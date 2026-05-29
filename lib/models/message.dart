import 'dart:convert';

enum MeshDeliveryStatus { pending, sent, delivered, read, rejected }

class MeshMessage {
  final String id;
  final String payload;
  final int ttl;
  final List<String> hopPath;
  final String senderId;
  final String? recipientDisplayName;
  final MeshDeliveryStatus status;

  const MeshMessage({
    required this.id,
    required this.payload,
    required this.ttl,
    required this.hopPath,
    required this.senderId,
    this.recipientDisplayName,
    this.status = MeshDeliveryStatus.pending,
  });

  MeshMessage decrementTTL(String myId) {
    return MeshMessage(
      id: id,
      payload: payload,
      ttl: ttl - 1,
      hopPath: [...hopPath, myId],
      senderId: senderId,
      recipientDisplayName: recipientDisplayName,
      status: status,
    );
  }

  MeshMessage copyWith({MeshDeliveryStatus? status}) {
    return MeshMessage(
      id: id,
      payload: payload,
      ttl: ttl,
      hopPath: hopPath,
      senderId: senderId,
      recipientDisplayName: recipientDisplayName,
      status: status ?? this.status,
    );
  }

  String toJson() {
    return jsonEncode({
      'id': id,
      'payload': payload,
      'ttl': ttl,
      'hopPath': hopPath,
      'senderId': senderId,
      'recipientDisplayName': recipientDisplayName,
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
      recipientDisplayName: map['recipientDisplayName'],
    );
  }
}

// Relay message with delivery tracking for UI
class RelayConversation {
  final String peerName;
  final int peerColor;
  final List<RelayMessageItem> messages;

  const RelayConversation({
    required this.peerName,
    required this.peerColor,
    required this.messages,
  });
}

class RelayMessageItem {
  final String id;
  final String content;
  final String time;
  final int timestamp;
  final bool isMine;
  MeshDeliveryStatus status;

  RelayMessageItem({
    required this.id,
    required this.content,
    required this.time,
    required this.timestamp,
    required this.isMine,
    this.status = MeshDeliveryStatus.pending,
  });
}