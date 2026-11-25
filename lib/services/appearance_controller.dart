import 'package:flutter/foundation.dart';

import '../models/ui_style_settings.dart';
import 'settings_service.dart';

/// Root-owned appearance state — persists and notifies [MaterialApp] rebuilds.
class AppearanceController extends ChangeNotifier {
  AppearanceController({
    required this.settingsService,
    UiStyleSettings? initial,
  }) : _style = initial ?? UiStyleSettings.defaults();

  final SettingsService settingsService;
  UiStyleSettings _style;
  bool _ready = false;

  UiStyleSettings get style => _style;
  bool get ready => _ready;

  Future<void> load() async {
    final loaded = await settingsService.getUiStyle();
    _style = loaded;
    _ready = true;
    notifyListeners();
  }

  /// Reload after backup restore without flashing a default theme.
  Future<void> reload() async {
    final loaded = await settingsService.getUiStyle();
    _style = loaded;
    _ready = true;
    notifyListeners();
  }

  Future<void> save(UiStyleSettings style) async {
    _style = style;
    notifyListeners();
    await settingsService.saveUiStyle(style);
  }

  void applyLocal(UiStyleSettings style) {
    _style = style;
    notifyListeners();
  }
}
