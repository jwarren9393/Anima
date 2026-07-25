import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// True on Windows, Linux, or macOS builds (not Android/iOS/web).
bool get isDesktopPlatform {
  if (kIsWeb) return false;
  return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
}
