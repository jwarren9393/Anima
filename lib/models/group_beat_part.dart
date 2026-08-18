/// One character's line inside a [ChatRole.groupBeat] message.
class GroupBeatPart {
  const GroupBeatPart({
    required this.speakerId,
    required this.speakerName,
    required this.text,
  });

  final String speakerId;
  final String speakerName;
  final String text;

  GroupBeatPart copyWith({
    String? speakerId,
    String? speakerName,
    String? text,
  }) {
    return GroupBeatPart(
      speakerId: speakerId ?? this.speakerId,
      speakerName: speakerName ?? this.speakerName,
      text: text ?? this.text,
    );
  }

  Map<String, dynamic> toJson() => {
        'speakerId': speakerId,
        'speakerName': speakerName,
        'text': text,
      };

  factory GroupBeatPart.fromJson(Map<String, dynamic> json) {
    return GroupBeatPart(
      speakerId: '${json['speakerId'] ?? ''}'.trim(),
      speakerName: '${json['speakerName'] ?? ''}'.trim(),
      text: '${json['text'] ?? ''}'.trim(),
    );
  }
}
