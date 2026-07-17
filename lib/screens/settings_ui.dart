import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/keyboard_inset.dart';

/// Shared helpers for settings sub-screens.
class SettingsUi {
  static const listPadding = EdgeInsets.all(20);

  /// Keep focused fields above the keyboard when scrolling a settings form.
  static const keyboardScrollPadding = kAnimaKeyboardScrollPadding;

  static Widget sectionTitle(BuildContext context, String title) {
    return Text(title, style: Theme.of(context).textTheme.titleMedium);
  }

  static Widget sectionHint(BuildContext context, String text) {
    return Text(text, style: Theme.of(context).textTheme.bodyMedium);
  }

  static Widget saveButton({
    required bool saving,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return FilledButton(
      onPressed: onPressed,
      child: saving
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label),
    );
  }

  static InputDecoration fieldDecoration({
    required String label,
    String? helperText,
    String? hintText,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helperText,
      hintText: hintText,
      border: const OutlineInputBorder(),
    );
  }

  static List<TextInputFormatter> decimalInput() {
    return [FilteringTextInputFormatter.allow(RegExp(r'[0-9.-]'))];
  }

  static List<TextInputFormatter> positiveIntInput() {
    return [FilteringTextInputFormatter.digitsOnly];
  }

  static double? parseOptionalDouble(String raw, {double? min, double? max}) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final parsed = double.tryParse(trimmed);
    if (parsed == null) return null;
    var value = parsed;
    if (min != null) value = value < min ? min : value;
    if (max != null) value = value > max ? max : value;
    return value;
  }

  static int? parseOptionalPositiveInt(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final parsed = int.tryParse(trimmed);
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  static int? parseOptionalInt(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    return int.tryParse(trimmed);
  }
}
