import io
import os

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
RUNTIME_DATA_PATH = os.path.join(RUNTIME_DIR, "training_data.csv")

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


def load_model():
    # Prefer a model retrained during this run of the server, otherwise the committed one
    if os.path.exists(RUNTIME_MODEL_PATH):
        return joblib.load(RUNTIME_MODEL_PATH)
    return joblib.load(BASE_MODEL_PATH)


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
    """Add the new rows to the existing training data, refit the same pipeline and return a new bundle."""
    base_path = RUNTIME_DATA_PATH if os.path.exists(RUNTIME_DATA_PATH) else BASE_DATA_PATH
    base = pd.read_csv(base_path)
    combined = pd.concat([base, new_rows], ignore_index=True)

    X = combined[FEATURES]
    y = combined[TARGET]
    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

    # clone() copies the pipeline settings (scaler + encoder + model type) but not the old fitted values,
    # so preprocessing is re-fitted on the new training split only
    pipeline = clone(current_bundle["pipeline"])
    pipeline.fit(X_train, y_train)
    test_pred = pipeline.predict(X_test)

    new_bundle = dict(current_bundle)
    new_bundle["pipeline"] = pipeline
    new_bundle["test_mse"] = float(mean_squared_error(y_test, test_pred))

    os.makedirs(RUNTIME_DIR, exist_ok=True)
    joblib.dump(new_bundle, RUNTIME_MODEL_PATH, compress=3)
    combined.to_csv(RUNTIME_DATA_PATH, index=False)

    summary = {
        "model": new_bundle["model_name"],
        "rows_added": len(new_rows),
        "total_rows": len(combined),
        "old_test_mse": round(current_bundle.get("test_mse", float("nan")), 6),
        "new_test_mse": round(new_bundle["test_mse"], 6),
        "new_test_r2": round(float(r2_score(y_test, test_pred)), 4),
    }
    return new_bundle, summary
