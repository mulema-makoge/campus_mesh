class UserProfile {
  final String displayName;
  final int avatarColorValue;

  const UserProfile({
    required this.displayName,
    required this.avatarColorValue,
  });

  String toJson() {
    return '{"name":"$displayName","color":$avatarColorValue}';
  }

  static UserProfile fromJson(String json) {
    final name =
        RegExp(r'"name":"([^"]+)"').firstMatch(json)?.group(1) ??
            'Unknown';
    final color = int.tryParse(
          RegExp(r'"color":(\d+)').firstMatch(json)?.group(1) ?? '0',
        ) ??
        0xFF2196F3;
    return UserProfile(displayName: name, avatarColorValue: color);
  }

  UserProfile copyWith(
      {String? displayName, int? avatarColorValue}) {
    return UserProfile(
      displayName: displayName ?? this.displayName,
      avatarColorValue: avatarColorValue ?? this.avatarColorValue,
    );
  }
}

// Saved peer — remembered after a chat session
class SavedPeer {
  final String displayName;
  final int avatarColorValue;
  final String lastSeen; // ISO 8601 date string

  const SavedPeer({
    required this.displayName,
    required this.avatarColorValue,
    required this.lastSeen,
  });

  String toJson() {
    return '{"name":"$displayName","color":$avatarColorValue,"lastSeen":"$lastSeen"}';
  }

  static SavedPeer fromJson(String json) {
    final name =
        RegExp(r'"name":"([^"]+)"').firstMatch(json)?.group(1) ??
            'Unknown';
    final color = int.tryParse(
          RegExp(r'"color":(\d+)').firstMatch(json)?.group(1) ?? '0',
        ) ??
        0xFF2196F3;
    final lastSeen =
        RegExp(r'"lastSeen":"([^"]+)"').firstMatch(json)?.group(1) ??
            DateTime.now().toIso8601String();
    return SavedPeer(
      displayName: name,
      avatarColorValue: color,
      lastSeen: lastSeen,
    );
  }
}