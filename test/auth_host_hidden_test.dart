import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:telemedicinemobile/features/auth/auth_chrome.dart';

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
}
