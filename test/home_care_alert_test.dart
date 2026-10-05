import 'package:flutter_test/flutter_test.dart';
import 'package:telemedicinemobile/features/homecare/home_care_logic.dart';

void main() {
  const token = 'aB3xY9kLm2Qp7Vw8Zn4Ht6';
  const text =
      'Healynks home care: Wound dressing in East Legon. Open https://healynks.app/homecare/$token';

  test('a home care notification opens the share token, not a numeric id', () {
    expect(homeCareTokenFromNotification(text), token);
    expect(homeCareJobPath('/homecare/$token'), '/homecare/$token');
    expect(homeCareShareTokenOk(token), isTrue);
    expect(homeCareTokenFromNotification('Open https://healynks.app/homecare/42'), isNull);
    expect(homeCareJobPath('/homecare/42'), isNull);
    expect(homeCareJobPath('/homecare/1234567890123456'), isNull);
    expect(homeCareJobPath('/nurse/homecare'), isNull);
    expect(homeCareJobPath('/admin?next=/homecare/$token'), isNull);
    expect(homeCareJobPath('https://evil.example/homecare/$token'), isNull);
    expect(homeCareJobPath('//evil.example/homecare/$token'), isNull);
    expect(homeCarePublicUrl(token), 'https://healynks.app/homecare/$token');
    expect(homeCarePublicUrl(token)!.contains('onrender'), isFalse);
    expect(homeCarePublicUrl('42'), isNull);
  });
}
