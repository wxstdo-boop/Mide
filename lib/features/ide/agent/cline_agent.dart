// Facade: real sidecar bridge on dart:io, graceful stub on Web.
export 'cline_agent_stub.dart' if (dart.library.io) 'cline_agent_io.dart';
