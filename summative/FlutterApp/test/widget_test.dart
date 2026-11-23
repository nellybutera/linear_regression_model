import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baralens/main.dart';

void main() {
  testWidgets('prediction page has 10 text fields and a predict button', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BaraLensApp());
    expect(find.text('BaraLens'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(10));

    await tester.scrollUntilVisible(
      find.text('Predict'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Predict'), findsOneWidget);

    // tapping Predict with an empty form should show the validation message, not call the API
    await tester.tap(find.text('Predict'));
    await tester.pump();
    final message = find.textContaining('Age: Required');
    await tester.scrollUntilVisible(
      message,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(message, findsOneWidget);
  });
}
