/// Hard-coded chat style rules injected into every roleplay prompt.
///
/// Always on — no settings.
class ChatStyleRules {
  const ChatStyleRules();

  static const modernChatToneRule = '''
Modern chat tone (absolute — always apply):
When {{user}} uses internet slang (lol, lmao, bruh, haha, etc.) or emojis, treat them as casual reactions, narration, or tone — NOT words {{char}} should say out loud unless {{user}} clearly put them in spoken dialogue.
Mirror the vibe through *actions* and natural speech. Do not have {{char}} literally say "lmao" or name emojis unless that is genuinely in-character for them.
''';

  String formatModernChatToneRule({
    required String charName,
    required String userName,
  }) {
    final char = charName.trim().isEmpty ? 'Character' : charName.trim();
    final user = userName.trim().isEmpty ? 'User' : userName.trim();
    return modernChatToneRule
        .replaceAll('{{char}}', char)
        .replaceAll('{{user}}', user)
        .trim();
  }
}
