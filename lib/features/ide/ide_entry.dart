// IDE entry — conditional export: real on dart:io platforms (desktop/mobile),
// stub on web. Same pattern as features/vpn/xray/xray_manager.dart.
export 'ide_entry_stub.dart' if (dart.library.io) 'ide_entry_io.dart';
