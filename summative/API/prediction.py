import os
from typing import Literal

import pandas as pd
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from retrain import FEATURES, load_model, retrain_lock, retrain_model, validate_training_csv

app = FastAPI(
    title="BaraLens API",
    description="Predicts a Regional Openness Index (0 = closed, 1 = open to African regional integration) "
                "from Afrobarometer Round 10 survey answers.",
    version="1.0.0",
)

# Explicit list of origins, no "*". Browsers reject "*" together with credentials anyway.
# Mobile apps don't send an Origin header, so the Flutter app on a phone is not blocked by this.
default_origins = [
    "http://localhost:3000",
    "http://localhost:8080",
    "http://localhost:5000",
    "http://127.0.0.1:8000",
]
extra_origins = [o.strip() for o in os.environ.get("EXTRA_ORIGINS", "").split(",") if o.strip()]

app.add_middleware(
    CORSMiddleware,
    allow_origins=default_origins + extra_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Content-Type", "Authorization", "Accept"],
)

# Loaded once at start-up; /retrain swaps this for the new model so /predict uses it immediately
model_bundle = load_model()

Country = Literal[
    "Angola", "Benin", "Botswana", "Cabo Verde", "Cameroon", "Chad", "Comoros", "Congo-Brazzaville",
    "Cote d'Ivoire", "Eswatini", "Gabon", "Gambia", "Ghana", "Guinea", "Guinea-Bissau", "Kenya",
    "Lesotho", "Liberia", "Madagascar", "Malawi", "Mali", "Mauritania", "Mauritius", "Morocco",
    "Mozambique", "Namibia", "Nigeria", "Sao Tome and Principe", "Senegal", "Seychelles",
    "Sierra Leone", "South Africa", "Tanzania", "Togo", "Tunisia", "Uganda", "Zambia", "Zimbabwe",
]


class SurveyInput(BaseModel):
    age: int = Field(..., strict=True, ge=18, le=100, description="Age in years (survey covers adults 18+)")
    education: int = Field(..., strict=True, ge=0, le=9, description="0 = no formal schooling ... 5 = secondary ... 8 = university ... 9 = post-graduate")
    border_ease: int = Field(..., strict=True, ge=1, le=4, description="How easy is it to cross borders in your region: 1 = very difficult ... 4 = very easy")
    au_recognition: int = Field(..., strict=True, ge=1, le=5, description="'The AU recognises our country's needs': 1 = strongly disagree ... 5 = strongly agree")
    social_media_news: int = Field(..., strict=True, ge=0, le=4, description="News from social media: 0 = never ... 4 = every day")
    gender: Literal["Man", "Woman"]
    area: Literal["Urban", "Rural", "Peri-Urban"]
    country: Country
    employment: Literal["Not working, not looking", "Not working, looking", "Part time", "Full time"]
    afcfta_aware: Literal["No", "Yes"] = Field(..., description="Has heard of the African Continental Free Trade Area")

    model_config = {
        "extra": "forbid",
        "json_schema_extra": {
            "example": {
                "age": 24, "education": 6, "border_ease": 2, "au_recognition": 4, "social_media_news": 4,
                "gender": "Woman", "area": "Urban", "country": "Kenya",
                "employment": "Not working, looking", "afcfta_aware": "Yes",
            }
        },
    }


def describe_score(score):
    if score < 0.4:
        return "Leans closed to regional integration"
    if score < 0.6:
        return "Mixed / moderate openness"
    return "Leans open to regional integration"


@app.get("/")
def home():
    return {"message": "BaraLens API is running. Go to /docs to try it.", "model": model_bundle["model_name"]}


@app.post("/predict")
def predict(data: SurveyInput):
    row = pd.DataFrame([data.model_dump()])[FEATURES]
    score = float(model_bundle["pipeline"].predict(row)[0])
    score = min(max(score, 0.0), 1.0)  # a linear model can go slightly outside 0-1, the index can't
    return {
        "openness_index": round(score, 4),
        "interpretation": describe_score(score),
        "model": model_bundle["model_name"],
    }


# A normal "def" (not async) so FastAPI runs the slow training in a worker thread and /predict keeps answering
@app.post("/retrain")
def retrain(file: UploadFile = File(..., description="CSV with the 10 feature columns plus openness_index")):
    global model_bundle
    if not file.filename.lower().endswith(".csv"):
        raise HTTPException(status_code=400, detail="Please upload a .csv file.")

    new_rows, errors = validate_training_csv(file.file.read())
    if errors:
        raise HTTPException(status_code=422, detail=errors)

    with retrain_lock:
        model_bundle, summary = retrain_model(model_bundle, new_rows)
    return summary
