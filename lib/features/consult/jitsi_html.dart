/// Medilynks video rooms.
///
/// meet.jit.si (and 8x8.vc) hard-require an authenticated moderator to start a
/// conference — anonymous External API embeds get stuck on
/// "Asking to join meeting..." / "no moderators have yet arrived". That cannot
/// be disabled via configOverwrite. We therefore host rooms on a public
/// community instance where the first joiner becomes moderator with no login.
const String kDigiJitsiDomain = String.fromEnvironment(
  'JITSI_DOMAIN',
  defaultValue: 'jitsi.debian.social',
);

bool isLockedPublicJitsiHost(String host) {
  final h = host.toLowerCase().trim();
  return h == 'meet.jit.si' ||
      h == '8x8.vc' ||
      h.endsWith('.8x8.vc') ||
      h == 'jaas.8x8.vc';
}

String digiJitsiDomainFromUrl(String meetingUrl) {
  final uri = Uri.tryParse(normalizeJitsiMeetingUrl(meetingUrl));
  final host = uri?.host ?? '';
  if (host.isEmpty || isLockedPublicJitsiHost(host)) return kDigiJitsiDomain;
  return host;
}

String normalizeJitsiMeetingUrl(String meetingUrl) {
  final trimmed = meetingUrl.trim();
  if (trimmed.isEmpty) return trimmed;
  final withScheme = trimmed.contains('://') ? trimmed : 'https://$trimmed';
  final uri = Uri.tryParse(withScheme);
  if (uri == null || uri.host.isEmpty) {
    return 'https://$kDigiJitsiDomain/${jitsiRoomNameFromUrl(trimmed)}';
  }
  final room = jitsiRoomNameFromUrl(uri.toString());
  final host = isLockedPublicJitsiHost(uri.host) ? kDigiJitsiDomain : uri.host;
  return Uri(
    scheme: 'https',
    host: host,
    path: '/$room',
  ).toString();
}

String jitsiRoomNameFromUrl(String meetingUrl) {
  final trimmed = meetingUrl.trim();
  var uri = Uri.tryParse(trimmed);
  if (uri == null || (uri.host.isEmpty && !trimmed.contains('://'))) {
    uri = Uri.tryParse(trimmed.contains('://') ? trimmed : 'https://$trimmed');
  }
  if (uri == null) {
    return trimmed.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '');
  }
  final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segs.isEmpty) {
    return trimmed.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '');
  }
  return segs.join('/');
}

String jitsiDirectJoinUrl({
  required String meetingUrl,
  required String displayName,
  bool startAudioMuted = false,
  bool startVideoMuted = false,
}) {
  final normalized = normalizeJitsiMeetingUrl(meetingUrl);
  final domain = digiJitsiDomainFromUrl(normalized);
  final room = jitsiRoomNameFromUrl(normalized);
  final name = Uri.encodeQueryComponent(sanitizeJitsiName(displayName));
  return 'https://$domain/$room'
      '#userInfo.displayName="$name"'
      '&config.prejoinConfig.enabled=false'
      '&config.prejoinPageEnabled=false'
      '&config.startWithAudioMuted=$startAudioMuted'
      '&config.startWithVideoMuted=$startVideoMuted'
      '&config.disableDeepLinking=true'
      '&config.enableWelcomePage=false'
      '&config.requireDisplayName=false';
}

String sanitizeJitsiName(String name) {
  final cleaned = name.replaceAll(RegExp(r"[^a-zA-Z0-9 .'-]"), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return cleaned.isEmpty ? 'Guest' : cleaned;
}

String buildJitsiHostHtml({
  required String roomName,
  required String displayName,
  String domain = kDigiJitsiDomain,
  bool startAudioMuted = false,
  bool startVideoMuted = false,
}) {
  final room = roomName.replaceAll("'", '');
  final name = sanitizeJitsiName(displayName).replaceAll("'", '');
  final host = domain.replaceAll("'", '').replaceAll(RegExp(r'[^a-zA-Z0-9.-]'), '');
  final safeHost = host.isEmpty ? kDigiJitsiDomain : host;
  return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
  <meta http-equiv="Permissions-Policy" content="camera=*, microphone=*, display-capture=*, autoplay=*">
  <script src="https://$safeHost/external_api.js"></script>
  <style>
    html, body, #meet { margin: 0; padding: 0; height: 100%; width: 100%; background: #071018; overflow: hidden; }
  </style>
</head>
<body>
  <div id="meet"></div>
  <script>
    function notify(event) {
      try { if (window.DigiJitsi) DigiJitsi.postMessage(event); } catch (e) {}
      try { window.parent && window.parent.postMessage({ source: 'digi-jitsi', event: event }, '*'); } catch (e) {}
    }
    function startMeet() {
      const api = new JitsiMeetExternalAPI('$safeHost', {
        roomName: '$room',
        parentNode: document.querySelector('#meet'),
        width: '100%',
        height: '100%',
        userInfo: { displayName: '$name' },
        configOverwrite: {
          prejoinPageEnabled: false,
          prejoinConfig: { enabled: false },
          startWithAudioMuted: $startAudioMuted,
          startWithVideoMuted: $startVideoMuted,
          disableDeepLinking: true,
          disableInviteFunctions: true,
          disableModeratorIndicator: true,
          enableWelcomePage: false,
          enableClosePage: false,
          requireDisplayName: false,
          hideConferenceSubject: true,
          hideConferenceTimer: true,
          enableLobbyChat: false,
          lobby: { autoKnock: true, enableChat: false },
          securityUi: { hideLobbyButton: true, disableLobbyPassword: true },
          notifications: [],
        },
        interfaceConfigOverwrite: {
          TOOLBAR_BUTTONS: ['microphone', 'camera', 'tileview'],
          SHOW_JITSI_WATERMARK: false,
          SHOW_BRAND_WATERMARK: false,
          SHOW_WATERMARK_FOR_GUESTS: false,
          DEFAULT_BACKGROUND: '#071018',
          FILM_STRIP_MAX_HEIGHT: 90,
          DISABLE_JOIN_LEAVE_NOTIFICATIONS: true,
          MOBILE_APP_PROMO: false,
        }
      });
      window.jitsiApi = api;
      window.toggleAudio = function () { api.executeCommand('toggleAudio'); };
      window.toggleVideo = function () { api.executeCommand('toggleVideo'); };
      window.switchCamera = function () { api.executeCommand('switchCamera'); };
      window.hangup = function () { api.executeCommand('hangup'); };
      window.addEventListener('message', function (e) {
        var cmd = (e.data && e.data.cmd) ? e.data.cmd : e.data;
        if (cmd === 'toggleAudio') toggleAudio();
        if (cmd === 'toggleVideo') toggleVideo();
        if (cmd === 'switchCamera') switchCamera();
        if (cmd === 'hangup') hangup();
      });
      api.addListener('videoConferenceJoined', function () { notify('joined'); });
      api.addListener('participantJoined', function () { notify('participantJoined'); });
      api.addListener('participantLeft', function () { notify('participantLeft'); });
      api.addListener('videoConferenceLeft', function () { notify('left'); });
      notify('ready');
    }
    function warmMediaThenStart() {
      var done = false;
      function go() {
        if (done) return;
        done = true;
        startMeet();
      }
      try {
        if (navigator.mediaDevices && navigator.mediaDevices.getUserMedia) {
          navigator.mediaDevices.getUserMedia({ audio: true, video: true })
            .then(function (stream) {
              try { stream.getTracks().forEach(function (t) { t.stop(); }); } catch (e) {}
              go();
            })
            .catch(function () { go(); });
          setTimeout(go, 2500);
          return;
        }
      } catch (e) {}
      go();
    }
    warmMediaThenStart();
  </script>
</body>
</html>
''';
}
