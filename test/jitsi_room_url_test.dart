import 'package:flutter_test/flutter_test.dart';
import 'package:telemedicinemobile/features/consult/jitsi_html.dart';

void main() {
  test('new and stored rooms join the same public Jitsi host over https', () {
    expect(kDigiJitsiDomain, 'meet.evolix.org');
    expect(jitsiHostBlocksIframeEmbed(kDigiJitsiDomain), isFalse);

    const room = 'healynks-abc123def456';
    expect(
      normalizeJitsiMeetingUrl('https://meet.ffmuc.net/$room'),
      'https://meet.evolix.org/$room',
    );
    expect(
      normalizeJitsiMeetingUrl('https://meet.jit.si/$room#config.prejoinPageEnabled=false'),
      'https://meet.evolix.org/$room',
    );
    expect(
      normalizeJitsiMeetingUrl('meet.ffmuc.net/$room'),
      'https://meet.evolix.org/$room',
    );

    final direct = jitsiDirectJoinUrl(
      meetingUrl: 'https://meet.ffmuc.net/$room',
      displayName: 'Dr Ama',
    );
    expect(direct.startsWith('https://meet.evolix.org/$room#'), isTrue);
    expect(direct.contains('http://'), isFalse);

    final html = buildJitsiHostHtml(roomName: room, displayName: 'Dr Ama');
    expect(html.contains('https://meet.evolix.org/external_api.js'), isTrue);
    expect(html.contains('clipboard-write'), isTrue);
    expect(html.contains('display-capture'), isTrue);
    expect(html.contains('microphone'), isTrue);
    expect(kJitsiIframeAllow.contains('fullscreen'), isTrue);
    expect(kJitsiIframeAllow.contains('autoplay'), isTrue);
    expect(kJitsiIframeAllow.contains('camera'), isTrue);
  });
}
