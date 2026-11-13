// Facade: real video preview on native, placeholder on Web.
export 'clip_player_io.dart'
    if (dart.library.js_interop) 'clip_player_stub.dart';
