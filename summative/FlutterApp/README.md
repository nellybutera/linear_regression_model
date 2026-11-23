# BaraLens app

Single-page Flutter app for BaraLens. You fill in the 10 survey answers (age, education, border ease, AU recognition, social media news, gender, area, country, employment, AfCFTA awareness), tap **Predict**, and it shows the predicted Regional Openness Index (0 to 1) from the BaraLens API.

## Run it
```bash
flutter pub get
flutter run
```
It uses the live API at https://baralens-api.onrender.com. The free server sleeps, so the first prediction can take up to about a minute.

To use a local API instead: `flutter run --dart-define=API_URL=http://10.0.2.2:8000`
