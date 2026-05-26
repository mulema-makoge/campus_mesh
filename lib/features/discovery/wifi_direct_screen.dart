import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import '../../models/peer.dart';
import '../../services/storage_service.dart';
import '../../services/wifi_direct_service.dart';

class WifiDirectScreen extends StatefulWidget {
  final StorageService storage;
  final WifiDirectService service;

  const WifiDirectScreen({
    super.key,
    required this.storage,
    required this.service,
  });

  @override
  State<WifiDirectScreen> createState() => _WifiDirectScreenState();
}

class _WifiDirectScreenState extends State<WifiDirectScreen> {
  WifiDirectService get _service => widget.service;

  final TextEditingController _messageController =
      TextEditingController();
  final TextEditingController _nameController =
      TextEditingController();
  final List<Map<String, dynamic>> _messages = [];

  StreamSubscription<List<BleDiscoveredDevice>>? _peersSubscription;
  StreamSubscription<String>? _messageSubscription;
  StreamSubscription<bool>? _connectionSubscription;

  List<BleDiscoveredDevice> _peers = [];
  List<SavedPeer> _savedPeers = [];
  bool _isConnected = false;
  bool _isLoading = false;
  String _role = 'none';
  String _statusText = 'Choose your role below';
  UserProfile? _myProfile;
  UserProfile? _peerProfile;
  bool _profileExists = false;

  bool _peerIsTyping = false;
  Timer? _typingTimer;
  Timer? _peerTypingTimer;

  int? _lastSentTimestamp;
  int? _lastLatencyMs;

  final List<int> _colorOptions = [
    0xFF1B4F8A, 0xFF4CAF50, 0xFFFF5722,
    0xFF9C27B0, 0xFFFF9800, 0xFF00BCD4,
  ];
  int _selectedColor = 0xFF1B4F8A;

  String _timestamp() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  String _formatLastSeen(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      final diff = DateTime.now().difference(date);
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return 'Recently';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadSavedPeers();

    _peersSubscription = _service.peersStream.listen((peers) {
      if (!mounted) return;
      setState(() => _peers = peers);
    });

    _messageSubscription =
        _service.messageStream.listen((message) {
      if (!mounted) return;

      if (message.startsWith('CHANNEL:') ||
          message.startsWith('BROADCAST:') ||
          message.startsWith('CHANNEL_JOIN:')) return;

      if (message.startsWith('PROFILE:')) {
        final profileJson = message.substring(8);
        final profile = UserProfile.fromJson(profileJson);
        setState(() {
          _peerProfile = profile;
          _statusText = 'Connected with ${profile.displayName}';
        });
        // Save peer to history
        widget.storage.savePeer(SavedPeer(
          displayName: profile.displayName,
          avatarColorValue: profile.avatarColorValue,
          lastSeen: DateTime.now().toIso8601String(),
        ));
        _loadSavedPeers();
      } else if (message == 'TYPING:') {
        setState(() => _peerIsTyping = true);
        _peerTypingTimer?.cancel();
        _peerTypingTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _peerIsTyping = false);
        });
      } else if (message == 'READ:') {
        if (_lastSentTimestamp != null) {
          final rtt = DateTime.now().millisecondsSinceEpoch -
              _lastSentTimestamp!;
          _lastSentTimestamp = null;
          if (mounted) setState(() => _lastLatencyMs = rtt);
        }
        setState(() {
          for (int i = _messages.length - 1; i >= 0; i--) {
            if (_messages[i]['isMine'] == true &&
                _messages[i]['read'] == false) {
              _messages[i]['read'] = true;
              break;
            }
          }
        });
      } else if (message.startsWith('📡')) {
        final content = message.substring(2).trim();
        setState(() => _messages.add({
              'content': content,
              'time': _timestamp(),
              'isMine': false,
              'read': true,
              'isRelay': true,
              'senderName': _peerProfile?.displayName ?? 'Relay',
              'senderColor':
                  _peerProfile?.avatarColorValue ?? 0xFF9C27B0,
            }));
      } else {
        setState(() => _peerIsTyping = false);
        setState(() => _messages.add({
              'content': message,
              'time': _timestamp(),
              'isMine': false,
              'read': true,
              'isRelay': false,
              'senderName': _peerProfile?.displayName ?? 'Peer',
              'senderColor':
                  _peerProfile?.avatarColorValue ?? 0xFF2196F3,
            }));
      }
    });

    _connectionSubscription =
        _service.connectionStream.listen((connected) {
      if (!mounted) return;
      setState(() {
        _isConnected = connected;
        if (connected) {
          _statusText = _service.isHost
              ? 'Waiting for peer...'
              : 'Connected';
          _shareProfile();
        } else {
          _statusText = 'Disconnected';
        }
      });
    });

    _checkBluetooth();
  }

  Future<void> _loadProfile() async {
    final profile = widget.storage.getProfile();
    if (profile != null && mounted) {
      setState(() {
        _myProfile = profile;
        _nameController.text = profile.displayName;
        _selectedColor = profile.avatarColorValue;
        _profileExists = true;
      });
    }
  }

  Future<void> _loadSavedPeers() async {
    final peers = widget.storage.getSavedPeers();
    if (mounted) setState(() => _savedPeers = peers);
  }

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final profile = UserProfile(
      displayName: name,
      avatarColorValue: _selectedColor,
    );
    await widget.storage.saveProfile(profile);
    if (mounted) {
      setState(() {
        _myProfile = profile;
        _profileExists = true;
      });
    }
  }

  Future<void> _shareProfile() async {
    if (_myProfile != null) {
      final delay = _service.isHost
          ? const Duration(seconds: 2)
          : const Duration(milliseconds: 800);
      await Future.delayed(delay);
      await _service
          .sendMessage('PROFILE:${_myProfile!.toJson()}');
    }
  }

  Future<void> _checkBluetooth() async {
    final btOn = await WifiDirectService.isBluetoothOn();
    if (!btOn && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('⚠️ Please turn Bluetooth ON before starting'),
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
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _role = 'host';
      _statusText = 'Setting up host...';
    });
    final error = await _service.startAsHost();
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _role = 'none';
        _statusText = 'Choose your role below';
      });
      _showError(error);
    } else {
      setState(
          () => _statusText = 'Waiting for client to connect...');
    }
    setState(() => _isLoading = false);
  }

  Future<void> _startAsClient() async {
    await _saveProfile();
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _role = 'client';
      _statusText = 'Scanning for host...';
    });
    final error = await _service.startAsClient();
    if (!mounted) return;
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
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _statusText = 'Connecting to ${device.deviceName}...';
    });
    final error = await _service.connectToPeer(device);
    if (!mounted) return;
    if (error != null) {
      _showError('Connection failed: $error');
      setState(() => _statusText = 'Scanning for host...');
    }
    setState(() => _isLoading = false);
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _lastSentTimestamp = DateTime.now().millisecondsSinceEpoch;
    await _service.sendMessage(text);
    if (!mounted) return;
    setState(() => _messages.add({
          'content': text,
          'time': _timestamp(),
          'isMine': true,
          'read': false,
          'isRelay': false,
          'senderName': _myProfile?.displayName ?? 'Me',
          'senderColor':
              _myProfile?.avatarColorValue ?? 0xFF1B4F8A,
        }));
    _messageController.clear();
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _peerTypingTimer?.cancel();
    _peersSubscription?.cancel();
    _messageSubscription?.cancel();
    _connectionSubscription?.cancel();
    _messageController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Widget _buildAvatar(String name, int colorValue,
      {double radius = 18}) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: Color(colorValue),
      child: Text(
        name[0].toUpperCase(),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.85,
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
            if (_myProfile != null)
              _buildAvatar(
                _myProfile!.displayName,
                _myProfile!.avatarColorValue,
                radius: 16,
              ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Direct Chat',
                    style: TextStyle(fontSize: 16)),
                if (_peerProfile != null)
                  Text(
                    _peerProfile!.displayName,
                    style: const TextStyle(
                        fontSize: 11, color: Colors.white70),
                  ),
              ],
            ),
            if (_lastLatencyMs != null) ...[
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_lastLatencyMs}ms RTT',
                  style: const TextStyle(
                      fontSize: 11, color: Colors.white),
                ),
              ),
            ],
          ],
        ),
        actions: [
          // Edit profile button
          if (_profileExists && _role == 'none')
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () {
                setState(() => _profileExists = false);
              },
              tooltip: 'Edit profile',
            ),
        ],
      ),
      body: Column(
        children: [
          // Status bar
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 8),
            color: _isConnected
                ? Colors.green[50]
                : _role == 'none'
                    ? Colors.orange[50]
                    : Colors.blue[50],
            child: Row(
              children: [
                if (_peerProfile != null)
                  _buildAvatar(
                    _peerProfile!.displayName,
                    _peerProfile!.avatarColorValue,
                    radius: 14,
                  ),
                if (_peerProfile != null)
                  const SizedBox(width: 8),
                if (_isLoading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2),
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
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),

          // Profile setup (shown only if no saved profile
          // or user clicked edit)
          if (_role == 'none' && !_profileExists)
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Your Profile',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _buildAvatar(
                          _nameController.text.isEmpty
                              ? '?'
                              : _nameController.text,
                          _selectedColor,
                          radius: 28,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: TextField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              hintText: 'Display name',
                              labelText: 'Your name',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('Avatar colour',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey)),
                    const SizedBox(height: 8),
                    Row(
                      children: _colorOptions.map((color) {
                        return GestureDetector(
                          onTap: () => setState(
                              () => _selectedColor = color),
                          child: AnimatedContainer(
                            duration:
                                const Duration(milliseconds: 200),
                            margin:
                                const EdgeInsets.only(right: 10),
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Color(color),
                              shape: BoxShape.circle,
                              border: _selectedColor == color
                                  ? Border.all(
                                      color: Colors.black87,
                                      width: 2.5)
                                  : null,
                              boxShadow: _selectedColor == color
                                  ? [
                                      BoxShadow(
                                        color: Color(color)
                                            .withValues(alpha: 0.4),
                                        blurRadius: 8,
                                      )
                                    ]
                                  : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () async {
                        await _saveProfile();
                      },
                      style: ElevatedButton.styleFrom(
                          minimumSize:
                              const Size(double.infinity, 48)),
                      child: const Text('Save Profile'),
                    ),
                  ],
                ),
              ),
            ),

          // Role selection + saved peers
          // (shown when profile exists and not yet in a role)
          if (_role == 'none' && _profileExists)
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Welcome back
                    Row(
                      children: [
                        _buildAvatar(
                          _myProfile!.displayName,
                          _myProfile!.avatarColorValue,
                          radius: 22,
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hey, ${_myProfile!.displayName}!',
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold),
                            ),
                            const Text(
                              'Ready to connect?',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Make sure Bluetooth and Wi-Fi are ON',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed:
                                _isLoading ? null : _startAsHost,
                            icon: const Icon(Icons.router,
                                size: 18),
                            label: const Text('Host'),
                            style: ElevatedButton.styleFrom(
                                padding:
                                    const EdgeInsets.all(14)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isLoading
                                ? null
                                : _startAsClient,
                            icon: const Icon(Icons.phone_android,
                                size: 18),
                            label: const Text('Client'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.all(14),
                              backgroundColor: Colors.white,
                              foregroundColor:
                                  const Color(0xFF1B4F8A),
                              side: const BorderSide(
                                  color: Color(0xFF1B4F8A)),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Recent peers
                    if (_savedPeers.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      const Text(
                        'Recent Peers',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      ..._savedPeers.map((peer) => Card(
                            margin: const EdgeInsets.only(
                                bottom: 8),
                            child: ListTile(
                              leading: _buildAvatar(
                                peer.displayName,
                                peer.avatarColorValue,
                                radius: 20,
                              ),
                              title: Text(peer.displayName,
                                  style: const TextStyle(
                                      fontWeight:
                                          FontWeight.w600)),
                              subtitle: Text(
                                'Last seen ${_formatLastSeen(peer.lastSeen)}',
                                style: const TextStyle(
                                    fontSize: 12),
                              ),
                              trailing: const Icon(
                                  Icons.wifi_tethering,
                                  color: Color(0xFF1B4F8A)),
                            ),
                          )),
                    ],
                  ],
                ),
              ),
            ),

          // Peer list for client
          if (_role == 'client' && !_isConnected)
            Expanded(
              child: _peers.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Scanning for host via BLE...',
                              style: TextStyle(
                                  color: Colors.grey)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _peers.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final peer = _peers[index];
                        // Check if this peer is in saved peers
                        final saved = _savedPeers
                            .where((s) =>
                                s.displayName == peer.deviceName)
                            .firstOrNull;
                        return Card(
                          child: ListTile(
                            leading: saved != null
                                ? _buildAvatar(
                                    saved.displayName,
                                    saved.avatarColorValue,
                                    radius: 20)
                                : CircleAvatar(
                                    backgroundColor:
                                        const Color(0xFF1B4F8A),
                                    child: Text(
                                      peer.deviceName[0]
                                          .toUpperCase(),
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight:
                                              FontWeight.bold),
                                    ),
                                  ),
                            title: Text(
                              saved?.displayName ??
                                  peer.deviceName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              saved != null
                                  ? 'Last seen ${_formatLastSeen(saved.lastSeen)}'
                                  : peer.deviceAddress,
                              style:
                                  const TextStyle(fontSize: 12),
                            ),
                            trailing: ElevatedButton(
                              onPressed: _isLoading
                                  ? null
                                  : () => _connectToPeer(peer),
                              child: const Text('Connect'),
                            ),
                          ),
                        );
                      },
                    ),
            ),

          // Messages
          if (_role != 'none')
            Expanded(
              child: _messages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_outline,
                              size: 48,
                              color: Colors.grey[300]),
                          const SizedBox(height: 12),
                          Text(
                            _isConnected
                                ? 'Say hello! 👋'
                                : 'Waiting for connection...',
                            style: TextStyle(
                                color: Colors.grey[500]),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(
                          12, 12, 12, 4),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        final isMine = msg['isMine'] as bool;
                        final content = msg['content'] as String;
                        final time = msg['time'] as String;
                        final read = msg['read'] as bool;
                        final isRelay = msg['isRelay'] as bool;
                        final senderName =
                            msg['senderName'] as String;
                        final senderColor =
                            msg['senderColor'] as int;

                        return Padding(
                          padding:
                              const EdgeInsets.only(bottom: 8),
                          child: Row(
                            mainAxisAlignment: isMine
                                ? MainAxisAlignment.end
                                : MainAxisAlignment.start,
                            crossAxisAlignment:
                                CrossAxisAlignment.end,
                            children: [
                              if (!isMine) ...[
                                _buildAvatar(
                                    senderName, senderColor,
                                    radius: 14),
                                const SizedBox(width: 6),
                              ],
                              Flexible(
                                child: Column(
                                  crossAxisAlignment: isMine
                                      ? CrossAxisAlignment.end
                                      : CrossAxisAlignment.start,
                                  children: [
                                    if (!isMine)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(
                                                left: 4,
                                                bottom: 2),
                                        child: Text(
                                          senderName,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight:
                                                FontWeight.bold,
                                            color: Color(
                                                senderColor),
                                          ),
                                        ),
                                      ),
                                    Container(
                                      padding: const EdgeInsets
                                          .symmetric(
                                          horizontal: 14,
                                          vertical: 10),
                                      decoration: BoxDecoration(
                                        color: isRelay
                                            ? Colors.purple[50]
                                            : isMine
                                                ? const Color(
                                                    0xFF1B4F8A)
                                                : Colors
                                                    .grey[100],
                                        borderRadius:
                                            BorderRadius.only(
                                          topLeft: const Radius
                                              .circular(16),
                                          topRight: const Radius
                                              .circular(16),
                                          bottomLeft:
                                              Radius.circular(
                                                  isMine
                                                      ? 16
                                                      : 4),
                                          bottomRight:
                                              Radius.circular(
                                                  isMine
                                                      ? 4
                                                      : 16),
                                        ),
                                        border: isRelay
                                            ? Border.all(
                                                color: Colors
                                                    .purple[200]!,
                                                width: 1)
                                            : null,
                                      ),
                                      child: Column(
                                        crossAxisAlignment: isMine
                                            ? CrossAxisAlignment
                                                .end
                                            : CrossAxisAlignment
                                                .start,
                                        children: [
                                          if (isRelay)
                                            const Text(
                                              '📡 Relayed',
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors
                                                      .purple),
                                            ),
                                          Text(
                                            content,
                                            style: TextStyle(
                                              color: isRelay
                                                  ? Colors.black87
                                                  : isMine
                                                      ? Colors
                                                          .white
                                                      : Colors
                                                          .black87,
                                              fontSize: 15,
                                            ),
                                          ),
                                          const SizedBox(
                                              height: 3),
                                          Row(
                                            mainAxisSize:
                                                MainAxisSize.min,
                                            children: [
                                              Text(
                                                time,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: isMine &&
                                                          !isRelay
                                                      ? Colors
                                                          .white60
                                                      : Colors
                                                          .black38,
                                                ),
                                              ),
                                              if (isMine) ...[
                                                const SizedBox(
                                                    width: 4),
                                                Icon(
                                                  read
                                                      ? Icons
                                                          .done_all
                                                      : Icons.done,
                                                  size: 13,
                                                  color: read
                                                      ? Colors
                                                          .lightBlueAccent
                                                      : Colors
                                                          .white60,
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isMine) ...[
                                const SizedBox(width: 6),
                                _buildAvatar(
                                  _myProfile?.displayName ?? 'Me',
                                  _myProfile?.avatarColorValue ??
                                      0xFF1B4F8A,
                                  radius: 14,
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),

          // Message input
          if (_isConnected)
            Container(
              padding:
                  const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: const InputDecoration(
                        hintText: 'Message...',
                        filled: true,
                        fillColor: Color(0xFFF5F5F5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(
                              Radius.circular(24)),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
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
                    icon: const Icon(Icons.send_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF1B4F8A),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}