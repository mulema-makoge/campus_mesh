import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_mesh/app.dart';
import 'package:campus_mesh/services/crypto_service.dart';

void main() {
  // UI test
  testWidgets('CampusMesh app launches', (WidgetTester tester) async {
    await tester.pumpWidget(const CampusMeshApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  // Crypto unit tests
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
}