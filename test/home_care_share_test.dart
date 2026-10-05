import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:telemedicinemobile/features/homecare/home_care_link.dart';
import 'package:telemedicinemobile/features/homecare/home_care_refer.dart';
import 'package:telemedicinemobile/features/homecare/home_care_repository.dart';
import 'package:telemedicinemobile/features/homecare/home_care_screen.dart';
import 'package:telemedicinemobile/shared/widgets/home_care_commission.dart';

void main() {
  const token = 'aB3xY9kLm2Qp7Vw8Zn4Ht6';

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  test('a public share payload keeps the area and drops the phone', () {
    final snap = HomeCareShareSnapshot.fromJson({
      'title': 'Wound dressing',
      'location': 'Osu, Accra',
      'status': 'open',
      'taken': false,
      'contact_phone': '0244000000',
      'note': 'Bring gauze',
      'patient_id': 9,
      'share_token': token,
    });

    expect(snap.limited, isTrue);
    expect(snap.pendingReview, isFalse);
    expect(snap.request, isNull);
    expect(snap.title, 'Wound dressing');
    expect(snap.location, 'Osu, Accra');
    expect(snap.taken, isFalse);
  });

  test('a pending nurse share payload stays public', () {
    final snap = HomeCareShareSnapshot.fromJson({
      'title': 'Overnight watch',
      'location': 'Tema',
      'status': 'open',
      'taken': false,
      'pending_review': true,
      'contact_phone': '0244111222',
    });

    expect(snap.limited, isTrue);
    expect(snap.pendingReview, isTrue);
    expect(snap.request, isNull);
  });

  test('an approved nurse share payload keeps the phone while the job is open', () {
    final snap = HomeCareShareSnapshot.fromJson({
      'id': 8,
      'title': 'Wound dressing',
      'status': 'open',
      'location': 'Osu, Accra',
      'contact_phone': '0244000000',
      'note': 'Bring gauze',
      'share_token': token,
    });

    expect(snap.limited, isFalse);
    expect(snap.request!.contactPhone, '0244000000');
    expect(snap.request!.note, 'Bring gauze');
    expect(snap.request!.shareUrl, 'https://healynks.app/homecare/$token');
    expect(snap.request!.shareUrl!.contains('onrender'), isFalse);
  });

  testWidgets('a logged-out person sees the job, not the phone', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HomeCareShareGuestCard(
            title: 'Wound dressing',
            location: 'Osu, Accra',
            status: 'open',
            taken: false,
            message: 'Sign in, or join as a nurse, to review this home care job.',
            showActions: true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Wound dressing'), findsOneWidget);
    expect(find.text('Osu, Accra'), findsOneWidget);
    expect(find.text(healynksHomeCareCommission), findsOneWidget);
    expect(
      find.text('Sign in, or join as a nurse, to review this home care job.'),
      findsOneWidget,
    );
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Join as a nurse'), findsOneWidget);
    expect(find.textContaining('0244'), findsNothing);
    expect(find.textContaining('onrender'), findsNothing);
  });

  testWidgets('an admin copies the healynks.app link', (tester) async {
    const request = HomeCareRequest(
      id: 11,
      title: 'Wound dressing',
      status: 'open',
      mine: false,
      taken: false,
      postedByMe: true,
      location: 'Osu, Accra',
      shareToken: token,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HomeCareRequestCard(request: request, admin: true),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Sent'), findsOneWidget);
    expect(find.text('Copy link'), findsOneWidget);
    expect(find.text('https://healynks.app/homecare/$token'), findsOneWidget);
    expect(find.textContaining('onrender'), findsNothing);

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData' && call.arguments is Map) {
          copied = (call.arguments as Map)['text']?.toString();
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await tester.tap(find.widgetWithText(TextButton, 'Copy link'));
    await tester.pump();
    await tester.pump();

    expect(copied, 'https://healynks.app/homecare/$token');
    expect(find.text('Link copied.'), findsOneWidget);
  });

  testWidgets('the referring doctor sees Copy link on the referral', (tester) async {
    const request = HomeCareRequest(
      id: 12,
      title: 'Wound dressing at home',
      status: 'open',
      mine: false,
      taken: false,
      referredByMe: true,
      location: 'East Legon',
      shareToken: token,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: HomeCareDoctorRequestTile(request: request)),
      ),
    );
    await tester.pump();

    expect(find.text('Sent'), findsOneWidget);
    expect(find.text('Copy link'), findsOneWidget);
    expect(find.text('https://healynks.app/homecare/$token'), findsOneWidget);
    expect(find.textContaining('onrender'), findsNothing);
  });
}
