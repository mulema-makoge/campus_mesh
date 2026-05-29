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

  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];

  StreamSubscription<List<BleDiscoveredDevice>>? _peersSubscription;
  StreamSubscription<String>? _messageSubscription;
  StreamSubscription<bool>? _connectionSubscription;
  StreamSubscription<int>? _latencySubscription;
  StreamSubscription<String>? _requestSubscription;
  StreamSubscription<void>? _rejectedSubscription;

  List<BleDiscoveredDevice> _nearbyPeers = [];
  List<SavedPeer> _savedPeers = [];
  bool _isConnected = false;
  bool _isLoading = false;
  bool _isScanning = false;
  bool _isHosting = false;
  bool _requestSent = false;
  bool _connectionHandledOnce = false;

  String _statusText = 'Looking for nearby peers...';
  UserProfile? _myProfile;
  UserProfile? _peerProfile;
  bool _profileExists = false;

  bool _peerIsTyping = false;
  Timer? _typingTimer;
  Timer? _peerTypingTimer;
  Timer? _proximityRetryTimer;

  int? _lastLatencyMs;

  final List<int> _colorOptions = [
    0xFF1B4F8A, 0xFF4CAF50, 0xFFFF5722,
    0xFF9C27B0, 0xFFFF9800, 0xFF00BCD4,
  ];
  int _selectedColor = 0xFF1B4F8A;
  final TextEditingController _nameController = TextEditingController();

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

  SavedPeer? _matchSavedPeer(String deviceName) {
    return _savedPeers
        .where((p) =>
            deviceName.toLowerCase().contains(p.displayName.toLowerCase()) ||
            p.displayName.toLowerCase().contains(deviceName.toLowerCase()))
        .firstOrNull;
  }

  void _saveHistory() {
    if (_peerProfile != null) {
      widget.storage.saveMessages(_peerProfile!.displayName, _messages);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadSavedPeers();

    _peersSubscription = _service.peersStream.listen((peers) {
      if (!mounted) return;
      setState(() => _nearbyPeers = peers);
    });

    _latencySubscription = _service.latencyStream.listen((latency) {
      if (!mounted) return;
      setState(() => _lastLatencyMs = latency);
    });

    _requestSubscription =
        _service.connectionRequestStream.listen((requesterName) {
      if (!mounted) return;
      _showConnectionRequestDialog(requesterName);
    });

    _rejectedSubscription =
        _service.connectionRejectedStream.listen((_) {
      if (!mounted) return;
      _showError('Connection request was declined');
      _resetToProximityMode();
    });

    _messageSubscription = _service.messageStream.listen((message) {
      if (!mounted) return;

      if (message.startsWith('CHANNEL:') ||
          message.startsWith('BROADCAST:') ||
          message.startsWith('CHANNEL_JOIN:') ||
          message.startsWith('📡MESH:')) {
        return;
      }

      if (message == 'PEER_DISCONNECTED:') {
        setState(() {
          _isConnected = false;
          _statusText = 'Peer disconnected';
        });
        _showDisconnectedBanner();
        _resetToProximityMode();
        return;
      }

      if (message.startsWith('PROFILE:')) {
        final profile = UserProfile.fromJson(message.substring(8));
        setState(() {
          _peerProfile = profile;
          _statusText = 'Connected with ${profile.displayName}';
          for (int i = 0; i < _messages.length; i++) {
            final name = _messages[i]['senderName'];
            if (name == 'Unknown' || name == 'Peer') {
              _messages[i]['senderName'] = profile.displayName;
              _messages[i]['senderColor'] = profile.avatarColorValue;
            }
          }
        });
        // Both sides save each other — symmetric
        widget.storage.savePeer(SavedPeer(
          displayName: profile.displayName,
          avatarColorValue: profile.avatarColorValue,
          lastSeen: DateTime.now().toIso8601String(),
        ));
        _loadSavedPeers();
        final history = widget.storage.getMessages(profile.displayName);
        if (history.isNotEmpty && mounted && _messages.isEmpty) {
          setState(() => _messages.addAll(history));
        }
      } else if (message == 'TYPING:') {
        setState(() => _peerIsTyping = true);
        _peerTypingTimer?.cancel();
        _peerTypingTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _peerIsTyping = false);
        });
      } else if (message == 'READ:') {
        setState(() {
          for (int i = _messages.length - 1; i >= 0; i--) {
            if (_messages[i]['isMine'] == true &&
                _messages[i]['read'] == false) {
              _messages[i]['read'] = true;
              break;
            }
          }
        });
        _saveHistory();
      } else {
        setState(() => _peerIsTyping = false);
        final newMsg = {
          'content': message,
          'time': _timestamp(),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'isMine': false,
          'read': true,
          'senderName': _peerProfile?.displayName ??
              _savedPeers.firstOrNull?.displayName ?? 'Unknown',
          'senderColor': _peerProfile?.avatarColorValue ?? 0xFF2196F3,
        };
        setState(() => _messages.add(newMsg));
        _saveHistory();
      }
    });

    _connectionSubscription =
        _service.connectionStream.listen((connected) {
      if (!mounted) return;
      setState(() {
        _isConnected = connected;
        if (connected) {
          if (!_connectionHandledOnce) {
            _connectionHandledOnce = true;
            if (_peerProfile == null) {
              _statusText = _service.isHost
                  ? 'Peer connected — waiting for request...'
                  : 'Connected — sending request...';
            }
          }
          _shareProfile();
        } else {
          _connectionHandledOnce = false;
          _requestSent = false;
        }
      });
    });
  }

  Future<void> _startProximityMode() async {
    if (_isHosting || _isScanning) return;
    await _loadProfile();
    if (!_profileExists) return;

    setState(() {
      _isLoading = true;
      _statusText = 'Scanning for nearby peers...';
    });

    final scanError = await _service.startAsClient();
    if (scanError != null) {
      _startHosting();
      return;
    }

    setState(() {
      _isScanning = true;
      _isLoading = false;
    });

    _proximityRetryTimer =
        Timer(const Duration(seconds: 6), () async {
      if (mounted && !_isConnected && _isScanning) {
        await _service.stopScan();
        await _service.disconnect();
        _startHosting();
      }
    });
  }

  Future<void> _startHosting() async {
    if (_isHosting) return;
    final hostError = await _service.startAsHost();
    if (!mounted) return;
    if (hostError != null) {
      setState(() {
        _statusText = 'Could not start — check permissions';
        _isLoading = false;
      });
    } else {
      setState(() {
        _isHosting = true;
        _isScanning = false;
        _isLoading = false;
        _statusText = 'Discoverable to nearby peers';
      });
    }
  }

  // ── Stop scanning / reset to idle ────────────────────────────
  Future<void> _stopProximityMode() async {
    _proximityRetryTimer?.cancel();
    await _service.stopScan();
    await _service.disconnect();
    if (!mounted) return;
    setState(() {
      _isScanning = false;
      _isHosting = false;
      _isLoading = false;
      _nearbyPeers = [];
      _statusText = 'Tap Scan to find nearby peers';
    });
  }

  Future<void> _connectToPeer(BleDiscoveredDevice device) async {
    if (!mounted) return;

    if (_isHosting) {
      setState(() {
        _isLoading = true;
        _statusText = 'Switching to connect mode...';
      });
      _proximityRetryTimer?.cancel();
      await _service.stopScan();
      await _service.disconnect();
      setState(() => _isHosting = false);

      final scanError = await _service.startAsClient();
      if (scanError != null) {
        _showError('Failed to switch mode');
        _startHosting();
        return;
      }
      setState(() => _isScanning = true);
      await Future.delayed(const Duration(seconds: 2));
    }

    final saved = _matchSavedPeer(device.deviceName);
    setState(() {
      _isLoading = true;
      _statusText = saved != null
          ? 'Connecting to ${saved.displayName}...'
          : 'Connecting...';
    });

    final error = await _service.connectToPeer(device);
    if (!mounted) return;

    if (error != null) {
      _showError('Connection failed: $error');
      setState(() => _statusText = 'Looking for nearby peers...');
      _resetToProximityMode();
    } else {
      if (!_requestSent) {
        _requestSent = true;
        setState(() => _statusText = 'Requesting connection...');
        await _service
            .sendConnectionRequest(_myProfile?.displayName ?? 'Unknown');
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _resetToProximityMode() async {
    _proximityRetryTimer?.cancel();
    _isScanning = false;
    _isHosting = false;
    _requestSent = false;
    _connectionHandledOnce = false;
    setState(() {
      _isConnected = false;
      _peerProfile = null;
      _nearbyPeers = [];
      _isLoading = false;
      _statusText = 'Looking for nearby peers...';
    });
    await _service.stopScan();
    await _service.disconnect();
    _startProximityMode();
  }

  void _showConnectionRequestDialog(String requesterName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Connection Request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: const Color(0xFF1B4F8A),
              child: Text(requesterName[0].toUpperCase(),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 12),
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: const TextStyle(color: Colors.black, fontSize: 15),
                children: [
                  TextSpan(
                    text: requesterName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const TextSpan(
                      text: ' wants to start a proximity chat.'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _service.rejectConnectionRequest();
            },
            child: const Text('Decline',
                style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _service.acceptConnectionRequest();
              if (mounted) {
                setState(() =>
                    _statusText = 'Establishing secure channel...');
              }
            },
            child: const Text('Accept'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndDisconnect() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End Chat?'),
        content: Text(
            'Disconnect from ${_peerProfile?.displayName ?? "peer"}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white),
            child: const Text('End Chat'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      if (_isConnected) {
        await _service.sendDisconnectNotification();
        await Future.delayed(const Duration(milliseconds: 300));
      }
      await _resetToProximityMode();
    }
  }

  void _showDisconnectedBanner() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Peer ended the chat'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 4),
      ),
    );
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
    final profile =
        UserProfile(displayName: name, avatarColorValue: _selectedColor);
    await widget.storage.saveProfile(profile);
    if (mounted) {
      setState(() {
        _myProfile = profile;
        _profileExists = true;
      });
      _startProximityMode();
    }
  }

  Future<void> _shareProfile() async {
    if (_myProfile == null) return;
    int retries = 0;
    while (!_service.cryptoReady && retries < 16) {
      await Future.delayed(const Duration(milliseconds: 500));
      retries++;
      if (!mounted) return;
    }
    if (!_service.cryptoReady || !mounted) return;
    await _service.sendMessage('PROFILE:${_myProfile!.toJson()}');
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

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    await _service.sendMessage(text);
    if (!mounted) return;
    final newMsg = {
      'content': text,
      'time': _timestamp(),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'isMine': true,
      'read': false,
      'senderName': _myProfile?.displayName ?? 'Me',
      'senderColor': _myProfile?.avatarColorValue ?? 0xFF1B4F8A,
    };
    setState(() => _messages.add(newMsg));
    _messageController.clear();
    _saveHistory();
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _peerTypingTimer?.cancel();
    _proximityRetryTimer?.cancel();
    _peersSubscription?.cancel();
    _messageSubscription?.cancel();
    _connectionSubscription?.cancel();
    _latencySubscription?.cancel();
    _requestSubscription?.cancel();
    _rejectedSubscription?.cancel();
    _messageController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Widget _buildAvatar(String name, int colorValue, {double radius = 18}) {
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
    final inChat =
        _isConnected && _service.cryptoReady && _peerProfile != null;
    final isIdle = !_isScanning && !_isHosting && !_isLoading && !inChat;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            if (_myProfile != null)
              _buildAvatar(_myProfile!.displayName,
                  _myProfile!.avatarColorValue, radius: 16),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(inChat ? _peerProfile!.displayName : 'Proximity Chat',
                    style: const TextStyle(fontSize: 16)),
                Text(
                  inChat ? 'In chat' : _statusText,
                  style: const TextStyle(
                      fontSize: 11, color: Colors.white70),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            if (_lastLatencyMs != null && inChat) ...[
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('${_lastLatencyMs}ms',
                    style: const TextStyle(
                        fontSize: 11, color: Colors.white)),
              ),
            ],
          ],
        ),
        actions: [
          if (inChat)
            IconButton(
              icon: const Icon(Icons.call_end),
              onPressed: _confirmAndDisconnect,
              tooltip: 'End chat',
            )
          else if (_isScanning || _isHosting)
            // ── Stop scan button ──────────────────────────────
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined),
              onPressed: _isLoading ? null : _stopProximityMode,
              tooltip: 'Stop scanning',
            ),
          if (_profileExists && !inChat && !_isScanning && !_isHosting)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => setState(() => _profileExists = false),
              tooltip: 'Edit profile',
            ),
        ],
      ),
      body: Column(
        children: [
          // Status bar
          if (!inChat)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: _isHosting
                  ? Colors.green[50]
                  : _isScanning
                      ? Colors.blue[50]
                      : Colors.orange[50],
              child: Row(
                children: [
                  if (_isLoading)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child:
                          CircularProgressIndicator(strokeWidth: 2),
                    ),
                  if (_isLoading) const SizedBox(width: 8),
                  Icon(
                    _isHosting
                        ? Icons.wifi_tethering
                        : _isScanning
                            ? Icons.radar
                            : Icons.wifi_off,
                    size: 16,
                    color: _isHosting
                        ? Colors.green
                        : _isScanning
                            ? Colors.blue
                            : Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isHosting
                          ? '🟢 $_statusText'
                          : _isScanning
                              ? '🔍 $_statusText'
                              : '🟡 $_statusText',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),

          // Profile setup
          if (!_profileExists)
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Set Up Your Profile',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    const Text(
                        'Your name and avatar will be visible to nearby peers.',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey)),
                    const SizedBox(height: 24),
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
                              hintText: 'Your display name',
                              labelText: 'Name',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('Pick a colour',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey)),
                    const SizedBox(height: 8),
                    Row(
                      children: _colorOptions.map((color) {
                        return GestureDetector(
                          onTap: () =>
                              setState(() => _selectedColor = color),
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
                                          blurRadius: 8)
                                    ]
                                  : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 28),
                    ElevatedButton(
                      onPressed: _saveProfile,
                      style: ElevatedButton.styleFrom(
                          minimumSize:
                              const Size(double.infinity, 52)),
                      child: const Text('Start Using CampusMesh',
                          style: TextStyle(fontSize: 16)),
                    ),
                  ],
                ),
              ),
            ),

          // Idle state — scan button
          if (_profileExists && isIdle)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.sensors_off,
                        size: 64, color: Colors.grey[300]),
                    const SizedBox(height: 16),
                    const Text('Not scanning',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey)),
                    const SizedBox(height: 8),
                    const Text(
                        'Tap Scan to find nearby peers',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey)),
                    const SizedBox(height: 28),
                    ElevatedButton.icon(
                      onPressed: _startProximityMode,
                      icon: const Icon(Icons.radar),
                      label: const Text('Scan for Peers'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(14)),
                      ),
                    ),
                    if (_savedPeers.isNotEmpty) ...[
                      const SizedBox(height: 32),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            const Text('Recent Peers',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight:
                                        FontWeight.bold,
                                    color: Colors.grey)),
                            const SizedBox(height: 8),
                            ..._savedPeers.take(3).map(
                                (peer) => Card(
                                      margin:
                                          const EdgeInsets.only(
                                              bottom: 8),
                                      child: ListTile(
                                        leading: _buildAvatar(
                                            peer.displayName,
                                            peer.avatarColorValue,
                                            radius: 18),
                                        title: Text(
                                            peer.displayName,
                                            style: const TextStyle(
                                                fontWeight:
                                                    FontWeight.w600,
                                                fontSize: 14)),
                                        subtitle: Text(
                                            'Last seen ${_formatLastSeen(peer.lastSeen)}',
                                            style:
                                                const TextStyle(
                                                    fontSize: 11)),
                                        trailing: ElevatedButton(
                                          onPressed:
                                              _startProximityMode,
                                          style: ElevatedButton
                                              .styleFrom(
                                            padding:
                                                const EdgeInsets
                                                    .symmetric(
                                                    horizontal:
                                                        10,
                                                    vertical: 4),
                                            textStyle:
                                                const TextStyle(
                                                    fontSize: 11),
                                          ),
                                          child: const Text(
                                              'Reconnect'),
                                        ),
                                      ),
                                    )),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

          // Nearby peers list
          if (_profileExists &&
              !inChat &&
              !_requestSent &&
              (_isScanning || _isHosting))
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      children: [
                        const Text('Nearby Peers',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold)),
                        const Spacer(),
                        if (_isScanning || _isHosting)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF1B4F8A)),
                          ),
                      ],
                    ),
                  ),
                  if (_nearbyPeers.isEmpty)
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisAlignment:
                              MainAxisAlignment.center,
                          children: [
                            Icon(Icons.sensors,
                                size: 64,
                                color: Colors.grey[300]),
                            const SizedBox(height: 16),
                            Text(
                              _isHosting
                                  ? 'Waiting for peers...'
                                  : 'Scanning...',
                              style: TextStyle(
                                  color: Colors.grey[500]),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _isHosting
                                  ? 'Your device is discoverable'
                                  : 'Make sure peers have the app open',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        itemCount: _nearbyPeers.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final device = _nearbyPeers[index];
                          final saved =
                              _matchSavedPeer(device.deviceName);
                          final displayName =
                              saved?.displayName ?? device.deviceName;
                          final color =
                              saved?.avatarColorValue ?? 0xFF566573;

                          return Card(
                            child: ListTile(
                              leading: _buildAvatar(
                                  displayName, color, radius: 22),
                              title: Text(displayName,
                                  style: const TextStyle(
                                      fontWeight:
                                          FontWeight.w600)),
                              subtitle: Text(
                                saved != null
                                    ? 'Last seen ${_formatLastSeen(saved.lastSeen)}'
                                    : 'Tap to connect',
                                style: const TextStyle(
                                    fontSize: 12),
                              ),
                              trailing: ElevatedButton(
                                onPressed: _isLoading
                                    ? null
                                    : () =>
                                        _connectToPeer(device),
                                style: ElevatedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 6),
                                  textStyle: const TextStyle(
                                      fontSize: 13),
                                ),
                                child: const Text('Connect'),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),

          // Waiting for request response
          if (_profileExists && !inChat && _requestSent)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 52,
                      height: 52,
                      child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Color(0xFF1B4F8A)),
                    ),
                    const SizedBox(height: 20),
                    const Text('Request sent',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text('Waiting for them to accept...',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey)),
                    const SizedBox(height: 24),
                    TextButton(
                      onPressed: _resetToProximityMode,
                      child: const Text('Cancel',
                          style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              ),
            ),

          // Chat
          if (inChat)
            Expanded(
              child: _messages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
                        children: [
                          _buildAvatar(
                            _peerProfile!.displayName,
                            _peerProfile!.avatarColorValue,
                            radius: 36,
                          ),
                          const SizedBox(height: 16),
                          Text(
                              'Chat with ${_peerProfile!.displayName}',
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Text(
                            'E2E encrypted · ${_lastLatencyMs != null ? '${_lastLatencyMs}ms RTT' : 'Direct'}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          const Text('Say hello! 👋',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey)),
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
                                        child: Text(senderName,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight:
                                                  FontWeight.bold,
                                              color: Color(
                                                  senderColor),
                                            )),
                                      ),
                                    Container(
                                      padding:
                                          const EdgeInsets
                                              .symmetric(
                                              horizontal: 14,
                                              vertical: 10),
                                      decoration: BoxDecoration(
                                        color: isMine
                                            ? const Color(
                                                0xFF1B4F8A)
                                            : Colors.grey[100],
                                        borderRadius:
                                            BorderRadius.only(
                                          topLeft: const Radius
                                              .circular(16),
                                          topRight: const Radius
                                              .circular(16),
                                          bottomLeft:
                                              Radius.circular(
                                                  isMine ? 16 : 4),
                                          bottomRight:
                                              Radius.circular(
                                                  isMine ? 4 : 16),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: isMine
                                            ? CrossAxisAlignment.end
                                            : CrossAxisAlignment
                                                .start,
                                        children: [
                                          Text(content,
                                              style: TextStyle(
                                                color: isMine
                                                    ? Colors.white
                                                    : Colors.black87,
                                                fontSize: 15,
                                              )),
                                          const SizedBox(height: 3),
                                          Row(
                                            mainAxisSize:
                                                MainAxisSize.min,
                                            children: [
                                              Text(time,
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: isMine
                                                        ? Colors
                                                            .white60
                                                        : Colors
                                                            .black38,
                                                  )),
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
          if (inChat)
            Container(
              padding:
                  const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color:
                        Colors.black.withValues(alpha: 0.05),
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