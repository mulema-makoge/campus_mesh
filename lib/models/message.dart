import 'dart:convert';

class MeshMessage {
  final String id;
  final String payload;
  final int ttl;
  final List<String> hopPath;
  final String senderId;

  const MeshMessage({
    required this.id,
    required this.payload,
    required this.ttl,
    required this.hopPath,
    required this.senderId,
  });

  MeshMessage decrementTTL(String myId) {
    return MeshMessage(
      id: id,
      payload: payload,
      ttl: ttl - 1,
      hopPath: [...hopPath, myId],
      senderId: senderId,
    );
  }

  String toJson() {
    return jsonEncode({
      'id': id,
      'payload': payload,
      'ttl': ttl,
      'hopPath': hopPath,
      'senderId': senderId,
    });
  }

  static MeshMessage fromJson(String json) {
    final map = jsonDecode(json);
    return MeshMessage(
      id: map['id'],
      payload: map['payload'],
      ttl: map['ttl'],
      hopPath: List<String>.from(map['hopPath']),
      senderId: map['senderId'],
    );
  }
}