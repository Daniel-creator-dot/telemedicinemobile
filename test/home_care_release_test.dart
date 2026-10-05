import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:telemedicinemobile/features/homecare/home_care_link.dart';
import 'package:telemedicinemobile/features/homecare/home_care_logic.dart';
import 'package:telemedicinemobile/features/homecare/home_care_refer.dart';
import 'package:telemedicinemobile/features/homecare/home_care_repository.dart';
import 'package:telemedicinemobile/features/homecare/home_care_screen.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  HomeCareRequest job({
    required String status,
    bool mine = false,
    bool taken = false,
  }) {
    return HomeCareRequest(
      id: 8,
      title: 'Wound dressing',
      status: status,
      mine: mine,
      taken: taken,
      location: 'Osu, Accra',
      claimedByLabel: taken || status == 'closed' ? 'Ama Boateng' : null,
    );
  }

  test('confirm copy stays in plain language', () {
    expect(
      homeCareReleaseConfirm,
      'Release this job so someone else can take it?',
    );
    expect(
      homeCareReactivateConfirm,
      'Put this job back so nurses can take it?',
    );
    expect(homeCareReleaseConfirm.toLowerCase().contains('onrender'), isFalse);
  });

  testWidgets('the person who took a job can release it', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeCareRequestCard(
            request: job(status: 'claimed', mine: true, taken: true),
            admin: false,
            onRelease: () => taps += 1,
            onReactivate: () => taps += 10,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Release this job'), findsOneWidget);
    expect(find.text('Reactivate'), findsNothing);
    expect(find.text('Take this request'), findsNothing);
    expect(find.textContaining('onrender'), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Release this job'));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('another nurse does not see Release on a taken job', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeCareRequestCard(
            request: job(status: 'claimed', taken: true),
            admin: false,
            onRelease: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Release this job'), findsNothing);
    expect(find.text('Take this request'), findsNothing);
    expect(find.text('Taken · Ama Boateng'), findsOneWidget);
  });

  testWidgets('an open job hides Release and Reactivate', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              HomeCareRequestCard(
                request: job(status: 'open'),
                admin: false,
                onRelease: () {},
                onTap: () {},
              ),
              HomeCareRequestCard(
                request: job(status: 'open'),
                admin: true,
                onReactivate: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Release this job'), findsNothing);
    expect(find.text('Reactivate'), findsNothing);
    expect(find.text('Take this request'), findsOneWidget);
    expect(find.text('Sent'), findsNothing);
    expect(find.text('Open'), findsWidgets);
  });

  testWidgets('an admin can reactivate a taken or closed job', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              HomeCareRequestCard(
                request: job(status: 'claimed', taken: true),
                admin: true,
                onReactivate: () => taps += 1,
                onRelease: () => taps += 10,
                onClose: () {},
              ),
              HomeCareRequestCard(
                request: job(status: 'closed'),
                admin: true,
                onReactivate: () => taps += 1,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Reactivate'), findsNWidgets(2));
    expect(find.text('Release this job'), findsNothing);
    expect(find.text('Mark closed'), findsOneWidget);
    expect(find.textContaining('onrender'), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Reactivate').first);
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('a referring doctor keeps close and does not release someone else', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HomeCareDoctorRequestTile(
            request: HomeCareRequest(
              id: 4,
              title: 'Wound dressing',
              status: 'claimed',
              mine: false,
              taken: true,
              referredByMe: true,
              claimedByLabel: 'Ama Boateng',
            ),
            onClose: _noop,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Mark closed'), findsOneWidget);
    expect(find.text('Release this job'), findsNothing);
    expect(find.text('Reactivate'), findsNothing);
  });

  testWidgets('the share page shows Release or Reactivate for the right role', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              HomeCareShareReviewCard(
                request: job(status: 'claimed', mine: true, taken: true),
                admin: false,
                showCommission: true,
                showShareLink: false,
                shareToken: '',
                onRelease: () {},
                onReactivate: () {},
              ),
              HomeCareShareReviewCard(
                request: job(status: 'closed'),
                admin: true,
                showCommission: false,
                showShareLink: false,
                shareToken: '',
                onReactivate: () {},
                onRelease: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Release this job'), findsOneWidget);
    expect(find.text('Reactivate'), findsOneWidget);
    expect(find.textContaining('onrender'), findsNothing);
  });

  testWidgets('release asks before it clears the job', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () => confirmReleaseHomeCareJob(context),
                child: const Text('Open release'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Open release'));
    await tester.pumpAndSettle();

    expect(find.text(homeCareReleaseConfirm), findsOneWidget);
    expect(find.text('Keep it'), findsOneWidget);
    expect(find.text('Release this job'), findsOneWidget);

    await tester.tap(find.text('Keep it'));
    await tester.pumpAndSettle();
    expect(find.text(homeCareReleaseConfirm), findsNothing);
  });
}

void _noop() {}
