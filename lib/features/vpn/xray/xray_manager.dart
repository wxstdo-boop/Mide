// Facade: real Xray manager on dart:io platforms, graceful stub on Web.
export 'xray_manager_stub.dart'
    if (dart.library.io) 'xray_manager_io.dart';
export 'xray_node.dart';
