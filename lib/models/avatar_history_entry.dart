/// One stored portrait file in `avatars/` for a character or persona stem.
class AvatarHistoryEntry {
  const AvatarHistoryEntry({
    required this.fileName,
    required this.modified,
  });

  final String fileName;
  final DateTime modified;
}
