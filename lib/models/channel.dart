class ChannelMember {
  final String id;
  final String displayName;
  final int avatarColorValue;

  const ChannelMember({
    required this.id,
    required this.displayName,
    required this.avatarColorValue,
  });

  factory ChannelMember.fromJson(String json) {
    final id = RegExp(r'"id":"([^"]+)"').firstMatch(json)?.group(1) ?? '';
    final name =
        RegExp(r'"name":"([^"]+)"').firstMatch(json)?.group(1) ?? 'Unknown';
    final color = int.tryParse(
          RegExp(r'"color":(\d+)').firstMatch(json)?.group(1) ?? '0',
        ) ??
        0xFF2196F3;
    return ChannelMember(
        id: id, displayName: name, avatarColorValue: color);
  }

  String toJson() =>
      '{"id":"$id","name":"$displayName","color":$avatarColorValue}';
}

class ChannelMessage {
  final String senderId;
  final String senderName;
  final int senderColor;
  final String content;
  final String time;
  final bool isBroadcast;

  const ChannelMessage({
    required this.senderId,
    required this.senderName,
    required this.senderColor,
    required this.content,
    required this.time,
    this.isBroadcast = false,
  });
}