import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

class CryptoService {
  // X25519 for key exchange
  final _x25519 = X25519();

  // AES-GCM for message encryption
  final _aesGcm = AesGcm.with256bits();

  // Our own key pair (generated once on first use)
  SimpleKeyPair? _keyPair;

  // Shared secret derived after handshake
  SecretKey? _sharedSecret;

  // ── Key Generation ────────────────────────────────────────────

  // Generate our X25519 key pair
  Future<void> generateKeyPair() async {
    _keyPair = await _x25519.newKeyPair();
    debugPrint('CryptoService: Key pair generated');
  }

  // Get our public key as a base64 string for sharing via BLE
  Future<String> getPublicKeyBase64() async {
    if (_keyPair == null) await generateKeyPair();
    final publicKey = await _keyPair!.extractPublicKey();
    final bytes = publicKey.bytes;
    return base64Encode(bytes);
  }

  // ── Key Exchange ──────────────────────────────────────────────

  // Derive shared secret from peer's public key (X25519 ECDH)
  Future<void> deriveSharedSecret(String peerPublicKeyBase64) async {
    if (_keyPair == null) await generateKeyPair();

    final peerPublicKeyBytes = base64Decode(peerPublicKeyBase64);
    final peerPublicKey = SimplePublicKey(
      peerPublicKeyBytes,
      type: KeyPairType.x25519,
    );

    _sharedSecret = await _x25519.sharedSecretKey(
      keyPair: _keyPair!,
      remotePublicKey: peerPublicKey,
    );

    debugPrint('CryptoService: Shared secret derived');
  }

  // ── Encryption ────────────────────────────────────────────────

  // Encrypt a plain text message — returns base64 encoded ciphertext
  Future<String> encrypt(String plainText) async {
    if (_sharedSecret == null) {
      throw StateError('Shared secret not yet derived. Call deriveSharedSecret first.');
    }

    final plainBytes = utf8.encode(plainText);
    final secretBox = await _aesGcm.encrypt(
      plainBytes,
      secretKey: _sharedSecret!,
    );

    // Combine nonce + mac + ciphertext into one base64 payload
    final combined = Uint8List.fromList([
      ...secretBox.nonce,
      ...secretBox.mac.bytes,
      ...secretBox.cipherText,
    ]);

    return base64Encode(combined);
  }

  // ── Decryption ────────────────────────────────────────────────

  // Decrypt a base64 encoded ciphertext — returns plain text
  Future<String> decrypt(String encryptedBase64) async {
    if (_sharedSecret == null) {
      throw StateError('Shared secret not yet derived. Call deriveSharedSecret first.');
    }

    final combined = base64Decode(encryptedBase64);

    // Extract nonce (12 bytes), mac (16 bytes), ciphertext (rest)
    final nonce = combined.sublist(0, 12);
    final mac = Mac(combined.sublist(12, 28));
    final cipherText = combined.sublist(28);

    final secretBox = SecretBox(cipherText, nonce: nonce, mac: mac);

    final plainBytes = await _aesGcm.decrypt(
      secretBox,
      secretKey: _sharedSecret!,
    );

    return utf8.decode(plainBytes);
  }

  // ── Utilities ─────────────────────────────────────────────────

  bool get hasSharedSecret => _sharedSecret != null;

  void clearSharedSecret() {
    _sharedSecret = null;
    debugPrint('CryptoService: Shared secret cleared');
  }

  void dispose() {
    _sharedSecret = null;
    _keyPair = null;
  }
}