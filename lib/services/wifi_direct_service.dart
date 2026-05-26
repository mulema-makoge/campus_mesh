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

  bool _isHost = false;
  bool get isHost => _isHost;
  bool get cryptoReady => _cryptoReady;

  String _generateId() {
    final rand = Random.secure();
    return List.generate(
      8,
      (_) => rand.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static Future<bool> isBluetoothOn() async {
    final host = FlutterP2pHost();
    await host.initialize();
    final on = await host.checkBluetoothEnabled();
    await host.dispose();
    return on;
  }

  // ── HOST ──────────────────────────────────────────────────────
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
      final ourPublicKey = await _crypto.getPublicKeyBase64();

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
          if (!_keyExchangeDone) {
            _keyExchangeDone = true;
            await Future.delayed(const Duration(milliseconds: 500));
            await _host!.broadcastText('PK:$ourPublicKey');
            debugPrint('Host: Sent public key to client');
          }
        }
      });

      await _host!.createGroup();
      return null;
    } catch (e) {
      return 'Failed to start host: $e';
    }
  }

  // ── CLIENT ────────────────────────────────────────────────────
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
    if (msg.startsWith('PK:') && !_cryptoReady) {
      final peerPublicKey = msg.substring(3);
      await _crypto.deriveSharedSecret(peerPublicKey);
      _cryptoReady = true;
      debugPrint('Crypto ready: shared secret derived');
      if (!_isHost) {
        await _client!.broadcastText('PK:$ourPublicKey');
        debugPrint('Client: Sent public key to host');
      }
    } else if (msg.startsWith('MESH:')) {
      await _handleMeshMessage(msg.substring(5));
    } else if (msg.startsWith('ENC:')) {
      if (_cryptoReady) {
        try {
          final encrypted = msg.substring(4);
          final decrypted = await _crypto.decrypt(encrypted);

          // Extract timestamp and calculate latency
          String finalMessage = decrypted;
          if (decrypted.startsWith('TIME:')) {
            final parts = decrypted.substring(5).split('|');
            if (parts.length >= 2) {
              final sentTime = int.tryParse(parts[0]) ?? 0;
              final latency =
                  DateTime.now().millisecondsSinceEpoch - sentTime;
              debugPrint(
                  'Latency emitted: ${latency}ms — stream closed: ${_latencyController.isClosed}');
              if (!_latencyController.isClosed) {
                _latencyController.add(latency);
              }
              finalMessage = parts.sublist(1).join('|');
            }
          }

          if (!_messageController.isClosed) {
            _messageController.add(finalMessage);
          }
          await sendReadReceipt();
        } catch (e) {
          debugPrint('Decryption failed: $e');
        }
      }
    } else if (msg == 'TYPING:') {
      if (!_messageController.isClosed) {
        _messageController.add('TYPING:');
      }
    } else if (msg == 'READ:') {
      if (!_messageController.isClosed) {
        _messageController.add('READ:');
      }
    } else if (!msg.startsWith('PK:')) {
      if (!_messageController.isClosed) {
        _messageController.add(msg);
      }
    }
  }

  // ── Mesh Relay Handler ────────────────────────────────────────
  Future<void> _handleMeshMessage(String meshJson) async {
    try {
      final meshMsg = MeshMessage.fromJson(meshJson);

      if (_seenMessageIds.contains(meshMsg.id)) {
        debugPrint('Relay: Dropping duplicate message ${meshMsg.id}');
        return;
      }
      _seenMessageIds.add(meshMsg.id);

      if (!_relayController.isClosed) {
        _relayController
            .add([...meshMsg.hopPath, _myDeviceId ?? 'unknown']);
      }

      if (_cryptoReady) {
        try {
          final decrypted = await _crypto.decrypt(meshMsg.payload);
          if (!_messageController.isClosed) {
            _messageController.add('📡 $decrypted');
          }
        } catch (_) {}
      }

      if (meshMsg.ttl > 0) {
        final relayed = meshMsg.decrementTTL(_myDeviceId ?? 'unknown');
        final relayPayload = 'MESH:${relayed.toJson()}';
        if (_isHost) {
          await _host?.broadcastText(relayPayload);
        } else {
          await _client?.broadcastText(relayPayload);
        }
        debugPrint(
            'Relay: Forwarded message ${meshMsg.id} with TTL ${relayed.ttl}');
      }
    } catch (e) {
      debugPrint('Relay: Error handling mesh message: $e');
    }
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
    if (_cryptoReady) {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final withTime = 'TIME:$timestamp|$message';
      final encrypted = await _crypto.encrypt(withTime);
      final payload = 'ENC:$encrypted';
      if (_isHost) {
        await _host?.broadcastText(payload);
      } else {
        await _client?.broadcastText(payload);
      }
    } else {
      if (_isHost) {
        await _host?.broadcastText(message);
      } else {
        await _client?.broadcastText(message);
      }
    }
  }

  // ── SEND MESH MESSAGE ─────────────────────────────────────────
  Future<void> sendMeshMessage(String message) async {
    if (!_cryptoReady) return;
    final encrypted = await _crypto.encrypt(message);
    final meshMsg = MeshMessage(
      id: _generateId(),
      payload: encrypted,
      ttl: _defaultTTL,
      hopPath: [_myDeviceId ?? 'unknown'],
      senderId: _myDeviceId ?? 'unknown',
    );
    _seenMessageIds.add(meshMsg.id);
    final payload = 'MESH:${meshMsg.toJson()}';
    if (_isHost) {
      await _host?.broadcastText(payload);
    } else {
      await _client?.broadcastText(payload);
    }
  }

  // ── SEND CHANNEL MESSAGE ──────────────────────────────────────
  Future<void> sendChannelMessage(String message,
      {bool isBroadcast = false}) async {
    final prefix = isBroadcast ? 'BROADCAST:' : 'CHANNEL:';
    await sendMessage('$prefix$message');
  }

  // ── TYPING INDICATOR ──────────────────────────────────────────
  Future<void> sendTypingIndicator() async {
    if (!_cryptoReady) return;
    if (_isHost) {
      await _host?.broadcastText('TYPING:');
    } else {
      await _client?.broadcastText('TYPING:');
    }
  }

  // ── READ RECEIPT ──────────────────────────────────────────────
  Future<void> sendReadReceipt() async {
    if (!_cryptoReady) return;
    if (_isHost) {
      await _host?.broadcastText('READ:');
    } else {
      await _client?.broadcastText('READ:');
    }
  }

  Future<void> stopScan() async => await _client?.stopScan();

  Future<void> disconnect() async {
    try { await _host?.removeGroup(); } catch (_) {}
    try { await _client?.disconnect(); } catch (_) {}
    _cryptoReady = false;
    _keyExchangeDone = false;
    _seenMessageIds.clear();
  }

  void dispose() {
    _messageSubscription?.cancel();
    if (!_messageController.isClosed) _messageController.close();
    if (!_peersController.isClosed) _peersController.close();
    if (!_connectionController.isClosed) _connectionController.close();
    if (!_relayController.isClosed) _relayController.close();
    if (!_latencyController.isClosed) _latencyController.close();
    _crypto.dispose();
    if (_initialized) {
      try { _host?.dispose(); } catch (_) {}
      try { _client?.dispose(); } catch (_) {}
    }
  }
}