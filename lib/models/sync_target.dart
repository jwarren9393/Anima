/// Where the cross-device sync file lives on this device.
class SyncTarget {
  const SyncTarget({
    this.filePath,
    this.contentUri,
  });

  /// Desktop path (e.g. Google Drive synced folder on Windows).
  final String? filePath;

  /// Android Storage Access Framework document URI (e.g. Google Drive file).
  final String? contentUri;

  bool get isConfigured =>
      (filePath != null && filePath!.trim().isNotEmpty) ||
      (contentUri != null && contentUri!.trim().isNotEmpty);

  String get displayLabel {
    final path = filePath?.trim();
    if (path != null && path.isNotEmpty) {
      final parts = path.replaceAll('\\', '/').split('/');
      if (parts.length >= 2) {
        return '${parts[parts.length - 2]}/${parts.last}';
      }
      return parts.last;
    }
    final uri = contentUri?.trim();
    if (uri != null && uri.isNotEmpty) {
      return 'Google Drive sync file';
    }
    return 'Not set';
  }

  SyncTarget copyWith({
    String? filePath,
    String? contentUri,
    bool clearFilePath = false,
    bool clearContentUri = false,
  }) {
    return SyncTarget(
      filePath: clearFilePath ? null : (filePath ?? this.filePath),
      contentUri: clearContentUri ? null : (contentUri ?? this.contentUri),
    );
  }
}
