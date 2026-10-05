import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:telemedicinemobile/features/auth/larger_text.dart';
import 'package:telemedicinemobile/features/auth/simple_signup_step.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('easier signup step uses large type and a tall button', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SimpleSignupStep(
            question: 'What is your first name?',
            body: 'This is the name we will use when we talk with you.',
            buttonLabel: 'Next',
            onPressed: () {},
          ),
        ),
      ),
    );

    final question = tester.widget<Text>(find.text('What is your first name?'));
    final body = tester.widget<Text>(find.text('This is the name we will use when we talk with you.'));
    expect(question.style!.fontSize, greaterThanOrEqualTo(22));
    expect(body.style!.fontSize, greaterThanOrEqualTo(18));
    expect(tester.getSize(find.byKey(const Key('simple-signup-next'))).height, greaterThanOrEqualTo(56));
  });

  testWidgets('Larger text toggle bumps the question for the session', (tester) async {
    final controller = LargerTextController();
    await tester.pumpWidget(
      MaterialApp(
        home: LargerTextScope(
          controller: controller,
          child: const _LargerHarness(),
        ),
      ),
    );

    expect(
      tester.widget<Text>(find.text('What is your first name?')).style!.fontSize,
      simpleQuestionSize(false),
    );

    await tester.tap(find.text('Larger text'));
    await tester.pump();

    expect(find.text('Larger text on'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('What is your first name?')).style!.fontSize,
      greaterThan(simpleQuestionSize(false)),
    );
    expect(controller.larger, isTrue);
    expect(tester.getSize(find.byKey(const Key('simple-signup-next'))).height, greaterThanOrEqualTo(64));
  });
}

class _LargerHarness extends StatelessWidget {
  const _LargerHarness();

  @override
  Widget build(BuildContext context) {
    final larger = LargerTextScope.largerOf(context);
    return Scaffold(
      body: Column(
        children: [
          const LargerTextToggle(),
          SimpleSignupStep(
            larger: larger,
            question: 'What is your first name?',
            body: 'This is the name we will use when we talk with you.',
            buttonLabel: 'Next',
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}
