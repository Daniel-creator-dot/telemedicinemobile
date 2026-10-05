import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:telemedicinemobile/features/homecare/home_care_options.dart';
import 'package:telemedicinemobile/features/homecare/home_care_repository.dart';
import 'package:telemedicinemobile/features/homecare/home_care_screen.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  test('care options keep the catalog order and one extra label', () {
    final options = normalizeHomeCareOptions([
      'overnight',
      'Stay-in',
      'Not a catalog item',
      'stay-in',
      'Wound care',
    ]);
    expect(options, ['Stay-in', 'Overnight', 'Wound care']);
    expect(normalizeHomeCareCustomOption('  feeding   help  '), 'feeding help');
    expect(normalizeHomeCareCustomOption('   '), isNull);
    expect(normalizeHomeCareCustomOption('x' * 80)!.length, 48);

    final chips = homeCareChipLabels(options, 'feeding help');
    expect(chips, ['Stay-in', 'Overnight', 'Wound care', 'feeding help']);
    expect(homeCareChipLabels(options, 'Stay-in'), options);
    expect(homeCareShowsStayIn(options, null), isTrue);
    expect(homeCareShowsStayIn(const ['Day visit'], 'stay in'), isTrue);
    expect(homeCareShowsStayIn(const ['Day visit'], 'feeding help'), isFalse);
    expect(homeCareStayInLine, 'The caregiver stays in the home.');
  });

  test('a request keeps its options when it is marked sent', () {
    final request = HomeCareRequest.fromJson({
      'id': 9,
      'title': 'Home watch',
      'status': 'open',
      'care_options': ['Stay-in', 'Companionship'],
      'custom_option': 'Feeding help',
      'share_token': 'aB3xY9kLm2Qp7Vw8Zn4Ht6',
    });

    expect(request.optionChips, ['Stay-in', 'Companionship', 'Feeding help']);
    expect(request.showsStayIn, isTrue);
    expect(request.shareToken, 'aB3xY9kLm2Qp7Vw8Zn4Ht6');

    final sent = request.markedSent();
    expect(sent.careOptions, request.careOptions);
    expect(sent.customOption, 'Feeding help');
    expect(sent.shareToken, request.shareToken);
    expect(sent.pillLabel(admin: true), 'Sent');
  });

  testWidgets('admin card shows Edit, option chips, and the stay-in line', (tester) async {
    const request = HomeCareRequest(
      id: 4,
      title: 'Home watch',
      status: 'open',
      mine: false,
      taken: false,
      postedByMe: true,
      location: 'East Legon',
      careOptions: ['Stay-in', 'Wound care'],
      customOption: 'Feeding help',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeCareRequestCard(
            request: request,
            admin: true,
            onEdit: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Stay-in'), findsOneWidget);
    expect(find.text('Wound care'), findsOneWidget);
    expect(find.text('Feeding help'), findsOneWidget);
    expect(find.text(homeCareStayInLine), findsOneWidget);
    expect(find.text('Sent'), findsOneWidget);
    expect(find.textContaining('onrender'), findsNothing);
  });

  testWidgets('a nurse card shows the chips and does not show Edit', (tester) async {
    const request = HomeCareRequest(
      id: 4,
      title: 'Home watch',
      status: 'open',
      mine: false,
      taken: false,
      careOptions: ['Stay-in'],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HomeCareRequestCard(request: request, admin: false),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Edit'), findsNothing);
    expect(find.text('Stay-in'), findsOneWidget);
    expect(find.text(homeCareStayInLine), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
  });
}
