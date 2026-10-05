import 'package:flutter_test/flutter_test.dart';
import 'package:telemedicinemobile/features/homecare/home_care_repository.dart';

void main() {
  test(
    'a request taken by someone else does not carry their contact number',
    () {
      final request = HomeCareRequest.fromJson({
        'id': 4,
        'title': 'Wound dressing',
        'status': 'claimed',
        'mine': false,
        'taken': true,
        'claimed_by_label': 'Ama Home Care',
      });

      expect(request.contactPhone, isNull);
      expect(request.location, isNull);
      expect(request.claimerLine, 'Taken · Ama Home Care');
      expect(request.statusLabel, 'Taken · Ama Home Care');
    },
  );

  test(
    'the caregiver who took a request still sees the phone and location',
    () {
      final request = HomeCareRequest.fromJson({
        'id': 4,
        'title': 'Overnight watch',
        'status': 'claimed',
        'mine': true,
        'taken': true,
        'location': 'East Legon',
        'contact_phone': '0244000000',
        'claimed_by_label': 'Kojo Mensah',
      });

      expect(request.mine, isTrue);
      expect(request.contactPhone, '0244000000');
      expect(request.location, 'East Legon');
      expect(request.statusLabel, 'You took this');
    },
  );

  test('an open request the viewer posted reads Sent and stays first', () {
    final created = HomeCareRequest.fromJson({
      'id': 9,
      'title': 'Wound dressing',
      'status': 'open',
      'mine': false,
      'posted_by_me': true,
      'referred_by_me': true,
      'patient_name': 'Ama Mensah',
    });

    expect(created.postedByMe, isTrue);
    expect(created.referredByMe, isTrue);
    expect(created.isOpen, isTrue);
    expect(created.pillLabel(admin: true), 'Sent');
    expect(created.pillLabel(admin: false), 'Sent');
    expect(created.statusLabel, 'Sent');
    expect(created.canTake, isTrue);

    const olderOpen = HomeCareRequest(
      id: 3,
      title: 'Older visit',
      status: 'open',
      mine: false,
      taken: false,
    );
    const taken = HomeCareRequest(
      id: 2,
      title: 'Already taken',
      status: 'claimed',
      mine: false,
      taken: true,
      claimedByLabel: 'Kojo Mensah',
    );

    final placed = placeNewestHomeCareRequest([taken, olderOpen], created);
    expect(placed.map((row) => row.id).toList(), [9, 3, 2]);

    final pinned = pinJustPostedHomeCareRequest([olderOpen, created], created);
    expect(pinned.first.id, 9);
    expect(pinned.first.pillLabel(admin: true), 'Sent');

    final missing = pinJustPostedHomeCareRequest([olderOpen], created);
    expect(missing.map((row) => row.id).toList(), [9, 3]);
    expect(missing.first.pillLabel(admin: false), 'Sent');

    final otherPatient = pinJustPostedHomeCareRequest(
      [olderOpen],
      created,
      onlyPatientId: 44,
    );
    expect(otherPatient.map((row) => row.id).toList(), [3]);

    final claimed = HomeCareRequest.fromJson({
      'id': 9,
      'title': 'Wound dressing',
      'status': 'claimed',
      'mine': false,
      'taken': true,
      'posted_by_me': true,
      'claimed_by_label': 'Ama Home Care',
    });
    final afterClaim = pinJustPostedHomeCareRequest([olderOpen, claimed], created);
    expect(afterClaim.last.pillLabel(admin: true), 'Taken');
    expect(afterClaim.last.pillLabel(admin: false), 'Taken · Ama Home Care');
    expect(afterClaim.last.statusLabel, 'Taken · Ama Home Care');
  });

  test('a nurse still sees an open job they can take', () {
    const request = HomeCareRequest(
      id: 4,
      title: 'Wound dressing',
      status: 'open',
      mine: false,
      taken: false,
      postedByMe: true,
    );

    expect(request.pillLabel(admin: false), 'Open');
    expect(request.canTake, isTrue);
    expect(request.pillLabel(admin: true), 'Sent');
  });
}
