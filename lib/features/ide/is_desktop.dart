// Platform gate for PC-only features (the IDE). Mirrors the app's
// io/stub conditional-import pattern: desktop OSes only, never web/mobile.
import 'package:flutter/foundation.dart';

/// True only on desktop OS builds (Windows/macOS/Linux). Web and mobile
/// return false — the IDE entry pill stays hidden there.
bool get isDesktopPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS);
