import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:telemedicinemobile/features/homecare/home_care_refer.dart';
import 'package:telemedicinemobile/features/homecare/home_care_repository.dart';
import 'package:telemedicinemobile/features/homecare/home_care_sent.dart';
import 'package:telemedicinemobile/shared/widgets/home_care_commission.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  test('a doctor referral keeps the patient and who referred them', () {
    final request = HomeCareRequest.fromJson({
      'id': 12,
      'title': 'Wound dressing at home',
      'status': 'open',
      'mine': false,
      'patient_id': 44,
      'patient_name': 'Ama Mensah',
      'referrer_user_id': 7,
      'referrer_name': 'Dr. Boateng',
      'referred_by_me': true,
      'location': 'East Legon',
      'contact_phone': '0244000000',
    });

    expect(request.patientId, 44);
    expect(request.patientName, 'Ama Mensah');
    expect(request.referrerName, 'Dr. Boateng');
    expect(request.referredByMe, isTrue);
    expect(request.location, 'East Legon');
    expect(request.isOpen, isTrue);
    expect(request.pillLabel(admin: false), 'Sent');
    expect(request.pillLabel(admin: true), 'Open');
  });

  testWidgets('a doctor with no home care referrals sees the empty line', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HomeCareDoctorList(requests: []),
        ),
      ),
    );
    await tester.pump();

    expect(find.text(homeCareDoctorEmpty), findsOneWidget);
    expect(find.text('Refer to home care'), findsNothing);
    expect(find.textContaining('onrender'), findsNothing);
  });

  testWidgets('a taken referral shows Taken and the caregiver name', (tester) async {
    const request = HomeCareRequest(
      id: 3,
      title: 'Evening medication',
      status: 'claimed',
      mine: false,
      taken: true,
      patientName: 'Ama Mensah',
      location: 'Tema',
      contactPhone: '0244111222',
      claimedByLabel: 'Kojo Mensah',
      referredByMe: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeCareDoctorRequestTile(
            request: request,
            onAddNote: () {},
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Taken · Kojo Mensah'), findsOneWidget);
    expect(find.text('Tema'), findsOneWidget);
    expect(find.text('0244111222'), findsOneWidget);
    expect(find.text('Ama Mensah'), findsOneWidget);
    expect(find.text('Add a note'), findsOneWidget);
    expect(find.text('Mark closed'), findsOneWidget);
    expect(find.text(healynksHomeCareCommission), findsNothing);
    expect(find.textContaining('onrender'), findsNothing);
  });

  testWidgets('an open referral the doctor sent shows Sent', (tester) async {
    const request = HomeCareRequest(
      id: 12,
      title: 'Wound dressing at home',
      status: 'open',
      mine: false,
      taken: false,
      patientName: 'Ama Mensah',
      location: 'East Legon',
      contactPhone: '0244000000',
      referredByMe: true,
      postedByMe: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              HomeCareRequestSentBanner(onDismiss: () {}),
              HomeCareDoctorRequestTile(request: request),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Sent'), findsOneWidget);
    expect(find.text('Open'), findsNothing);
    expect(find.text('Take this request'), findsNothing);
    expect(find.text(homeCareRequestSent), findsOneWidget);
    expect(find.text('Wound dressing at home'), findsOneWidget);
    expect(find.text(healynksHomeCareCommission), findsNothing);
    expect(find.textContaining('onrender'), findsNothing);
  });
}
