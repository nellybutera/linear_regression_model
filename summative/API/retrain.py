import io
import os
import threading

import joblib
import pandas as pd
from sklearn.base import clone
from sklearn.metrics import mean_squared_error, r2_score
from sklearn.model_selection import train_test_split

API_DIR = os.path.dirname(os.path.abspath(__file__))
BASE_MODEL_PATH = os.path.join(API_DIR, "best_model.pkl")
BASE_DATA_PATH = os.path.join(API_DIR, "training_data.csv")

# Render's free tier has an ephemeral disk: anything written at runtime is lost on restart.
# So the retrained model is kept in memory (used right away by /predict) and also written to
# a writable folder. After a restart the API falls back to the committed best_model.pkl.
RUNTIME_DIR = os.environ.get("MODEL_DIR", "/tmp/baralens" if os.name != "nt" else os.path.join(API_DIR, "runtime"))
RUNTIME_MODEL_PATH = os.path.join(RUNTIME_DIR, "best_model.pkl")
UPLOADS_PATH = os.path.join(RUNTIME_DIR, "uploaded_rows.csv")

NUMERIC_RANGES = {
    "age": (18, 100),
    "education": (0, 9),
    "border_ease": (1, 4),
    "au_recognition": (1, 5),
    "social_media_news": (0, 4),
}

ALLOWED_CATEGORIES = {
    "gender": ["Man", "Woman"],
    "area": ["Urban", "Rural", "Peri-Urban"],
    "country": [
        "Angola", "Benin", "Botswana", "Cabo Verde", "Cameroon", "Chad", "Comoros", "Congo-Brazzaville",
        "Cote d'Ivoire", "Eswatini", "Gabon", "Gambia", "Ghana", "Guinea", "Guinea-Bissau", "Kenya",
        "Lesotho", "Liberia", "Madagascar", "Malawi", "Mali", "Mauritania", "Mauritius", "Morocco",
        "Mozambique", "Namibia", "Nigeria", "Sao Tome and Principe", "Senegal", "Seychelles",
        "Sierra Leone", "South Africa", "Tanzania", "Togo", "Tunisia", "Uganda", "Zambia", "Zimbabwe",
    ],
    "employment": ["Not working, not looking", "Not working, looking", "Part time", "Full time"],
    "afcfta_aware": ["No", "Yes"],
}

FEATURES = list(NUMERIC_RANGES) + list(ALLOWED_CATEGORIES)
TARGET = "openness_index"
MIN_NEW_ROWS = 20
# A retrained model replaces the current one only if its test MSE is not more than 2% worse.
# This stops a bad upload (e.g. every target set to 1) from silently breaking /predict.
MAX_WORSE = 1.02

# Only one retrain at a time, so two uploads can't overwrite each other's files
retrain_lock = threading.Lock()


def load_model():
    # Prefer a model retrained during this run of the server, otherwise the committed one
    if os.path.exists(RUNTIME_MODEL_PATH):
        return joblib.load(RUNTIME_MODEL_PATH)
    return joblib.load(BASE_MODEL_PATH)


def predict_one_row(row, bundle=None):
    # Shared by the notebook (one test row) and by /predict, so both predict the exact same way.
    # Loads the saved model when no bundle is passed in. row = one-row DataFrame or dict of the 10 features.
    if bundle is None:
        bundle = joblib.load(BASE_MODEL_PATH)
    if isinstance(row, dict):
        row = pd.DataFrame([row])
    score = float(bundle["pipeline"].predict(row[FEATURES])[0])
    return min(max(score, 0.0), 1.0)  # a linear model can go slightly outside 0-1, the index can't


def load_base_split():
    # Same split as the notebook (test_size=0.2, random_state=42), so the test set is fixed
    # and old and new models are always compared on exactly the same rows
    base = pd.read_csv(BASE_DATA_PATH)
    train, test = train_test_split(base, test_size=0.2, random_state=42)
    return train, test


def validate_training_csv(file_bytes):
    """Read the uploaded CSV and return (clean_df, list_of_errors)."""
    try:
        df = pd.read_csv(io.BytesIO(file_bytes))
    except Exception:
        return None, ["Could not read the file as CSV."]

    errors = []
    missing_cols = [c for c in FEATURES + [TARGET] if c not in df.columns]
    if missing_cols:
        return None, [f"Missing required columns: {', '.join(missing_cols)}"]

    df = df[FEATURES + [TARGET]].copy()
    if df.isna().any().any():
        bad = df.columns[df.isna().any()].tolist()
        errors.append(f"Empty values found in columns: {', '.join(bad)}")

    for col, (low, high) in NUMERIC_RANGES.items():
        values = pd.to_numeric(df[col], errors="coerce")
        if values.isna().any():
            errors.append(f"Column '{col}' must contain numbers only.")
        elif not (values % 1 == 0).all():
            errors.append(f"Column '{col}' must contain whole numbers.")
        elif not values.between(low, high).all():
            errors.append(f"Column '{col}' must be between {low} and {high}.")
        df[col] = values

    target = pd.to_numeric(df[TARGET], errors="coerce")
    if target.isna().any() or not target.between(0, 1).all():
        errors.append(f"Column '{TARGET}' must be a number between 0 and 1.")
    df[TARGET] = target

    for col, allowed in ALLOWED_CATEGORIES.items():
        bad_values = sorted(set(df[col].dropna().astype(str)) - set(allowed))
        if bad_values:
            errors.append(f"Column '{col}' has unknown values: {', '.join(bad_values[:5])}")

    if len(df) < MIN_NEW_ROWS:
        errors.append(f"Need at least {MIN_NEW_ROWS} rows to retrain, got {len(df)}.")

    return (None, errors) if errors else (df, [])


def retrain_model(current_bundle, new_rows):
    """Train on (original training rows + all uploaded rows) and test on the fixed test set.
    Returns (bundle_to_use, summary). The current model is kept if the new one is clearly worse."""
    base_train, test = load_base_split()

    # Keep every new row uploaded since the server started, without duplicates
    previous_uploads = pd.read_csv(UPLOADS_PATH) if os.path.exists(UPLOADS_PATH) else pd.DataFrame(columns=new_rows.columns)
    all_uploads = pd.concat([previous_uploads, new_rows], ignore_index=True).drop_duplicates()
    rows_added = len(all_uploads) - len(previous_uploads)

    train = pd.concat([base_train, all_uploads], ignore_index=True).drop_duplicates()
    X_test, y_test = test[FEATURES], test[TARGET]

    # clone() copies the pipeline settings (scaler + encoder + model type) but not the old fitted values,
    # so preprocessing is re-fitted on the new training data only
    new_pipeline = clone(current_bundle["pipeline"])
    new_pipeline.fit(train[FEATURES], train[TARGET])

    old_mse = mean_squared_error(y_test, current_bundle["pipeline"].predict(X_test))
    new_pred = new_pipeline.predict(X_test)
    new_mse = mean_squared_error(y_test, new_pred)

    summary = {
        "model": current_bundle["model_name"],
        "rows_uploaded": len(new_rows),
        "new_rows_added": rows_added,
        "training_rows": len(train),
        "test_rows": len(test),
        "old_test_mse": round(float(old_mse), 6),
        "new_test_mse": round(float(new_mse), 6),
        "new_test_r2": round(float(r2_score(y_test, new_pred)), 4),
    }

    if new_mse > old_mse * MAX_WORSE:
        summary["model_updated"] = False
        summary["new_rows_added"] = 0
        summary["message"] = ("New model was worse on the test set, so the current model was kept "
                              "and the uploaded rows were not saved.")
        return current_bundle, summary

    new_bundle = dict(current_bundle)
    new_bundle["pipeline"] = new_pipeline
    new_bundle["test_mse"] = float(new_mse)

    os.makedirs(RUNTIME_DIR, exist_ok=True)
    joblib.dump(new_bundle, RUNTIME_MODEL_PATH, compress=3)
    all_uploads.to_csv(UPLOADS_PATH, index=False)

    summary["model_updated"] = True
    summary["message"] = "Model retrained and now used by /predict."
    return new_bundle, summary
