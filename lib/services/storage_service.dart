import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/peer.dart';

class StorageService {
  static const _boxName = 'campus_mesh_prefs';
  static const _profileKey = 'user_profile';
  static const _publicKeyKey = 'public_key';
  static const _savedPeersKey = 'saved_peers';

  Box? _box;

  // ── Initialise ────────────────────────────────────────────────
  Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox(_boxName);
    debugPrint('StorageService: Hive initialised');
  }

  // ── User Profile ──────────────────────────────────────────────
  Future<void> saveProfile(UserProfile profile) async {
    await _box?.put(_profileKey, profile.toJson());
    debugPrint(
        'StorageService: Profile saved — ${profile.displayName}');
  }

  UserProfile? getProfile() {
    final json = _box?.get(_profileKey);
    if (json == null) return null;
    return UserProfile.fromJson(json);
  }

  bool get hasProfile => _box?.containsKey(_profileKey) ?? false;

  // ── Public Key ────────────────────────────────────────────────
  Future<void> savePublicKey(String publicKeyBase64) async {
    await _box?.put(_publicKeyKey, publicKeyBase64);
  }

  String? getPublicKey() => _box?.get(_publicKeyKey);

  // ── Saved Peers ───────────────────────────────────────────────
  Future<void> savePeer(SavedPeer peer) async {
    final existing = getSavedPeers();
    // Update if exists, add if new
    final updated = [
      peer,
      ...existing.where((p) => p.displayName != peer.displayName),
    ];
    // Keep last 20 peers
    final trimmed = updated.take(20).toList();
    final jsonList =
        trimmed.map((p) => p.toJson()).toList().join('||');
    await _box?.put(_savedPeersKey, jsonList);
    debugPrint('StorageService: Saved peer ${peer.displayName}');
  }

  List<SavedPeer> getSavedPeers() {
    final raw = _box?.get(_savedPeersKey) as String?;
    if (raw == null || raw.isEmpty) return [];
    return raw
        .split('||')
        .map((json) => SavedPeer.fromJson(json))
        .toList();
  }

  Future<void> clearAll() async {
    await _box?.clear();
  }

  Future<void> dispose() async {
    await _box?.close();
  }
}