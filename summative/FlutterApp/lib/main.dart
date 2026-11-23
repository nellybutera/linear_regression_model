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
const brandBlue = Color(0xFF1F5F8B);
const genders = ['Man', 'Woman'];
const areas = ['Urban', 'Rural', 'Peri-Urban'];
const yesNo = ['No', 'Yes'];

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
      theme: ThemeData(colorSchemeSeed: brandBlue, useMaterial3: true),
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

  // categorical features (typed as text, matched to the values the API accepts)
  final genderController = TextEditingController();
  final areaController = TextEditingController();
  final countryController = TextEditingController();
  final employmentController = TextEditingController();
  final afcftaController = TextEditingController();

  bool loading = false;
  double? score;
  String? interpretation;
  String? errorText;

  @override
  void dispose() {
    for (final c in [
      ageController,
      educationController,
      borderEaseController,
      auRecognitionController,
      socialMediaController,
      genderController,
      areaController,
      countryController,
      employmentController,
      afcftaController,
    ]) {
      c.dispose();
    }
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

  // Ignore case, spaces and commas so "not working looking" matches "Not working, looking"
  String simplify(String text) =>
      text.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');

  String? matchOption(String value, List<String> options) {
    for (final option in options) {
      if (simplify(option) == simplify(value)) return option;
    }
    return null;
  }

  String? checkChoice(String? value, List<String> options, String allowed) {
    if (value == null || value.trim().isEmpty) return 'Required';
    if (matchOption(value, options) == null) return 'Must be $allowed';
    return null;
  }

  // label, controller and check for every field, used to list all problems in the result box
  List<(String, TextEditingController, String? Function(String?))> get fields =>
      [
        ('Age', ageController, (v) => checkWholeNumber(v, 18, 100)),
        ('Education', educationController, (v) => checkWholeNumber(v, 0, 9)),
        ('Border ease', borderEaseController, (v) => checkWholeNumber(v, 1, 4)),
        (
          'AU cares about us',
          auRecognitionController,
          (v) => checkWholeNumber(v, 1, 5),
        ),
        (
          'Social media news',
          socialMediaController,
          (v) => checkWholeNumber(v, 0, 4),
        ),
        (
          'Gender',
          genderController,
          (v) => checkChoice(v, genders, 'Man or Woman'),
        ),
        (
          'Area',
          areaController,
          (v) => checkChoice(v, areas, 'Urban, Rural or Peri-Urban'),
        ),
        (
          'Country',
          countryController,
          (v) => checkChoice(v, countries, 'one of the 38 survey countries'),
        ),
        (
          'Employment',
          employmentController,
          (v) => checkChoice(v, employmentOptions, 'one of the 4 options'),
        ),
        (
          'Heard of AfCFTA',
          afcftaController,
          (v) => checkChoice(v, yesNo, 'Yes or No'),
        ),
      ];

  Future<void> predict() async {
    setState(() {
      score = null;
      interpretation = null;
      errorText = null;
    });
    _formKey.currentState!.validate(); // highlights the bad fields
    final problems = [
      for (final (label, controller, check) in fields)
        if (check(controller.text) case final message?) '$label: $message',
    ];
    if (problems.isNotEmpty) {
      setState(
        () => errorText = 'Please fix these fields:\n${problems.join('\n')}',
      );
      return;
    }

    final body = {
      'age': int.parse(ageController.text.trim()),
      'education': int.parse(educationController.text.trim()),
      'border_ease': int.parse(borderEaseController.text.trim()),
      'au_recognition': int.parse(auRecognitionController.text.trim()),
      'social_media_news': int.parse(socialMediaController.text.trim()),
      'gender': matchOption(genderController.text, genders),
      'area': matchOption(areaController.text, areas),
      'country': matchOption(countryController.text, countries),
      'employment': matchOption(employmentController.text, employmentOptions),
      'afcfta_aware': matchOption(afcftaController.text, yesNo),
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

      // Check the status first: while Render wakes up it can send back an HTML error page, not JSON
      if (response.statusCode != 200 && response.statusCode != 422) {
        setState(
          () => errorText =
              'Server error (${response.statusCode}). The server may be waking up, please try again.',
        );
        return;
      }

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        setState(() {
          score = (data['openness_index'] as num).toDouble();
          interpretation = data['interpretation'] as String;
        });
      } else {
        setState(
          () => errorText =
              'The API rejected the input: ${readValidationError(data)}',
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

  // One labelled text field per model input (10 in total)
  Widget inputField(int index, String hint, {bool number = false}) {
    final (label, controller, check) = fields[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          helperText: hint,
          helperMaxLines: 2,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        validator: check,
      ),
    );
  }

  // two short fields next to each other
  Widget pair(Widget left, Widget right) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(child: right),
      ],
    );
  }

  Widget heading(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      child: Text(
        text,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
      ),
    );
  }

  // The display area: prediction, error, or a hint before the first try
  Widget resultBox() {
    final isError = errorText != null;
    String text;
    if (isError) {
      text = errorText!;
    } else if (score != null) {
      text = 'Openness index: ${score!.toStringAsFixed(3)}\n$interpretation';
    } else {
      text = 'Your prediction will appear here.';
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isError ? Colors.red.shade50 : Colors.grey.shade100,
        border: Border.all(color: isError ? Colors.red : Colors.grey.shade400),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: score != null && !isError ? 18 : 15,
          color: isError ? Colors.red.shade900 : Colors.black87,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BaraLens'),
        backgroundColor: brandBlue,
        foregroundColor: Colors.white,
      ),
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
                  'Predict how open a person is to African regional integration '
                  '(0 = closed, 1 = open) from their survey answers.',
                ),
                const SizedBox(height: 8),
                heading('Person'),
                pair(
                  inputField(0, '18 to 100', number: true),
                  inputField(5, 'Man or Woman'),
                ),
                inputField(
                  1,
                  '0 none, 3 primary, 5 secondary, 8 university, 9 post-grad',
                  number: true,
                ),
                inputField(
                  8,
                  'Full time, Part time, Not working looking, Not working not looking',
                ),
                heading('Location'),
                pair(
                  inputField(7, 'e.g. Kenya'),
                  inputField(6, 'Urban, Rural, Peri-Urban'),
                ),
                heading('Opinions and news'),
                pair(
                  inputField(2, '1 very hard to 4 very easy', number: true),
                  inputField(3, '1 disagree to 5 agree', number: true),
                ),
                pair(
                  inputField(4, '0 never to 4 every day', number: true),
                  inputField(9, 'Yes or No'),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: brandBlue),
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
                resultBox(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
