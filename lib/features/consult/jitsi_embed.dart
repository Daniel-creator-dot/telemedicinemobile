export 'jitsi_embed_stub.dart'
    if (dart.library.html) 'jitsi_embed_web.dart'
    if (dart.library.io) 'jitsi_embed_io.dart';
