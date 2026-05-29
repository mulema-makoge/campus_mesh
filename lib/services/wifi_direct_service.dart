import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import '../models/message.dart';
import 'crypto_service.dart';

class WifiDirectService {
  FlutterP2pHost? _host;
  FlutterP2pClient? _client;
  bool _initialized = false;
  bool _keyExchangeDone = false;

  final _crypto = CryptoService();
  bool _cryptoReady = false;

  final Set<String> _seenMessageIds = {};
  static const int _defaultTTL = 3;
  String? _myDeviceId;
  String? _pendingPublicKey;

  int? _lastSentMs;

  final List<List<String>> _recentRelayPaths = [];
  List<List<String>> get recentRelayPaths =>
      List.unmodifiable(_recentRelayPaths);

  StreamSubscription<String>? _messageSubscription;

  final _messageController = StreamController<String>.broadcast();
  Stream<String> get messageStream => _messageController.stream;

  final _peersController =
      StreamController<List<BleDiscoveredDevice>>.broadcast();
  Stream<List<BleDiscoveredDevice>> get peersStream =>
      _peersController.stream;

  final _connectionController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStream => _connectionController.stream;

  final _relayController = StreamController<List<String>>.broadcast();
  Stream<List<String>> get relayStream => _relayController.stream;

  final _latencyController = StreamController<int>.broadcast();
  Stream<int> get latencyStream => _latencyController.stream;

  final _connectionRequestController =
      StreamController<String>.broadcast();
  Stream<String> get connectionRequestStream =>
      _connectionRequestController.stream;

  final _connectionRejectedController =
      StreamController<void>.broadcast();
  Stream<void> get connectionRejectedStream =>
      _connectionRejectedController.stream;

  // Mesh delivery events — emits meshId:status
  final _meshDeliveryController =
      StreamController<String>.broadcast();
  Stream<String> get meshDeliveryStream =>
      _meshDeliveryController.stream;

  bool _isHost = false;
  bool get isHost => _isHost;
  bool get cryptoReady => _cryptoReady;
  String? get myDeviceId => _myDeviceId;

  String _generateId() {
    final rand = Random.secure();
    return List.generate(
        8,
        (_) =>
            rand.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  void _emitRelayPath(List<String> path) {
    _recentRelayPaths.add(path);
    if (_recentRelayPaths.length > 50) _recentRelayPaths.removeAt(0);
    if (!_relayController.isClosed) _relayController.add(path);
  }

  Future<bool> _waitForCrypto(
      {int maxRetries = 20,
      Duration interval = const Duration(milliseconds: 500)}) async {
    int retries = 0;
    while (!_cryptoReady && retries < maxRetries) {
      await Future.delayed(interval);
      retries++;
    }
    return _cryptoReady;
  }

  Future<void> _sendPlain(String message) async {
    if (_isHost) {
      await _host?.broadcastText(message);
    } else {
      await _client?.broadcastText(message);
    }
  }

  static Future<bool> isBluetoothOn() async {
    final host = FlutterP2pHost();
    await host.initialize();
    final on = await host.checkBluetoothEnabled();
    await host.dispose();
    return on;
  }

  // ── START AS HOST (proximity mode — advertise + wait) ─────────
  Future<String?> startAsHost() async {
    try {
      _isHost = true;
      _myDeviceId = 'host_${_generateId().substring(0, 4)}';
      _host = FlutterP2pHost();
      await _host!.initialize();
      _initialized = true;

      await _host!.askP2pPermissions();
      await _host!.askBluetoothPermissions();

      if (!await _host!.checkWifiEnabled()) {
        await _host!.enableWifiServices();
        await Future.delayed(const Duration(seconds: 1));
      }
      if (!await _host!.checkBluetoothEnabled()) {
        await _host!.enableBluetoothServices();
        await Future.delayed(const Duration(seconds: 1));
      }
      if (!await _host!.checkLocationEnabled()) {
        await _host!.enableLocationServices();
        await Future.delayed(const Duration(seconds: 1));
      }

      await _crypto.generateKeyPair();
      _pendingPublicKey = await _crypto.getPublicKeyBase64();
      final ourPublicKey = _pendingPublicKey!;

      _messageSubscription =
          _host!.streamReceivedTexts().listen((msg) async {
        await _handleIncomingMessage(msg, ourPublicKey);
      });

      _host!.streamHotspotState().listen((state) {
        if (!_connectionController.isClosed) {
          _connectionController.add(state.isActive);
        }
      });

      _host!.streamClientList().listen((clients) async {
        if (clients.isNotEmpty && !_connectionController.isClosed) {
          _connectionController.add(true);
        }
      });

      await _host!.createGroup();
      return null;
    } catch (e) {
      return 'Failed to start host: $e';
    }
  }

  // ── START AS CLIENT (scan + connect to specific peer) ─────────
  Future<String?> startAsClient() async {
    try {
      _isHost = false;
      _myDeviceId = 'client_${_generateId().substring(0, 4)}';
      _client = FlutterP2pClient();
      await _client!.initialize();
      _initialized = true;

      await _client!.askP2pPermissions();
      await _client!.askBluetoothPermissions();

      if (!await _client!.checkWifiEnabled()) {
        await _client!.enableWifiServices();
        await Future.delayed(const Duration(seconds: 1));
      }
      if (!await _client!.checkBluetoothEnabled()) {
        await _client!.enableBluetoothServices();
        await Future.delayed(const Duration(seconds: 1));
      }
      if (!await _client!.checkLocationEnabled()) {
        await _client!.enableLocationServices();
        await Future.delayed(const Duration(seconds: 1));
      }

      await _crypto.generateKeyPair();
      final ourPublicKey = await _crypto.getPublicKeyBase64();

      _messageSubscription =
          _client!.streamReceivedTexts().listen((msg) async {
        await _handleIncomingMessage(msg, ourPublicKey);
      });

      _client!.streamHotspotState().listen((state) {
        if (!_connectionController.isClosed) {
          _connectionController.add(state.isActive);
        }
      });

      await _client!.startScan((devices) {
        if (!_peersController.isClosed) _peersController.add(devices);
      });

      return null;
    } catch (e) {
      return 'Failed to start client: $e';
    }
  }

  // ── Message Handler ───────────────────────────────────────────
  Future<void> _handleIncomingMessage(
      String msg, String ourPublicKey) async {
    if (msg.startsWith('REQUEST:')) {
      final requesterName = msg.substring(8);
      if (!_connectionRequestController.isClosed) {
        _connectionRequestController.add(requesterName);
      }
    } else if (msg == 'REJECT:') {
      if (!_connectionRejectedController.isClosed) {
        _connectionRejectedController.add(null);
      }
    } else if (msg == 'DISCONNECT:') {
      if (!_messageController.isClosed) {
        _messageController.add('PEER_DISCONNECTED:');
      }
    } else if (msg.startsWith('MESH_ACK:') ||
        msg.startsWith('MESH_READ:') ||
        msg.startsWith('MESH_REJECT:')) {
      // Relay delivery acknowledgements back through mesh
      await _handleMeshAck(msg);
    } else if (msg.startsWith('PK:') && !_cryptoReady) {
      final peerPublicKey = msg.substring(3);
      await _crypto.deriveSharedSecret(peerPublicKey);
      _cryptoReady = true;
      debugPrint('Crypto ready');
      if (!_isHost) {
        await _client!.broadcastText('PK:$ourPublicKey');
      }
    } else if (msg.startsWith('MESH:')) {
      await _handleMeshMessage(msg.substring(5));
    } else if (msg.startsWith('ENC:')) {
      if (_cryptoReady) {
        try {
          final encrypted = msg.substring(4);
          final decrypted = await _crypto.decrypt(encrypted);

          String finalMessage = decrypted;
          if (decrypted.startsWith('TIME:')) {
            final parts = decrypted.substring(5).split('|');
            if (parts.length >= 2) {
              finalMessage = parts.sublist(1).join('|');
            }
          }

          _emitRelayPath(['peer', _myDeviceId ?? 'me']);

          if (!_messageController.isClosed) {
            _messageController.add(finalMessage);
          }
          await _sendReadReceiptDirect();
        } catch (e) {
          debugPrint('Decryption failed: $e');
        }
      }
    } else if (msg == 'TYPING:') {
      if (!_messageController.isClosed) {
        _messageController.add('TYPING:');
      }
    } else if (msg == 'READ:') {
      if (_lastSentMs != null) {
        final rtt =
            DateTime.now().millisecondsSinceEpoch - _lastSentMs!;
        _lastSentMs = null;
        if (!_latencyController.isClosed) _latencyController.add(rtt);
      }
      if (!_messageController.isClosed) {
        _messageController.add('READ:');
      }
    } else if (!msg.startsWith('PK:')) {
      if (!_messageController.isClosed) {
        _messageController.add(msg);
      }
    }
  }

  // ── Mesh ACK Handler ──────────────────────────────────────────
  Future<void> _handleMeshAck(String msg) async {
    // Format: MESH_ACK:<meshId>, MESH_READ:<meshId>, MESH_REJECT:<meshId>
    if (!_meshDeliveryController.isClosed) {
      _meshDeliveryController.add(msg);
    }
    // Relay the ACK back through the mesh if needed
    // (same relay mechanism as regular mesh messages)
    final parts = msg.split(':');
    if (parts.length >= 2) {
      final ackMeshId = '${parts[0]}:${parts[1]}';
      if (!_seenMessageIds.contains('ack_$ackMeshId')) {
        _seenMessageIds.add('ack_$ackMeshId');
        await _sendPlain(msg);
      }
    }
  }

  // ── Mesh Relay Handler ────────────────────────────────────────
  Future<void> _handleMeshMessage(String meshJson) async {
    try {
      final meshMsg = MeshMessage.fromJson(meshJson);

      if (_seenMessageIds.contains(meshMsg.id)) return;
      _seenMessageIds.add(meshMsg.id);

      final hopPath = [...meshMsg.hopPath, _myDeviceId ?? 'unknown'];
      _emitRelayPath(hopPath);

      if (_cryptoReady) {
        try {
          final decrypted = await _crypto.decrypt(meshMsg.payload);
          // Format: "senderName|senderColor|content"
          if (!_messageController.isClosed) {
            _messageController.add('📡MESH:${meshMsg.id}:$decrypted');
          }
          // Send delivery ACK back through mesh
          await _sendMeshAck(meshMsg.id);
        } catch (_) {
          // Not for us — just relay
        }
      }

      if (meshMsg.ttl > 0) {
        final relayed = meshMsg.decrementTTL(_myDeviceId ?? 'unknown');
        await _sendPlain('MESH:${relayed.toJson()}');
      }
    } catch (e) {
      debugPrint('Relay error: $e');
    }
  }

  Future<void> _sendMeshAck(String meshId) async {
    final ackMsg = 'MESH_ACK:$meshId';
    if (!_seenMessageIds.contains('ack_$ackMsg')) {
      _seenMessageIds.add('ack_$ackMsg');
      await _sendPlain(ackMsg);
    }
  }

  Future<void> sendMeshReadAck(String meshId) async {
    await _sendPlain('MESH_READ:$meshId');
  }

  Future<void> sendMeshRejectAck(String meshId) async {
    await _sendPlain('MESH_REJECT:$meshId');
  }

  // ── CONNECTION REQUEST ────────────────────────────────────────
  Future<void> sendConnectionRequest(String displayName) async {
    await _sendPlain('REQUEST:$displayName');
  }

  Future<void> acceptConnectionRequest() async {
    if (_pendingPublicKey != null && !_keyExchangeDone) {
      _keyExchangeDone = true;
      await _sendPlain('PK:$_pendingPublicKey');
    }
  }

  Future<void> rejectConnectionRequest() async {
    await _sendPlain('REJECT:');
  }

  // ── CONNECT ───────────────────────────────────────────────────
  Future<String?> connectToPeer(BleDiscoveredDevice device) async {
    try {
      await _client?.stopScan();
      await _client?.connectWithDevice(
        device,
        timeout: const Duration(seconds: 30),
      );
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  // ── SEND MESSAGE ──────────────────────────────────────────────
  Future<void> sendMessage(String message) async {
    if (!_cryptoReady) {
      final ready = await _waitForCrypto();
      if (!ready) return;
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final withTime = 'TIME:$timestamp|$message';
    final encrypted = await _crypto.encrypt(withTime);
    final payload = 'ENC:$encrypted';

    _lastSentMs = timestamp;
    _emitRelayPath([_myDeviceId ?? 'me', 'peer']);

    if (_isHost) {
      await _host?.broadcastText(payload);
    } else {
      await _client?.broadcastText(payload);
    }
  }

  // ── SEND MESH MESSAGE ─────────────────────────────────────────
  Future<String?> sendMeshMessage(String message,
      {String? recipientDisplayName}) async {
    if (!_cryptoReady) {
      final ready = await _waitForCrypto();
      if (!ready) return null;
    }
    final encrypted = await _crypto.encrypt(message);
    final id = _generateId();
    final meshMsg = MeshMessage(
      id: id,
      payload: encrypted,
      ttl: _defaultTTL,
      hopPath: [_myDeviceId ?? 'unknown'],
      senderId: _myDeviceId ?? 'unknown',
      recipientDisplayName: recipientDisplayName,
    );
    _seenMessageIds.add(meshMsg.id);
    await _sendPlain('MESH:${meshMsg.toJson()}');
    return id; // Return ID for delivery tracking
  }

  // ── SEND CHANNEL MESSAGE ──────────────────────────────────────
  Future<void> sendChannelMessage(String message) async {
    await sendMessage('BROADCAST:$message');
  }

  // ── TYPING ────────────────────────────────────────────────────
  Future<void> sendTypingIndicator() async {
    if (!_cryptoReady) return;
    await _sendPlain('TYPING:');
  }

  // ── READ RECEIPT ──────────────────────────────────────────────
  Future<void> _sendReadReceiptDirect() async {
    await _sendPlain('READ:');
  }

  Future<void> sendReadReceipt() async {
    if (!_cryptoReady) {
      final ready = await _waitForCrypto(maxRetries: 10);
      if (!ready) return;
    }
    await _sendReadReceiptDirect();
  }

  Future<void> sendDisconnectNotification() async {
    await _sendPlain('DISCONNECT:');
  }

  Future<void> stopScan() async => await _client?.stopScan();

  Future<void> disconnect() async {
    _messageSubscription?.cancel();
    _messageSubscription = null;
    _lastSentMs = null;
    try { await _client?.stopScan(); } catch (_) {}
    try { await _host?.removeGroup(); } catch (_) {}
    try { await _client?.disconnect(); } catch (_) {}
    _host = null;
    _client = null;
    _initialized = false;
    _cryptoReady = false;
    _keyExchangeDone = false;
    _pendingPublicKey = null;
    _seenMessageIds.clear();
    _crypto.clearSharedSecret();
  }

  void dispose() {
    _messageSubscription?.cancel();
    if (!_messageController.isClosed) _messageController.close();
    if (!_peersController.isClosed) _peersController.close();
    if (!_connectionController.isClosed) _connectionController.close();
    if (!_relayController.isClosed) _relayController.close();
    if (!_latencyController.isClosed) _latencyController.close();
    if (!_connectionRequestController.isClosed) {
      _connectionRequestController.close();
    }
    if (!_connectionRejectedController.isClosed) {
      _connectionRejectedController.close();
    }
    if (!_meshDeliveryController.isClosed) {
      _meshDeliveryController.close();
    }
    _crypto.dispose();
    if (_initialized) {
      try { _host?.dispose(); } catch (_) {}
      try { _client?.dispose(); } catch (_) {}
    }
  }
}