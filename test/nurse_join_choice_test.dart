import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:telemedicinemobile/features/auth/professional_signup_screen.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('join screen offers a nurse clinician account beside doctor and agency', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(home: ProfessionalSignupScreen()),
    );
    await tester.pump();

    expect(find.text('Doctor'), findsOneWidget);
    expect(find.text('Nurse'), findsOneWidget);
    expect(find.text('Nurse agency'), findsOneWidget);
    expect(find.text('Create doctor account'), findsOneWidget);
    expect(find.textContaining('onrender'), findsNothing);
    expect(find.textContaining('https://'), findsNothing);

    await tester.tap(find.text('Nurse'));
    await tester.pump();

    expect(find.text('Create nurse account'), findsOneWidget);
    expect(find.text('Unit or area of practice'), findsOneWidget);
    expect(find.text('License or council number (optional)'), findsOneWidget);
    expect(find.text('Facility (optional)'), findsOneWidget);
    expect(find.text('Agency name'), findsNothing);

    await tester.tap(find.text('Nurse agency'));
    await tester.pump();

    expect(find.text('Create agency account'), findsOneWidget);
    expect(find.text('Agency name'), findsOneWidget);
    expect(find.text('Unit or area of practice'), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
  });
}
