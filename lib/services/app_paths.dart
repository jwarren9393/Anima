import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'app_data_root.dart';

/// App library folder. Uses the user-chosen Anima folder when it is ready,
/// otherwise Flutter's old hidden documents path (tests / first launch).
Future<Directory> appDocumentsDirectory() async {
  final root = AppDataRoot.instance;
  if (root != null && root.isConfigured) {
    return root.directory();
  }
  return getApplicationDocumentsDirectory();
}
