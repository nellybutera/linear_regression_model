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
afcfta_aware (categorical). After removing refused / don't-know answers, 35,988 rows are used.

## Public API (Swagger UI)

_Render URL will be added after deployment._

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
