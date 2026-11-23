import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// Deployed Render API. For local testing run:
// flutter run --dart-define=API_URL=http://10.0.2.2:8000   (10.0.2.2 = the PC's localhost from the Android emulator)
const String apiUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'https://baralens-api.onrender.com',
);

const countries = [
  'Angola',
  'Benin',
  'Botswana',
  'Cabo Verde',
  'Cameroon',
  'Chad',
  'Comoros',
  'Congo-Brazzaville',
  "Cote d'Ivoire",
  'Eswatini',
  'Gabon',
  'Gambia',
  'Ghana',
  'Guinea',
  'Guinea-Bissau',
  'Kenya',
  'Lesotho',
  'Liberia',
  'Madagascar',
  'Malawi',
  'Mali',
  'Mauritania',
  'Mauritius',
  'Morocco',
  'Mozambique',
  'Namibia',
  'Nigeria',
  'Sao Tome and Principe',
  'Senegal',
  'Seychelles',
  'Sierra Leone',
  'South Africa',
  'Tanzania',
  'Togo',
  'Tunisia',
  'Uganda',
  'Zambia',
  'Zimbabwe',
];
const employmentOptions = [
  'Not working, not looking',
  'Not working, looking',
  'Part time',
  'Full time',
];

void main() {
  runApp(const BaraLensApp());
}

class BaraLensApp extends StatelessWidget {
  const BaraLensApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BaraLens',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const PredictionPage(),
    );
  }
}

class PredictionPage extends StatefulWidget {
  const PredictionPage({super.key});

  @override
  State<PredictionPage> createState() => _PredictionPageState();
}

class _PredictionPageState extends State<PredictionPage> {
  final _formKey = GlobalKey<FormState>();

  // numeric features
  final ageController = TextEditingController();
  final educationController = TextEditingController();
  final borderEaseController = TextEditingController();
  final auRecognitionController = TextEditingController();
  final socialMediaController = TextEditingController();

  // categorical features
  String? gender;
  String? area;
  String? country;
  String? employment;
  String? afcftaAware;

  bool loading = false;
  String? resultText;
  String? errorText;

  @override
  void dispose() {
    ageController.dispose();
    educationController.dispose();
    borderEaseController.dispose();
    auRecognitionController.dispose();
    socialMediaController.dispose();
    super.dispose();
  }

  // Same ranges as the API's Pydantic model, so most mistakes are caught before sending
  String? checkWholeNumber(String? value, int min, int max) {
    if (value == null || value.trim().isEmpty) return 'Required';
    final number = int.tryParse(value.trim());
    if (number == null) return 'Enter a whole number';
    if (number < min || number > max) return 'Must be between $min and $max';
    return null;
  }

  Future<void> predict() async {
    setState(() {
      resultText = null;
      errorText = null;
    });
    if (!_formKey.currentState!.validate()) {
      setState(() => errorText = 'Please fix the highlighted fields.');
      return;
    }

    final body = {
      'age': int.parse(ageController.text.trim()),
      'education': int.parse(educationController.text.trim()),
      'border_ease': int.parse(borderEaseController.text.trim()),
      'au_recognition': int.parse(auRecognitionController.text.trim()),
      'social_media_news': int.parse(socialMediaController.text.trim()),
      'gender': gender,
      'area': area,
      'country': country,
      'employment': employment,
      'afcfta_aware': afcftaAware,
    };

    setState(() => loading = true);
    try {
      // Render's free plan sleeps when idle, so the first call can take close to a minute
      final response = await http
          .post(
            Uri.parse('$apiUrl/predict'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 90));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final score = (data['openness_index'] as num).toDouble();
        setState(
          () => resultText =
              'Regional Openness Index: ${score.toStringAsFixed(3)}\n${data['interpretation']}',
        );
      } else if (response.statusCode == 422) {
        setState(
          () => errorText =
              'The API rejected the input: ${readValidationError(data)}',
        );
      } else {
        setState(
          () => errorText =
              'Server error (${response.statusCode}). Please try again.',
        );
      }
    } on TimeoutException {
      setState(
        () => errorText = 'The server took too long to answer. It may be waking up, try again.',
      );
    } catch (e) {
      setState(
        () => errorText =
            'Could not reach the API. Check your internet connection.',
      );
    } finally {
      setState(() => loading = false);
    }
  }

  String readValidationError(dynamic data) {
    final detail = data['detail'];
    if (detail is List && detail.isNotEmpty) {
      final first = detail.first;
      final field = (first['loc'] as List).last;
      return '$field: ${first['msg']}';
    }
    return detail.toString();
  }

  Widget numberField(
    TextEditingController controller,
    String label,
    String hint,
    int min,
    int max,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          helperText: hint,
          border: const OutlineInputBorder(),
        ),
        validator: (value) => checkWholeNumber(value, min, max),
      ),
    );
  }

  Widget dropdownField(
    String label,
    String? value,
    List<String> options,
    ValueChanged<String?> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: options
            .map((o) => DropdownMenuItem(value: o, child: Text(o)))
            .toList(),
        onChanged: onChanged,
        validator: (v) => v == null ? 'Please choose one' : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BaraLens')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          // SingleChildScrollView + Column (not ListView) so every field stays built and gets validated,
          // even the ones scrolled off screen
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Predict how open a person is to African regional integration (0 = closed, 1 = open), '
                  'based on Afrobarometer Round 10 survey answers.',
                ),
                const SizedBox(height: 16),
                numberField(ageController, 'Age', '18 to 100', 18, 100),
                numberField(
                  educationController,
                  'Education level',
                  '0 = no schooling, 3 = primary, 5 = secondary, 8 = university, 9 = post-graduate',
                  0,
                  9,
                ),
                numberField(
                  borderEaseController,
                  'Ease of crossing borders',
                  '1 = very difficult, 2 = difficult, 3 = easy, 4 = very easy',
                  1,
                  4,
                ),
                numberField(
                  auRecognitionController,
                  'AU recognises our country\'s needs',
                  '1 = strongly disagree ... 3 = neutral ... 5 = strongly agree',
                  1,
                  5,
                ),
                numberField(
                  socialMediaController,
                  'News from social media',
                  '0 = never, 1 = < once a month, 2 = few times a month, 3 = few times a week, 4 = every day',
                  0,
                  4,
                ),
                dropdownField('Gender', gender, [
                  'Man',
                  'Woman',
                ], (v) => setState(() => gender = v)),
                dropdownField('Area', area, [
                  'Urban',
                  'Rural',
                  'Peri-Urban',
                ], (v) => setState(() => area = v)),
                dropdownField(
                  'Country',
                  country,
                  countries,
                  (v) => setState(() => country = v),
                ),
                dropdownField(
                  'Employment',
                  employment,
                  employmentOptions,
                  (v) => setState(() => employment = v),
                ),
                dropdownField(
                  'Heard of AfCFTA (free trade area)?',
                  afcftaAware,
                  ['No', 'Yes'],
                  (v) => setState(() => afcftaAware = v),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: loading ? null : predict,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Predict', style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: errorText != null
                        ? Colors.red.shade50
                        : Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    errorText ??
                        resultText ??
                        'Your prediction will appear here.',
                    style: TextStyle(
                      fontSize: 16,
                      color: errorText != null
                          ? Colors.red.shade800
                          : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
