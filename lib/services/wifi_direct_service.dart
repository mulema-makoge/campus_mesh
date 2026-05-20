import 'dart:async';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';

class WifiDirectService {
  FlutterP2pHost? _host;
  FlutterP2pClient? _client;
  bool _initialized = false;

  StreamSubscription<String>? _messageSubscription;

  final _messageController = StreamController<String>.broadcast();
  Stream<String> get messageStream => _messageController.stream;

  final _peersController =
      StreamController<List<BleDiscoveredDevice>>.broadcast();
  Stream<List<BleDiscoveredDevice>> get peersStream => _peersController.stream;

  final _connectionController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStream => _connectionController.stream;

  bool _isHost = false;
  bool get isHost => _isHost;

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
      _host = FlutterP2pHost();
      await _host!.initialize();
      _initialized = true;

      // Request permissions ONCE — don't loop
      await _host!.askP2pPermissions();
      await _host!.askBluetoothPermissions();

      // Enable services
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

      // Listen for messages
      _messageSubscription = _host!.streamReceivedTexts().listen((msg) {
        if (!_messageController.isClosed) _messageController.add(msg);
      });

      // Listen for connection state
      _host!.streamHotspotState().listen((state) {
        if (!_connectionController.isClosed) {
          _connectionController.add(state.isActive);
        }
      });

      _host!.streamClientList().listen((clients) {
        if (clients.isNotEmpty && !_connectionController.isClosed) {
          _connectionController.add(true);
        }
      });

      // Try to create group — if it fails it's a permission issue
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
      _client = FlutterP2pClient();
      await _client!.initialize();
      _initialized = true;

      // Request permissions ONCE — don't loop
      await _client!.askP2pPermissions();
      await _client!.askBluetoothPermissions();

      // Enable services
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

      // Listen for messages
      _messageSubscription = _client!.streamReceivedTexts().listen((msg) {
        if (!_messageController.isClosed) _messageController.add(msg);
      });

      // Listen for connection state
      _client!.streamHotspotState().listen((state) {
        if (!_connectionController.isClosed) {
          _connectionController.add(state.isActive);
        }
      });

      // Start BLE scan
      await _client!.startScan((devices) {
        if (!_peersController.isClosed) _peersController.add(devices);
      });

      return null;
    } catch (e) {
      return 'Failed to start client: $e';
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

  // ── SEND ──────────────────────────────────────────────────────
  Future<void> sendMessage(String message) async {
    if (_isHost) {
      await _host?.broadcastText(message);
    } else {
      await _client?.broadcastText(message);
    }
  }

  Future<void> stopScan() async => await _client?.stopScan();

  Future<void> disconnect() async {
    try {
      await _host?.removeGroup();
    } catch (_) {}
    try {
      await _client?.disconnect();
    } catch (_) {}
  }

  void dispose() {
    _messageSubscription?.cancel();
    if (!_messageController.isClosed) _messageController.close();
    if (!_peersController.isClosed) _peersController.close();
    if (!_connectionController.isClosed) _connectionController.close();
    if (_initialized) {
      try {
        _host?.dispose();
      } catch (_) {}
      try {
        _client?.dispose();
      } catch (_) {}
    }
  }
}
