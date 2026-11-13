// Public facade for the Clip Studio exporter.
//
// Native builds pull in the real FFmpeg-backed engine; Web pulls in a stub
// that reports exporting as unavailable. Both expose the same [ClipExporter].
import 'clip_export_io.dart'
    if (dart.library.js_interop) 'clip_export_stub.dart';

/// The active exporter for the current platform.
final ClipExporter clipExporter = ClipExporter();
