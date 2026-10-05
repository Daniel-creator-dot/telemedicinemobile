import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:telemedicinemobile/features/homecare/home_care_chat.dart';
import 'package:telemedicinemobile/features/homecare/home_care_logic.dart';
import 'package:telemedicinemobile/features/homecare/home_care_repository.dart';
import 'package:telemedicinemobile/features/homecare/home_care_screen.dart';
import 'package:telemedicinemobile/shared/widgets/home_care_commission.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  test(
    'near you matches a saved town inside the location and skips a blank town',
    () {
      expect(homeCareLocationNearTown('East Legon, Accra', 'accra'), isTrue);
      expect(
        homeCareLocationNearTown('East Legon, Accra', ' Kumasi '),
        isFalse,
      );
      expect(homeCareLocationNearTown('East Legon, Accra', ''), isFalse);
      expect(homeCareLocationNearTown('East Legon, Accra', null), isFalse);
      expect(homeCareLocationNearTown(null, 'Accra'), isFalse);
    },
  );

  test(
    'open requests sort ahead of taken and closed, with nearby open jobs first',
    () {
      HomeCareRequest item({
        required int id,
        required String status,
        bool nearYou = false,
        String? createdAt,
      }) {
        return HomeCareRequest(
          id: id,
          title: 'Visit $id',
          status: status,
          mine: false,
          taken: status == 'claimed',
          nearYou: nearYou,
          createdAt: createdAt,
        );
      }

      final sorted = sortHomeCareRequests([
        item(id: 1, status: 'closed', createdAt: '2026-10-05T12:00:00.000Z'),
        item(id: 2, status: 'claimed', createdAt: '2026-10-05T12:00:00.000Z'),
        item(id: 3, status: 'open', createdAt: '2026-10-05T09:00:00.000Z'),
        item(
          id: 4,
          status: 'open',
          nearYou: true,
          createdAt: '2026-10-05T08:00:00.000Z',
        ),
      ]);

      expect(sorted.map((row) => row.id).toList(), [4, 3, 2, 1]);
    },
  );

  test(
    'taken labels name the taker, and the person who took it sees You took this',
    () {
      const mine = HomeCareRequest(
        id: 1,
        title: 'Overnight watch',
        status: 'claimed',
        mine: true,
        taken: true,
        claimedByLabel: 'Ama Boateng',
        claimedAt: '2026-10-05T13:22:00.000Z',
      );
      const other = HomeCareRequest(
        id: 2,
        title: 'Wound dressing',
        status: 'claimed',
        mine: false,
        taken: true,
        claimedByLabel: 'Ridge Care Agency',
      );
      const adminView = HomeCareRequest(
        id: 3,
        title: 'Wound dressing',
        status: 'claimed',
        mine: false,
        taken: true,
        claimedByName: 'Ama Boateng',
        claimedByAgency: 'Ridge Care Agency',
        claimedAt: '2026-10-05T13:22:00.000Z',
      );

      expect(mine.pillLabel(admin: false), 'You took this');
      expect(mine.takenDetail(admin: false), 'Ama Boateng');
      expect(mine.canTake, isFalse);

      expect(other.pillLabel(admin: false), 'Taken · Ridge Care Agency');
      expect(other.canTake, isFalse);
      expect(other.takenDetail(admin: false), isNull);

      expect(adminView.pillLabel(admin: true), 'Taken');
      expect(
        adminView.takenDetail(admin: true),
        contains('Taken by Ridge Care Agency'),
      );
      expect(adminView.takenDetail(admin: true), contains('2026'));
    },
  );

  testWidgets(
    'a taken card hides Take and keeps the name with the commission',
    (tester) async {
      const request = HomeCareRequest(
        id: 8,
        title: 'Evening medication',
        status: 'claimed',
        mine: false,
        taken: true,
        claimedByLabel: 'Kojo Mensah',
        location: 'Tema',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HomeCareRequestCard(request: request, admin: false),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Taken · Kojo Mensah'), findsOneWidget);
      expect(find.text('Take this request'), findsNothing);
      expect(find.text(healynksHomeCareCommission), findsOneWidget);
      expect(find.text('Message admin'), findsOneWidget);
      expect(find.textContaining('onrender'), findsNothing);
    },
  );

  testWidgets(
    'the taker sees You took this, their name, and the commission together',
    (tester) async {
      const request = HomeCareRequest(
        id: 9,
        title: 'Evening medication',
        status: 'claimed',
        mine: true,
        taken: true,
        claimedByLabel: 'Kojo Mensah',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HomeCareRequestCard(request: request, admin: false),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('You took this'), findsOneWidget);
      expect(find.text('Kojo Mensah'), findsOneWidget);
      expect(find.text(healynksHomeCareCommission), findsOneWidget);
      expect(find.text('Take this request'), findsNothing);
    },
  );

  testWidgets('an open nearby request can be taken and says Near you', (
    tester,
  ) async {
    const request = HomeCareRequest(
      id: 4,
      title: 'Wound dressing',
      status: 'open',
      mine: false,
      taken: false,
      nearYou: true,
      location: 'Osu, Accra',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeCareRequestCard(
            request: request,
            admin: false,
            onTap: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Near you'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Take this request'), findsOneWidget);
    expect(find.text(healynksHomeCareCommission), findsOneWidget);
  });

  testWidgets('admin chat opens as a pop-out and shows the empty state', (
    tester,
  ) async {
    const request = HomeCareRequest(
      id: 4,
      title: 'Wound dressing',
      status: 'open',
      mine: false,
      taken: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeCareChatPanel(
            request: request,
            loadMessages: () async => const [],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Message admin'), findsOneWidget);
    expect(
      find.text('No messages yet. Write the admin about this request.'),
      findsOneWidget,
    );
    expect(find.text('Send'), findsOneWidget);
    expect(find.textContaining('onrender'), findsNothing);
  });
}
