class UserProfile {
  final String displayName;
  final int avatarColorValue; // stored as int, converted to Color in UI

  const UserProfile({
    required this.displayName,
    required this.avatarColorValue,
  });

  // Serialise to JSON string for sharing over the mesh
  String toJson() {
    return '{"name":"$displayName","color":$avatarColorValue}';
  }

  // Deserialise from JSON string received from peer
  static UserProfile fromJson(String json) {
    final name = RegExp(r'"name":"([^"]+)"').firstMatch(json)?.group(1) ?? 'Unknown';
    final color = int.tryParse(
          RegExp(r'"color":(\d+)').firstMatch(json)?.group(1) ?? '0',
        ) ?? 0xFF2196F3;
    return UserProfile(displayName: name, avatarColorValue: color);
  }

  UserProfile copyWith({String? displayName, int? avatarColorValue}) {
    return UserProfile(
      displayName: displayName ?? this.displayName,
      avatarColorValue: avatarColorValue ?? this.avatarColorValue,
    );
  }
}