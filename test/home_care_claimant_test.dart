import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:telemedicinemobile/features/homecare/home_care_claimant.dart';
import 'package:telemedicinemobile/features/homecare/home_care_link.dart';
import 'package:telemedicinemobile/features/homecare/home_care_refer.dart';
import 'package:telemedicinemobile/features/homecare/home_care_repository.dart';
import 'package:telemedicinemobile/features/homecare/home_care_screen.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  const claimant = HomeCareClaimant(
    name: 'Ama Boateng',
    kind: 'nurse',
    phone: '0555111222',
    practiceArea: 'General nursing',
    licenseNumber: 'NMC-2048',
    facility: 'Ridge Hospital',
  );

  const agency = HomeCareClaimant(
    name: 'Kojo Mensah',
    kind: 'agency',
    phone: '0200888777',
    agencyName: 'Ridge Care Agency',
    region: 'Greater Accra',
    town: 'East Legon',
  );

  HomeCareRequest taken({
    HomeCareClaimant? who,
    bool referredByMe = false,
    String? contactPhone = '0244000000',
  }) {
    return HomeCareRequest(
      id: 8,
      title: 'Evening medication',
      status: 'claimed',
      mine: false,
      taken: true,
      location: 'Tema',
      contactPhone: contactPhone,
      claimedByLabel: who?.isAgency == true ? who!.agencyName : who?.name,
      claimedByName: who?.name,
      claimedByAgency: who?.agencyName,
      referredByMe: referredByMe,
      postedByMe: true,
      claimant: who,
    );
  }

  test('a claimant payload keeps the nurse phone and drops empty fields', () {
    final request = HomeCareRequest.fromJson({
      'id': 8,
      'title': 'Evening medication',
      'status': 'claimed',
      'claimed_by_label': 'Ama Boateng',
      'claimant': {
        'name': 'Ama Boateng',
        'phone': '0555111222',
        'kind': 'nurse',
        'practice_area': 'General nursing',
        'license_number': 'NMC-2048',
        'facility': 'Ridge Hospital',
        'agency_name': '',
        'password': 'secret',
        'id': 3,
      },
    });

    expect(request.claimant, isNotNull);
    expect(request.claimant!.name, 'Ama Boateng');
    expect(request.claimant!.phone, '0555111222');
    expect(request.claimant!.roleLabel, 'Nurse');
    expect(request.claimant!.practiceArea, 'General nursing');
    expect(request.claimant!.licenseNumber, 'NMC-2048');
    expect(request.claimant!.facility, 'Ridge Hospital');
    expect(request.claimant!.agencyName, isNull);
    expect(request.claimant!.detailLines, contains('Role · Nurse'));
    expect(request.claimant!.detailLines, contains('Practice area · General nursing'));
    expect(request.claimant!.detailLines, contains('License · NMC-2048'));
    expect(request.claimant!.detailLines.join(' '), isNot(contains('secret')));
    expect(request.claimerLine, 'Taken · Ama Boateng');
  });

  test('a missing claimant stays off the card other nurses already see', () {
    final request = HomeCareRequest.fromJson({
      'id': 4,
      'title': 'Wound dressing',
      'status': 'claimed',
      'claimed_by_label': 'Ama Boateng',
    });

    expect(request.claimant, isNull);
    expect(request.pillLabel(admin: false), 'Taken · Ama Boateng');
  });

  testWidgets('an admin card shows the nurse block apart from the family number', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeCareRequestCard(request: taken(who: claimant), admin: true),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Nurse'), findsWidgets);
    expect(find.text('Ama Boateng'), findsWidgets);
    expect(find.text('0555111222'), findsOneWidget);
    expect(find.text('Call'), findsOneWidget);
    expect(find.text('Role · Nurse'), findsOneWidget);
    expect(find.text('Practice area · General nursing'), findsOneWidget);
    expect(find.text('License · NMC-2048'), findsOneWidget);
    expect(find.text('Facility · Ridge Hospital'), findsOneWidget);
    expect(find.text('Patient or family contact'), findsOneWidget);
    expect(find.text('0244000000'), findsOneWidget);
    expect(find.text('No phone on this profile.'), findsNothing);
    expect(find.textContaining('onrender'), findsNothing);
  });

  testWidgets('an agency block lists the agency, region, and town', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeCareRequestCard(request: taken(who: agency), admin: true),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Nurse'), findsOneWidget);
    expect(find.text('Kojo Mensah'), findsWidgets);
    expect(find.text('Role · Agency'), findsOneWidget);
    expect(find.text('Agency · Ridge Care Agency'), findsOneWidget);
    expect(find.text('Region · Greater Accra'), findsOneWidget);
    expect(find.text('Town · East Legon'), findsOneWidget);
    expect(find.text('Call'), findsOneWidget);
    expect(find.text('Practice area · General nursing'), findsNothing);
  });

  testWidgets('a profile with no phone still names the nurse', (tester) async {
    const quiet = HomeCareClaimant(name: 'Ama Boateng', kind: 'nurse');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeCareRequestCard(
            request: taken(who: quiet, contactPhone: null),
            admin: true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Ama Boateng'), findsWidgets);
    expect(find.text('No phone on this profile.'), findsOneWidget);
    expect(find.text('Call'), findsNothing);
  });

  testWidgets('another nurse still sees only Taken and the name', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeCareRequestCard(request: taken(who: claimant), admin: false),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Taken · Ama Boateng'), findsOneWidget);
    expect(find.text('0555111222'), findsNothing);
    expect(find.text('Call'), findsNothing);
    expect(find.text('Patient or family contact'), findsNothing);
    expect(find.text('Nurse'), findsNothing);
  });

  testWidgets('the referring doctor sees the same nurse block', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeCareDoctorRequestTile(
            request: taken(who: claimant, referredByMe: true),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Taken · Ama Boateng'), findsOneWidget);
    expect(find.text('Nurse'), findsWidgets);
    expect(find.text('0555111222'), findsOneWidget);
    expect(find.text('Call'), findsOneWidget);
    expect(find.text('Patient or family contact'), findsOneWidget);
    expect(find.text('0244000000'), findsOneWidget);
  });

  testWidgets('a doctor who did not refer the patient does not see the phone', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeCareDoctorRequestTile(
            request: taken(who: claimant),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Taken · Ama Boateng'), findsOneWidget);
    expect(find.text('0555111222'), findsNothing);
    expect(find.text('Call'), findsNothing);
  });

  testWidgets('an admin on the share page sees the nurse who took the job', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeCareShareReviewCard(
            request: taken(who: agency),
            admin: true,
            showCommission: false,
            showShareLink: true,
            shareToken: 'aB3xY9kLm2Qp7Vw8Zn4Ht6',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Nurse'), findsOneWidget);
    expect(find.text('Kojo Mensah'), findsWidgets);
    expect(find.text('0200888777'), findsOneWidget);
    expect(find.text('Call'), findsOneWidget);
    expect(find.text('Agency · Ridge Care Agency'), findsOneWidget);
    expect(find.text('Patient or family contact'), findsOneWidget);
    expect(find.text('0244000000'), findsOneWidget);
    expect(find.textContaining('onrender'), findsNothing);
  });
}
