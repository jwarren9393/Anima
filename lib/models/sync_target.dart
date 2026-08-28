/// Where the cross-device sync file lives on this device.
class SyncTarget {
  const SyncTarget({
    this.filePath,
    this.contentUri,
    this.friendlyName,
  });

  /// Desktop path (e.g. Google Drive synced folder, or a GNOME Drive mount).
  final String? filePath;

  /// Android Storage Access Framework document URI (e.g. Google Drive file).
  final String? contentUri;

  /// Human name when the filesystem name is a Drive ID (GNOME gvfs).
  final String? friendlyName;

  bool get isConfigured =>
      (filePath != null && filePath!.trim().isNotEmpty) ||
      (contentUri != null && contentUri!.trim().isNotEmpty);

  String get displayLabel {
    final friendly = friendlyName?.trim();
    if (friendly != null && friendly.isNotEmpty) return friendly;
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
      return 'Google Drive sync folder';
    }
    return 'Not set';
  }

  SyncTarget copyWith({
    String? filePath,
    String? contentUri,
    String? friendlyName,
    bool clearFilePath = false,
    bool clearContentUri = false,
    bool clearFriendlyName = false,
  }) {
    return SyncTarget(
      filePath: clearFilePath ? null : (filePath ?? this.filePath),
      contentUri: clearContentUri ? null : (contentUri ?? this.contentUri),
      friendlyName:
          clearFriendlyName ? null : (friendlyName ?? this.friendlyName),
    );
  }
}
