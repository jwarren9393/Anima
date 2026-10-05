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

  /// First-person RP voice for whoever is speaking this turn.
  ///
  /// [speakerName] is {{user}} during Impersonate / My line…, otherwise {{char}}.
  static const firstPersonPerspectiveRule = '''
Perspective (absolute — always apply for this reply):
Write ONLY as {{speaker}} in FIRST PERSON.
In *asterisk* actions and thoughts, use I/my/me — never he/she/they or {{speaker}}'s name for {{speaker}}'s own body, thoughts, or actions.
Correct: *I smile and step closer.* Wrong: *He smiles.* / *{{speaker}} steps closer.*
Spoken lines stay in "double quotes" as usual.
Do not narrate other people's private thoughts. Do not switch into third-person novel narration for {{speaker}}.
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

  String formatFirstPersonPerspectiveRule({
    required String speakerName,
  }) {
    final speaker =
        speakerName.trim().isEmpty ? 'the speaker' : speakerName.trim();
    return firstPersonPerspectiveRule
        .replaceAll('{{speaker}}', speaker)
        .trim();
  }
}
