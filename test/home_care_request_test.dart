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
}
