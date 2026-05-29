import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/peer.dart';

class StorageService {
  static const _boxName = 'campus_mesh_prefs';
  static const _profileKey = 'user_profile';
  static const _publicKeyKey = 'public_key';
  static const _savedPeersKey = 'saved_peers';
  static const _onboardingKey = 'onboarding_done';
  static const _messagesPrefix = 'messages_';
  static const _24h = 24 * 60 * 60 * 1000; // ms

  Box? _box;

  Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox(_boxName);
    debugPrint('StorageService: Hive initialised');
  }

  // ── Onboarding ────────────────────────────────────────────────
  bool get onboardingDone =>
      _box?.get(_onboardingKey, defaultValue: false) ?? false;

  Future<void> setOnboardingDone() async {
    await _box?.put(_onboardingKey, true);
  }

  // ── User Profile ──────────────────────────────────────────────
  Future<void> saveProfile(UserProfile profile) async {
    await _box?.put(_profileKey, profile.toJson());
    debugPrint('StorageService: Profile saved — ${profile.displayName}');
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
    final updated = [
      peer,
      ...existing.where((p) => p.displayName != peer.displayName),
    ];
    final trimmed = updated.take(20).toList();
    final jsonList = trimmed.map((p) => p.toJson()).join('||');
    await _box?.put(_savedPeersKey, jsonList);
  }

  List<SavedPeer> getSavedPeers() {
    final raw = _box?.get(_savedPeersKey) as String?;
    if (raw == null || raw.isEmpty) return [];
    return raw.split('||').map((j) => SavedPeer.fromJson(j)).toList();
  }

  // ── Message History (24h) ─────────────────────────────────────
  Future<void> saveMessages(
      String peerName, List<Map<String, dynamic>> messages) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    // Keep last 100 messages within 24h
    final filtered = messages
        .where((m) {
          final ts = m['timestamp'] as int? ?? now;
          return (now - ts) < _24h;
        })
        .toList();
    final trimmed =
        filtered.length > 100 ? filtered.sublist(filtered.length - 100) : filtered;
    final key = '$_messagesPrefix${peerName.toLowerCase().replaceAll(' ', '_')}';
    await _box?.put(key, jsonEncode(trimmed));
  }

  List<Map<String, dynamic>> getMessages(String peerName) {
    final key =
        '$_messagesPrefix${peerName.toLowerCase().replaceAll(' ', '_')}';
    final raw = _box?.get(key) as String?;
    if (raw == null || raw.isEmpty) return [];
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => Map<String, dynamic>.from(e))
          .where((m) {
            final ts = m['timestamp'] as int? ?? 0;
            return (now - ts) < _24h;
          })
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> clearAll() async => await _box?.clear();
  Future<void> dispose() async => await _box?.close();
}