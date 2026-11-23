# BaraLens: Understanding African Perspectives on Regional Integration Through Machine Learning

## Mission

Many young Africans only meet politics through social media, headlines or public debates, and have few chances to see how laws
are made or how African countries cooperate through regional organisations. My mission is to learn deeply about governance and
regional integration and to help more young people understand the system from the inside.
BaraLens explores how demographic, educational and governance-related characteristics relate to people's openness to African
regional integration. It does **not** measure leadership potential or the effectiveness of civic education.

## Dataset

**Afrobarometer Round 10 merged dataset** (38 countries, 2024/2025, release 25 Feb 2026): 50,961 face-to-face interviews with adults, 425 variables.
- Data: https://www.afrobarometer.org/survey-resource/merged-round-10-data-38-countries-2025/
- Codebook: https://www.afrobarometer.org/survey-resource/merged-round-10-codebook-38-countries-2025/

**Target:** Regional Openness Index (0–1), the average of 7 attitude items on migrants and refugees (Q73A–C), open trade and free
movement (Q76A–B) and accepting immigrants/refugees as neighbours (Q88D, Q88F).
**Predictors (10):** age, education, border_ease, au_recognition, social_media_news (numeric) and gender, area, country, employment,
afcfta_aware (categorical). After removing refused / don't-know answers there are 35,988 usable rows: 35,488 are used to build the models and 500 are kept aside as "new survey data" (`summative/API/retrain_sample.csv`) to demonstrate retraining.

## Public API (Swagger UI)

**Swagger UI:** https://baralens-api.onrender.com/docs

- `POST /predict` – send the 10 features as JSON, get back the predicted openness index (0–1)
- `POST /retrain` – upload a CSV with the 10 feature columns plus `openness_index`; the model is retrained and used by `/predict` straight away

Render settings: root directory `summative/API`, build `pip install -r requirements.txt`, start `uvicorn prediction:app --host 0.0.0.0 --port $PORT` (Python version from `summative/API/.python-version`).

Hosted on Render's free plan, so the first request after a quiet period can take up to ~1 minute while the server wakes up.
`/retrain` trains on the original training rows plus the uploaded rows (duplicates removed) and scores the old and new model on the same fixed test set; the new model only replaces the old one if its test MSE is not more than 2% worse. A retrained model lives in memory and in `/tmp`; Render's free disk is not permanent, so after a restart the API goes back to the committed `best_model.pkl`.

## Demo video

_Link will be added._

## How to run

### Notebook
```bash
cd summative
uv sync
uv run jupyter nbconvert --to notebook --execute --inplace linear_regression/multivariate.ipynb
```

### API locally
```bash
cd summative/API
uv sync
uv run uvicorn prediction:app --reload
# open http://127.0.0.1:8000/docs
```

### Mobile app (Flutter)
Needs Flutter installed and an Android emulator running (or a phone with USB debugging on).
```bash
cd summative/FlutterApp
flutter pub get
flutter run
```
The app calls the live API at https://baralens-api.onrender.com by default. Fill in the 10 fields and tap **Predict**.
To use a local API instead: `flutter run --dart-define=API_URL=http://10.0.2.2:8000` (10.0.2.2 is the PC's localhost from the Android emulator).
