typedef JitsiEventCallback = void Function(String event);

class JitsiRoomController {
  Future<void> Function()? toggleAudio;
  Future<void> Function()? toggleVideo;
  Future<void> Function()? switchCamera;
  Future<void> Function()? hangup;
}
