import 'package:flutter/material.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import '../../services/wifi_direct_service.dart';

class WifiDirectScreen extends StatefulWidget {
  const WifiDirectScreen({super.key});

  @override
  State<WifiDirectScreen> createState() => _WifiDirectScreenState();
}

class _WifiDirectScreenState extends State<WifiDirectScreen> {
  final WifiDirectService _service = WifiDirectService();
  final TextEditingController _messageController = TextEditingController();
  final List<String> _messages = [];

  List<BleDiscoveredDevice> _peers = [];
  bool _isConnected = false;
  bool _isLoading = false;
  String _role = 'none';
  String _statusText = 'Choose your role below';

  @override
  void initState() {
    super.initState();

    _service.peersStream.listen((peers) {
      setState(() => _peers = peers);
    });

    _service.messageStream.listen((message) {
      setState(() => _messages.add('Received: $message'));
    });

    _service.connectionStream.listen((connected) {
      setState(() {
        _isConnected = connected;
        if (connected) {
          _statusText =
              'Connected as ${_service.isHost ? "Host" : "Client"}';
        }
      });
    });

    // Check Bluetooth on load and warn user
    _checkBluetooth();
  }

  Future<void> _checkBluetooth() async {
    final btOn = await WifiDirectService.isBluetoothOn();
    if (!btOn && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Please turn Bluetooth ON before starting'),
          duration: Duration(seconds: 5),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _startAsHost() async {
    setState(() {
      _isLoading = true;
      _role = 'host';
      _statusText = 'Setting up host...';
    });

    final error = await _service.startAsHost();

    if (error != null) {
      setState(() {
        _role = 'none';
        _statusText = 'Choose your role below';
      });
      _showError(error);
    } else {
      setState(() => _statusText = 'Waiting for client to connect...');
    }

    setState(() => _isLoading = false);
  }

  Future<void> _startAsClient() async {
    setState(() {
      _isLoading = true;
      _role = 'client';
      _statusText = 'Scanning for host...';
    });

    final error = await _service.startAsClient();

    if (error != null) {
      setState(() {
        _role = 'none';
        _statusText = 'Choose your role below';
      });
      _showError(error);
    }

    setState(() => _isLoading = false);
  }

  Future<void> _connectToPeer(BleDiscoveredDevice device) async {
    setState(() {
      _isLoading = true;
      _statusText = 'Connecting to ${device.deviceName}...';
    });

    final error = await _service.connectToPeer(device);

    if (error != null) {
      _showError('Connection failed: $error');
      setState(() => _statusText = 'Scanning for host...');
    }

    setState(() => _isLoading = false);
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    await _service.sendMessage(text);
    setState(() => _messages.add('Sent: $text'));
    _messageController.clear();
  }

  @override
  void dispose() {
    _service.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wi-Fi Direct'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Status bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: _isConnected
                ? Colors.green[100]
                : _role == 'none'
                    ? Colors.orange[50]
                    : Colors.blue[50],
            child: Row(
              children: [
                if (_isLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                if (_isLoading) const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isConnected ? '🟢 $_statusText' : '🔵 $_statusText',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),

          // Role selection
          if (_role == 'none')
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text(
                    'Make sure Bluetooth and Wi-Fi are ON\nthen select your role:',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _startAsHost,
                          icon: const Icon(Icons.router),
                          label: const Text('Host'),
                          style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.all(16)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _startAsClient,
                          icon: const Icon(Icons.phone_android),
                          label: const Text('Client'),
                          style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.all(16)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          // Peer list for client
          if (_role == 'client' && !_isConnected)
            Expanded(
              flex: 1,
              child: _peers.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text('Scanning for host via BLE...'),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _peers.length,
                      itemBuilder: (context, index) {
                        final peer = _peers[index];
                        return ListTile(
                          leading: const Icon(Icons.router),
                          title: Text(peer.deviceName),
                          subtitle: Text(peer.deviceAddress),
                          trailing: ElevatedButton(
                            onPressed:
                                _isLoading ? null : () => _connectToPeer(peer),
                            child: const Text('Connect'),
                          ),
                        );
                      },
                    ),
            ),

          // Messages
          Expanded(
            flex: 2,
            child: _messages.isEmpty
                ? Center(
                    child: Text(
                      _isConnected
                          ? 'Type a message below'
                          : 'No messages yet',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isSent = msg.startsWith('Sent:');
                      return Align(
                        alignment: isSent
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isSent
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey[200],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            msg,
                            style: TextStyle(
                                color:
                                    isSent ? Colors.white : Colors.black),
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Message input
          if (_isConnected)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sendMessage,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
