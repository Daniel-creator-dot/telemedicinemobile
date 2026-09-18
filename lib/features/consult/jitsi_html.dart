/// Medilynks video rooms.
///
/// Public Jitsi hosts that block anonymous room creation (moderator/SSO gate):
/// - meet.jit.si / 8x8.vc — require authenticated moderator
/// - jitsi.debian.social — tokenAuthUrl → salsa.debian.org SSO
/// - jitsi.member.fsf.org — FSF associate-member login to *start* rooms
///
/// Default: meet.ffmuc.net (Freifunk) — no tokenAuthUrl; first joiner is
/// moderator. That host sets X-Frame-Options / CSP frame-ancestors, so the
/// in-app client must load the room as a **top-level** WebView document
/// (not an External API iframe). Override with JITSI_DOMAIN if you self-host.
const String kDigiJitsiDomain = String.fromEnvironment(
  'JITSI_DOMAIN',
  defaultValue: 'meet.ffmuc.net',
);

bool isLockedPublicJitsiHost(String host) {
  final h = host.toLowerCase().trim();
  return h == 'meet.jit.si' ||
      h == '8x8.vc' ||
      h.endsWith('.8x8.vc') ||
      h == 'jaas.8x8.vc' ||
      h == 'jitsi.debian.social' ||
      h == 'jitsi.member.fsf.org';
}

/// Hosts that refuse being framed (External API / iframe embeds blank out).
bool jitsiHostBlocksIframeEmbed(String host) {
  final h = host.toLowerCase().trim();
  return h == 'meet.ffmuc.net' ||
      h == 'ffmuc.net' ||
      h.endsWith('.ffmuc.net') ||
      h.endsWith('.ffmeet.net') ||
      h.endsWith('.ffmeet.de');
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
      '&config.requireDisplayName=false'
      '&config.enableClosePage=false'
      '&config.disableInviteFunctions=true'
      '&interfaceConfig.MOBILE_APP_PROMO=false'
      '&interfaceConfig.SHOW_JITSI_WATERMARK=false'
      '&interfaceConfig.DISABLE_JOIN_LEAVE_NOTIFICATIONS=true';
}

String sanitizeJitsiName(String name) {
  final cleaned = name.replaceAll(RegExp(r"[^a-zA-Z0-9 .'-]"), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return cleaned.isEmpty ? 'Guest' : cleaned;
}

/// Bridge script injected into a top-level Jitsi Meet page (direct WebView load).
String jitsiMeetBridgeScript() {
  return r'''
(function () {
  if (window.__digiJitsiBridge) return;
  window.__digiJitsiBridge = true;
  function notify(event) {
    try { if (window.DigiJitsi) DigiJitsi.postMessage(event); } catch (e) {}
    try { window.parent && window.parent.postMessage({ source: 'digi-jitsi', event: event }, '*'); } catch (e) {}
  }
  function bindConference() {
    try {
      if (!window.APP || !APP.conference) return false;
      var conf = APP.conference;
      function onJoined() { notify('joined'); }
      function onLeft() { notify('left'); }
      function onPeerJoined() { notify('participantJoined'); }
      function onPeerLeft() { notify('participantLeft'); }
      try {
        if (typeof conf.addListener === 'function') {
          conf.addListener('conference.joined', onJoined);
          conf.addListener('conference.left', onLeft);
          conf.addListener('conference.userJoined', onPeerJoined);
          conf.addListener('conference.userLeft', onPeerLeft);
        }
      } catch (e) {}
      try {
        if (conf.isJoined && conf.isJoined()) onJoined();
      } catch (e) {}
      window.toggleAudio = function () {
        try { if (conf.toggleAudioMuted) conf.toggleAudioMuted(); else if (conf.muteAudio) conf.muteAudio(!conf.isLocalAudioMuted()); } catch (e) {}
      };
      window.toggleVideo = function () {
        try { if (conf.toggleVideoMuted) conf.toggleVideoMuted(); else if (conf.muteVideo) conf.muteVideo(!conf.isLocalVideoMuted()); } catch (e) {}
      };
      window.switchCamera = function () {
        try { if (APP.conference && APP.conference.switchCamera) APP.conference.switchCamera(); } catch (e) {}
      };
      window.hangup = function () {
        try { if (conf.hangup) conf.hangup(); else if (APP.conference && APP.conference.hangup) APP.conference.hangup(); } catch (e) {}
      };
      notify('ready');
      return true;
    } catch (e) {
      return false;
    }
  }
  var tries = 0;
  (function poll() {
    if (bindConference()) return;
    tries += 1;
    if (tries < 90) setTimeout(poll, 500);
    else notify('bridgeTimeout');
  })();
  // Fallback: detect joined via DOM / title heuristics after a while
  setTimeout(function () {
    try {
      if (window.APP && APP.conference && APP.conference.isJoined && APP.conference.isJoined()) {
        notify('joined');
      }
    } catch (e) {}
  }, 4000);
})();
''';
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
    #err { display:none; color:#fecaca; font-family:sans-serif; padding:24px; text-align:center; }
  </style>
</head>
<body>
  <div id="meet"></div>
  <div id="err"></div>
  <script>
    function notify(event) {
      try { if (window.DigiJitsi) DigiJitsi.postMessage(event); } catch (e) {}
      try { window.parent && window.parent.postMessage({ source: 'digi-jitsi', event: event }, '*'); } catch (e) {}
    }
    function showErr(msg) {
      var el = document.getElementById('err');
      el.style.display = 'block';
      el.textContent = msg || 'Video room failed to load';
      notify('error:' + (msg || 'load failed'));
    }
    function startMeet() {
      if (typeof JitsiMeetExternalAPI !== 'function') {
        showErr('Could not load Jitsi API from $safeHost');
        return;
      }
      try {
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
        api.addListener('readyToClose', function () { notify('left'); });
        notify('ready');
      } catch (e) {
        showErr(String(e && e.message ? e.message : e));
      }
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
    window.addEventListener('error', function (e) {
      if (e && e.target && e.target.src && String(e.target.src).indexOf('external_api') >= 0) {
        showErr('Blocked loading Jitsi from $safeHost (network or frame policy)');
      }
    }, true);
    warmMediaThenStart();
  </script>
</body>
</html>
''';
}
