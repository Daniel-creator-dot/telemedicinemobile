import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:telemedicinemobile/features/auth/auth_chrome.dart';
import 'package:telemedicinemobile/features/auth/auth_repository.dart';
import 'package:telemedicinemobile/features/auth/login_screen.dart';
import 'package:telemedicinemobile/features/auth/signup_screen.dart';
import 'package:telemedicinemobile/shared/widgets/app_launch_carousel.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('phone sign-in header does not print the API host', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AuthBrandHeader()),
      ),
    );
    await tester.pump();

    expect(find.text('Healynks'), findsOneWidget);
    expect(find.text('Care from doctors and nurses, wherever you are.'), findsOneWidget);
    expect(find.textContaining('onrender'), findsNothing);
    expect(find.textContaining('http://'), findsNothing);
    expect(find.textContaining('https://'), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('wide sign-in aside does not print the API host', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(
        home: AuthScaffold(child: SizedBox.shrink()),
      ),
    );
    await tester.pump();

    expect(find.text('Care that stays with you.'), findsOneWidget);
    expect(find.textContaining('onrender'), findsNothing);
    expect(find.textContaining('http://'), findsNothing);
    expect(find.textContaining('https://'), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('launch, sign-in, and patient signup stay readable on a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const MaterialApp(home: AppLaunchCarousel()));
    await tester.pump();
    expect(find.text('Healynks'), findsOneWidget);
    expect(find.text('Care from doctors and nurses, wherever you are.'), findsOneWidget);
    expect(find.text('Doctors'), findsOneWidget);
    expect(find.text('Nurses'), findsOneWidget);
    expect(find.textContaining('onrender'), findsNothing);
    expect(find.textContaining('telemedicine-server'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pump();
    expect(find.text('Join as a doctor, nurse, or nurse agency'), findsOneWidget);
    expect(find.textContaining('onrender'), findsNothing);
    expect(find.textContaining('telemedicine-server'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Forgot password?'));
    await tester.pump();
    await tester.tap(find.text('Forgot password?'));
    await tester.pump();
    expect(find.text('Reset your password'), findsOneWidget);
    expect(find.text('Send reset code'), findsOneWidget);
    expect(find.text('We will text a code to the mobile number on the account.'), findsOneWidget);
    expect(find.textContaining('onrender'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const MaterialApp(home: SignupScreen()));
    await tester.pump();
    expect(find.text('Create a patient account'), findsOneWidget);
    expect(find.textContaining('Ghana numbers can start with 0'), findsOneWidget);
    expect(find.textContaining('onrender'), findsNothing);
    expect(find.textContaining('Dev OTP'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 400));
  });

  test('auth errors stay in plain language and hide the API host', () {
    expect(
      AuthRepository.plainAuthMessage('Invalid credentials'),
      'Those details do not match an account.',
    );
    expect(
      AuthRepository.plainAuthMessage('Server error'),
      'Healynks could not complete that. Try again in a moment.',
    );
    expect(
      AuthRepository.plainAuthMessage('https://telemedicine-server-l2bj.onrender.com/api/auth/login'),
      isNot(contains('onrender')),
    );
    expect(
      AuthRepository.plainAuthMessage('https://telemedicine-server-l2bj.onrender.com/api/auth/login'),
      isNot(contains('telemedicine-server')),
    );
    expect(
      AuthRepository.plainAuthMessage('Invalid or expired OTP.'),
      'That code is not valid, or it has expired.',
    );
    expect(
      AuthRepository.plainAuthMessage('That code is not valid, or it has expired.'),
      'That code is not valid, or it has expired.',
    );
  });

  testWidgets('reset asks for a code and a password of at least 8 characters', (tester) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pump();
    await tester.tap(find.text('Forgot password?'));
    await tester.pump();
    expect(find.text('Send reset code'), findsOneWidget);

    await tester.tap(find.text('I already have a code'));
    await tester.pump();
    expect(find.text('Choose a new password'), findsOneWidget);
    expect(find.text('Code from the text'), findsOneWidget);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '0241555000');
    await tester.enterText(fields.at(1), '123456');
    await tester.enterText(fields.at(2), 'short');
    await tester.tap(find.text('Save new password'));
    await tester.pump();
    expect(find.text('Use at least 8 characters.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
