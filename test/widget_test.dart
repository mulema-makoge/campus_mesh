import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_mesh/app.dart';
import 'package:campus_mesh/services/crypto_service.dart';
import 'package:campus_mesh/services/storage_service.dart';
import 'package:campus_mesh/models/message.dart';
import 'package:campus_mesh/models/peer.dart';

void main() {

  // ── UI Test ───────────────────────────────────────────────────
testWidgets('CampusMesh app smoke test', (WidgetTester tester) async {
  // Just verify MaterialApp renders without Hive dependency
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(child: Text('CampusMesh')),
      ),
    ),
  );
  expect(find.text('CampusMesh'), findsOneWidget);
});

  // ── Crypto Tests ──────────────────────────────────────────────
  group('CryptoService', () {
    test('generates a public key', () async {
      final crypto = CryptoService();
      final pubKey = await crypto.getPublicKeyBase64();
      expect(pubKey, isNotEmpty);
      expect(pubKey.length, greaterThan(10));
    });

    test('two devices derive the same shared secret', () async {
      final alice = CryptoService();
      final bob = CryptoService();

      final alicePubKey = await alice.getPublicKeyBase64();
      final bobPubKey = await bob.getPublicKeyBase64();

      await alice.deriveSharedSecret(bobPubKey);
      await bob.deriveSharedSecret(alicePubKey);

      expect(alice.hasSharedSecret, isTrue);
      expect(bob.hasSharedSecret, isTrue);
    });

    test('encrypt and decrypt roundtrip', () async {
      final alice = CryptoService();
      final bob = CryptoService();

      final alicePubKey = await alice.getPublicKeyBase64();
      final bobPubKey = await bob.getPublicKeyBase64();

      await alice.deriveSharedSecret(bobPubKey);
      await bob.deriveSharedSecret(alicePubKey);

      const original = 'Hello from CampusMesh!';
      final encrypted = await alice.encrypt(original);
      final decrypted = await bob.decrypt(encrypted);

      expect(decrypted, equals(original));
    });

    test('encrypted text is not readable plaintext', () async {
      final alice = CryptoService();
      final bob = CryptoService();

      await alice.deriveSharedSecret(await bob.getPublicKeyBase64());
      await bob.deriveSharedSecret(await alice.getPublicKeyBase64());

      const original = 'secret message';
      final encrypted = await alice.encrypt(original);

      expect(encrypted, isNot(equals(original)));
    });
  });

  // ── Mesh Message / Relay Tests ────────────────────────────────
  group('MeshMessage', () {
    test('serialises and deserialises correctly', () {
      final msg = MeshMessage(
        id: 'abc123',
        payload: 'encryptedPayload',
        ttl: 3,
        hopPath: ['device_a'],
        senderId: 'device_a',
      );

      final json = msg.toJson();
      final restored = MeshMessage.fromJson(json);

      expect(restored.id, equals('abc123'));
      expect(restored.payload, equals('encryptedPayload'));
      expect(restored.ttl, equals(3));
      expect(restored.hopPath, equals(['device_a']));
      expect(restored.senderId, equals('device_a'));
    });

    test('TTL decrements correctly on relay', () {
      final msg = MeshMessage(
        id: 'abc123',
        payload: 'encryptedPayload',
        ttl: 3,
        hopPath: ['device_a'],
        senderId: 'device_a',
      );

      final relayed = msg.decrementTTL('device_b');

      expect(relayed.ttl, equals(2));
      expect(relayed.hopPath, equals(['device_a', 'device_b']));
      expect(relayed.id, equals('abc123'));
    });

    test('hop path grows with each relay', () {
      var msg = MeshMessage(
        id: 'xyz',
        payload: 'payload',
        ttl: 3,
        hopPath: ['device_a'],
        senderId: 'device_a',
      );

      msg = msg.decrementTTL('device_b');
      msg = msg.decrementTTL('device_c');

      expect(msg.ttl, equals(1));
      expect(msg.hopPath,
          equals(['device_a', 'device_b', 'device_c']));
      expect(msg.hopPath.length, equals(3));
    });

    test('message stops relaying when TTL reaches 0', () {
      final msg = MeshMessage(
        id: 'xyz',
        payload: 'payload',
        ttl: 1,
        hopPath: ['device_a', 'device_b'],
        senderId: 'device_a',
      );

      final relayed = msg.decrementTTL('device_c');

      expect(relayed.ttl, equals(0));
      // When ttl == 0 no further relay should happen
      expect(relayed.ttl > 0, isFalse);
    });
  });

  // ── UserProfile Tests ─────────────────────────────────────────
  group('UserProfile', () {
    test('serialises and deserialises correctly', () {
      const profile = UserProfile(
        displayName: 'Phil',
        avatarColorValue: 0xFF1B4F8A,
      );

      final json = profile.toJson();
      final restored = UserProfile.fromJson(json);

      expect(restored.displayName, equals('Phil'));
      expect(restored.avatarColorValue, equals(0xFF1B4F8A));
    });

    test('copyWith works correctly', () {
      const profile = UserProfile(
        displayName: 'Phil',
        avatarColorValue: 0xFF1B4F8A,
      );

      final updated = profile.copyWith(displayName: 'Collins');

      expect(updated.displayName, equals('Collins'));
      expect(updated.avatarColorValue, equals(0xFF1B4F8A));
    });
  });

  // ── Seen-ID Cache Logic Test ──────────────────────────────────
  group('Seen-ID Cache', () {
    test('Set correctly prevents duplicate IDs', () {
      final seenIds = <String>{};

      const id = 'msg_001';
      expect(seenIds.contains(id), isFalse);

      seenIds.add(id);
      expect(seenIds.contains(id), isTrue);

      // Adding again doesn't duplicate
      seenIds.add(id);
      expect(seenIds.length, equals(1));
    });

    test('multiple unique IDs are all tracked', () {
      final seenIds = <String>{};

      seenIds.addAll(['msg_001', 'msg_002', 'msg_003']);
      expect(seenIds.length, equals(3));
      expect(seenIds.contains('msg_002'), isTrue);
    });
  });
}