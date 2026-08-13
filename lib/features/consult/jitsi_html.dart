String normalizeJitsiMeetingUrl(String meetingUrl) {
  final trimmed = meetingUrl.trim();
  if (trimmed.isEmpty) return trimmed;
  final withScheme = trimmed.contains('://') ? trimmed : 'https://$trimmed';
  final uri = Uri.tryParse(withScheme);
  if (uri == null || uri.host.isEmpty) {
    return 'https://meet.jit.si/${jitsiRoomNameFromUrl(trimmed)}';
  }
  return uri.toString();
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
  final room = jitsiRoomNameFromUrl(meetingUrl);
  final name = Uri.encodeQueryComponent(sanitizeJitsiName(displayName));
  return 'https://meet.jit.si/$room'
      '#userInfo.displayName="$name"'
      '&config.prejoinPageEnabled=false'
      '&config.startWithAudioMuted=$startAudioMuted'
      '&config.startWithVideoMuted=$startVideoMuted'
      '&config.disableDeepLinking=true';
}

String sanitizeJitsiName(String name) {
  final cleaned = name.replaceAll(RegExp(r"[^a-zA-Z0-9 .'-]"), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return cleaned.isEmpty ? 'Guest' : cleaned;
}

String buildJitsiHostHtml({
  required String roomName,
  required String displayName,
  bool startAudioMuted = false,
  bool startVideoMuted = false,
}) {
  final room = roomName.replaceAll("'", '');
  final name = sanitizeJitsiName(displayName).replaceAll("'", '');
  return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
  <script src="https://meet.jit.si/external_api.js"></script>
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
    const api = new JitsiMeetExternalAPI('meet.jit.si', {
      roomName: '$room',
      parentNode: document.querySelector('#meet'),
      width: '100%',
      height: '100%',
      userInfo: { displayName: '$name' },
      configOverwrite: {
        prejoinPageEnabled: false,
        startWithAudioMuted: $startAudioMuted,
        startWithVideoMuted: $startVideoMuted,
        disableDeepLinking: true,
        disableInviteFunctions: true,
        hideConferenceSubject: true,
        hideConferenceTimer: true,
      },
      interfaceConfigOverwrite: {
        TOOLBAR_BUTTONS: ['microphone', 'camera', 'tileview'],
        SHOW_JITSI_WATERMARK: false,
        SHOW_BRAND_WATERMARK: false,
        SHOW_WATERMARK_FOR_GUESTS: false,
        DEFAULT_BACKGROUND: '#071018',
        FILM_STRIP_MAX_HEIGHT: 90,
        DISABLE_JOIN_LEAVE_NOTIFICATIONS: true,
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
  </script>
</body>
</html>
''';
}
