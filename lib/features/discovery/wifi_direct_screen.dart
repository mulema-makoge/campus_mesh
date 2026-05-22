import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import '../../models/peer.dart';
import '../../services/storage_service.dart';
import '../../services/wifi_direct_service.dart';

class WifiDirectScreen extends StatefulWidget {
  final StorageService storage;
  const WifiDirectScreen({super.key, required this.storage});

  @override
  State<WifiDirectScreen> createState() => _WifiDirectScreenState();
}

class _WifiDirectScreenState extends State<WifiDirectScreen> {
  final WifiDirectService _service = WifiDirectService();
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final List<String> _messages = [];

  List<BleDiscoveredDevice> _peers = [];
  bool _isConnected = false;
  bool _isLoading = false;
  String _role = 'none';
  String _statusText = 'Choose your role below';
  UserProfile? _myProfile;
  UserProfile? _peerProfile;

  bool _peerIsTyping = false;
  Timer? _typingTimer;
  Timer? _peerTypingTimer;

  final List<int> _colorOptions = [
    0xFF2196F3, 0xFF4CAF50, 0xFFFF5722,
    0xFF9C27B0, 0xFFFF9800, 0xFF00BCD4,
  ];
  int _selectedColor = 0xFF2196F3;

  String _timestamp() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();

    _service.peersStream.listen((peers) {
      setState(() => _peers = peers);
    });

    _service.messageStream.listen((message) {
      if (message.startsWith('PROFILE:')) {
        final profileJson = message.substring(8);
        setState(() {
          _peerProfile = UserProfile.fromJson(profileJson);
          _statusText =
              'Connected as ${_service.isHost ? "Host" : "Client"} with ${_peerProfile!.displayName}';
        });
      } else if (message == 'TYPING:') {
        setState(() => _peerIsTyping = true);
        _peerTypingTimer?.cancel();
        _peerTypingTimer = Timer(const Duration(seconds: 3), () {
          setState(() => _peerIsTyping = false);
        });
      } else {
        setState(() => _peerIsTyping = false);
        final senderName = _peerProfile?.displayName ?? 'Peer';
        setState(() =>
            _messages.add('$senderName: $message [${_timestamp()}]'));
      }
    });

    _service.connectionStream.listen((connected) {
      setState(() {
        _isConnected = connected;
        if (connected) {
          _statusText =
              'Connected as ${_service.isHost ? "Host" : "Client"}';
          _shareProfile();
        }
      });
    });

    _checkBluetooth();
  }

  Future<void> _loadProfile() async {
    final profile = widget.storage.getProfile();
    if (profile != null) {
      setState(() {
        _myProfile = profile;
        _nameController.text = profile.displayName;
        _selectedColor = profile.avatarColorValue;
      });
    }
  }

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final profile = UserProfile(
      displayName: name,
      avatarColorValue: _selectedColor,
    );
    await widget.storage.saveProfile(profile);
    setState(() => _myProfile = profile);
  }

  Future<void> _shareProfile() async {
    if (_myProfile != null) {
      final delay = _service.isHost
          ? const Duration(seconds: 2)
          : const Duration(milliseconds: 800);
      await Future.delayed(delay);
      await _service.sendMessage('PROFILE:${_myProfile!.toJson()}');
    }
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
    await _saveProfile();
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
    await _saveProfile();
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
    final myName = _myProfile?.displayName ?? 'Me';
    setState(() => _messages.add('$myName: $text [${_timestamp()}]'));
    _messageController.clear();
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _peerTypingTimer?.cancel();
    _service.dispose();
    _messageController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Widget _buildAvatar(UserProfile? profile, {double radius = 20}) {
    final name = profile?.displayName ?? '?';
    final color = Color(profile?.avatarColorValue ?? 0xFF2196F3);
    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      child: Text(
        name[0].toUpperCase(),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.9,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            if (_myProfile != null) ...[
              _buildAvatar(_myProfile, radius: 16),
              const SizedBox(width: 8),
            ],
            const Text('CampusMesh'),
          ],
        ),
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
                if (_peerProfile != null) ...[
                  _buildAvatar(_peerProfile, radius: 14),
                  const SizedBox(width: 8),
                ],
                if (_isLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                if (_isLoading) const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _peerIsTyping
                        ? '✏️ ${_peerProfile?.displayName ?? "Peer"} is typing...'
                        : _isConnected
                            ? '🟢 $_statusText'
                            : '🔵 $_statusText',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),

          // Profile setup + role selection
          if (_role == 'none')
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Your profile',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildAvatar(
                        UserProfile(
                          displayName: _nameController.text.isEmpty
                              ? '?'
                              : _nameController.text,
                          avatarColorValue: _selectedColor,
                        ),
                        radius: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            hintText: 'Enter your display name',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: _colorOptions.map((color) {
                      return GestureDetector(
                        onTap: () => setState(() => _selectedColor = color),
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Color(color),
                            shape: BoxShape.circle,
                            border: _selectedColor == color
                                ? Border.all(color: Colors.black, width: 2)
                                : null,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Make sure Bluetooth and Wi-Fi are ON:',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _startAsHost,
                          icon: const Icon(Icons.router),
                          label: const Text('Host'),
                          style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.all(14)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _startAsClient,
                          icon: const Icon(Icons.phone_android),
                          label: const Text('Client'),
                          style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.all(14)),
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
                            onPressed: _isLoading
                                ? null
                                : () => _connectToPeer(peer),
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
                      final myName = _myProfile?.displayName ?? 'Me';
                      final isMine = msg.startsWith('$myName:');

                      final timestampMatch =
                          RegExp(r'\[(\d{2}:\d{2})\]$').firstMatch(msg);
                      final timestamp = timestampMatch?.group(1) ?? '';
                      final content = msg
                          .replaceAll(RegExp(r'\s*\[\d{2}:\d{2}\]$'), '');

                      return Align(
                        alignment: isMine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isMine
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey[200],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: isMine
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              Text(
                                content,
                                style: TextStyle(
                                    color: isMine
                                        ? Colors.white
                                        : Colors.black),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                timestamp,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isMine
                                      ? Colors.white70
                                      : Colors.black45,
                                ),
                              ),
                            ],
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
                      onChanged: (_) {
                        _typingTimer?.cancel();
                        _typingTimer = Timer(
                          const Duration(milliseconds: 300),
                          () => _service.sendTypingIndicator(),
                        );
                      },
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