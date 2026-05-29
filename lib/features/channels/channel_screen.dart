import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/message.dart';
import '../../models/peer.dart';
import '../../services/storage_service.dart';
import '../../services/wifi_direct_service.dart';

class ChannelScreen extends StatefulWidget {
  final StorageService storage;
  final WifiDirectService? service;

  const ChannelScreen({
    super.key,
    required this.storage,
    this.service,
  });

  @override
  State<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends State<ChannelScreen> {
  final Map<String, List<RelayMessageItem>> _conversations = {};
  List<SavedPeer> _savedPeers = [];
  String? _selectedPeer;
  UserProfile? _myProfile;

  StreamSubscription<String>? _messageSubscription;
  StreamSubscription<String>? _deliverySubscription;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadSavedPeers();
    _listenForMessages();
    _listenForDelivery();
  }

  Future<void> _loadProfile() async {
    final profile = widget.storage.getProfile();
    if (profile != null && mounted) {
      setState(() => _myProfile = profile);
    }
  }

  Future<void> _loadSavedPeers() async {
    final peers = widget.storage.getSavedPeers();
    if (mounted) setState(() => _savedPeers = peers);
  }

  void _listenForMessages() {
    _messageSubscription =
        widget.service?.messageStream.listen((message) {
      if (!mounted) return;

      // Handle incoming mesh relay messages
      if (message.startsWith('📡MESH:')) {
        // Format: 📡MESH:<meshId>:<senderName>|<senderColor>|<content>
        final withoutPrefix = message.substring(7); // remove '📡MESH:'
        final colonIdx = withoutPrefix.indexOf(':');
        if (colonIdx == -1) return;
        final meshId = withoutPrefix.substring(0, colonIdx);
        final rest = withoutPrefix.substring(colonIdx + 1);

        final parts = rest.split('|');
        if (parts.length >= 3) {
          final senderName = parts[0];
          final content = parts.sublist(2).join('|');
          final now = DateTime.now();
          final time =
              '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

          setState(() {
            _conversations.putIfAbsent(senderName, () => []);
            _conversations[senderName]!.add(RelayMessageItem(
              id: meshId,
              content: content,
              time: time,
              timestamp: now.millisecondsSinceEpoch,
              isMine: false,
              status: MeshDeliveryStatus.delivered,
            ));
          });

          // Show notification if not viewing this conversation
          if (_selectedPeer != senderName) {
            _showIncomingNotification(senderName, content, meshId);
          } else {
            // Auto-send read receipt if viewing
            widget.service?.sendMeshReadAck(meshId);
          }
        }
      }
    });
  }

  void _listenForDelivery() {
    _deliverySubscription =
        widget.service?.meshDeliveryStream.listen((event) {
      if (!mounted) return;
      // Format: MESH_ACK:<id>, MESH_READ:<id>, MESH_REJECT:<id>
      final parts = event.split(':');
      if (parts.length < 2) return;
      final type = parts[0];
      final meshId = parts[1];

      MeshDeliveryStatus status;
      if (type == 'MESH_ACK') {
        status = MeshDeliveryStatus.delivered;
      } else if (type == 'MESH_READ') {
        status = MeshDeliveryStatus.read;
      } else if (type == 'MESH_REJECT') {
        status = MeshDeliveryStatus.rejected;
      } else {
        return;
      }

      setState(() {
        for (final msgs in _conversations.values) {
          for (int i = 0; i < msgs.length; i++) {
            if (msgs[i].id == meshId && msgs[i].isMine) {
              msgs[i].status = status;
              break;
            }
          }
        }
      });
    });
  }

  void _showIncomingNotification(
      String senderName, String content, String meshId) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.alt_route, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(senderName,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
                  Text(content,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF7D3C98),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'View',
          textColor: Colors.white,
          onPressed: () {
            setState(() => _selectedPeer = senderName);
            widget.service?.sendMeshReadAck(meshId);
          },
        ),
      ),
    );
  }

  Future<void> _sendRelayMessage(String peerName, String content) async {
    if (content.trim().isEmpty || _myProfile == null) return;
    if (widget.service?.cryptoReady != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connect via Proximity Chat first to relay messages'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final now = DateTime.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    // Format: senderName|senderColor|content
    final payload =
        '${_myProfile!.displayName}|${_myProfile!.avatarColorValue}|$content';

    final meshId = await widget.service
        ?.sendMeshMessage(payload, recipientDisplayName: peerName);

    if (meshId != null) {
      setState(() {
        _conversations.putIfAbsent(peerName, () => []);
        _conversations[peerName]!.add(RelayMessageItem(
          id: meshId,
          content: content,
          time: time,
          timestamp: now.millisecondsSinceEpoch,
          isMine: true,
          status: MeshDeliveryStatus.sent,
        ));
      });
    }
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _deliverySubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = widget.service?.cryptoReady == true;

    if (_selectedPeer != null) {
      return _buildConversationView(_selectedPeer!, isConnected);
    }

    return _buildPeerListView(isConnected);
  }

  Widget _buildPeerListView(bool isConnected) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mesh Relay'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Icon(
                isConnected ? Icons.alt_route : Icons.alt_route_outlined,
                color: isConnected ? Colors.white : Colors.white54,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Status
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: isConnected ? Colors.green[50] : Colors.orange[50],
            child: Text(
              isConnected
                  ? '🟢 Relay active — messages hop through nearby devices'
                  : '🟡 Connect via Proximity Chat to activate mesh relay',
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),

          if (_savedPeers.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.people_outline,
                        size: 64, color: Colors.grey[300]),
                    const SizedBox(height: 16),
                    const Text('No peers yet',
                        style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text(
                      'Chat with someone via Proximity Chat first.\nThey\'ll appear here for mesh relay.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _savedPeers.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final peer = _savedPeers[index];
                  final msgs = _conversations[peer.displayName] ?? [];
                  final unread = msgs
                      .where((m) =>
                          !m.isMine &&
                          m.status != MeshDeliveryStatus.read)
                      .length;
                  final lastMsg = msgs.isNotEmpty ? msgs.last : null;

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 0, vertical: 4),
                    leading: Stack(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: Color(peer.avatarColorValue),
                          child: Text(
                            peer.displayName[0].toUpperCase(),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (unread > 0)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: const BoxDecoration(
                                color: Color(0xFF1B4F8A),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text('$unread',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ),
                      ],
                    ),
                    title: Text(peer.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      lastMsg != null
                          ? '${lastMsg.isMine ? 'You: ' : ''}${lastMsg.content}'
                          : 'Tap to send a relay message',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          color: unread > 0
                              ? const Color(0xFF1B4F8A)
                              : Colors.grey),
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.alt_route,
                            size: 16, color: Color(0xFF7D3C98)),
                        if (lastMsg != null) ...[
                          const SizedBox(height: 2),
                          Text(lastMsg.time,
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.grey)),
                        ],
                      ],
                    ),
                    onTap: () {
                      setState(() => _selectedPeer = peer.displayName);
                      // Mark incoming as read
                      final msgs =
                          _conversations[peer.displayName] ?? [];
                      for (final m in msgs) {
                        if (!m.isMine &&
                            m.status != MeshDeliveryStatus.read) {
                          widget.service?.sendMeshReadAck(m.id);
                          m.status = MeshDeliveryStatus.read;
                        }
                      }
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildConversationView(String peerName, bool isConnected) {
    final msgs = _conversations[peerName] ?? [];
    final peer =
        _savedPeers.where((p) => p.displayName == peerName).firstOrNull;
    final controller = TextEditingController();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() => _selectedPeer = null),
        ),
        title: Row(
          children: [
            if (peer != null)
              CircleAvatar(
                radius: 16,
                backgroundColor: Color(peer.avatarColorValue),
                child: Text(peer.displayName[0].toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
              ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(peerName, style: const TextStyle(fontSize: 15)),
                const Text('Mesh Relay',
                    style: TextStyle(
                        fontSize: 11, color: Colors.white70)),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Relay info bar
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: Colors.purple[50],
            child: Row(
              children: [
                const Icon(Icons.alt_route,
                    size: 14, color: Color(0xFF7D3C98)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isConnected
                        ? 'Messages relay through nearby devices with TTL=3'
                        : 'Connect via Proximity Chat to send relay messages',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF7D3C98)),
                  ),
                ),
              ],
            ),
          ),

          // Messages
          Expanded(
            child: msgs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.alt_route,
                            size: 48, color: Colors.grey[300]),
                        const SizedBox(height: 12),
                        Text('Send a relay message to $peerName',
                            style:
                                TextStyle(color: Colors.grey[500])),
                        const SizedBox(height: 6),
                        const Text(
                          'It will hop through nearby devices\nto reach them even if out of range',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: msgs.length,
                    itemBuilder: (context, index) {
                      final msg = msgs[index];
                      final isMine = msg.isMine;

                      IconData statusIcon;
                      Color statusColor;
                      String statusLabel;
                      switch (msg.status) {
                        case MeshDeliveryStatus.pending:
                          statusIcon = Icons.schedule;
                          statusColor = Colors.grey;
                          statusLabel = 'Sending...';
                          break;
                        case MeshDeliveryStatus.sent:
                          statusIcon = Icons.done;
                          statusColor = Colors.white60;
                          statusLabel = 'Sent into mesh';
                          break;
                        case MeshDeliveryStatus.delivered:
                          statusIcon = Icons.done_all;
                          statusColor = Colors.white70;
                          statusLabel = 'Delivered';
                          break;
                        case MeshDeliveryStatus.read:
                          statusIcon = Icons.done_all;
                          statusColor = Colors.lightBlueAccent;
                          statusLabel = 'Read';
                          break;
                        case MeshDeliveryStatus.rejected:
                          statusIcon = Icons.close;
                          statusColor = Colors.redAccent;
                          statusLabel = 'Rejected';
                          break;
                      }

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Align(
                          alignment: isMine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Column(
                            crossAxisAlignment: isMine
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              Container(
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context).size.width *
                                          0.72,
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: msg.status ==
                                          MeshDeliveryStatus.rejected
                                      ? Colors.red[50]
                                      : isMine
                                          ? const Color(0xFF7D3C98)
                                          : Colors.grey[100],
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(16),
                                    topRight: const Radius.circular(16),
                                    bottomLeft:
                                        Radius.circular(isMine ? 16 : 4),
                                    bottomRight:
                                        Radius.circular(isMine ? 4 : 16),
                                  ),
                                  border: msg.status ==
                                          MeshDeliveryStatus.rejected
                                      ? Border.all(
                                          color: Colors.red[300]!,
                                          width: 1)
                                      : null,
                                ),
                                child: Column(
                                  crossAxisAlignment: isMine
                                      ? CrossAxisAlignment.end
                                      : CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.alt_route,
                                            size: 11,
                                            color: Colors.white54),
                                        SizedBox(width: 3),
                                        Text('Mesh Relay',
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.white54)),
                                      ],
                                    ),
                                    Text(
                                      msg.content,
                                      style: TextStyle(
                                        color: msg.status ==
                                                MeshDeliveryStatus.rejected
                                            ? Colors.red[700]
                                            : isMine
                                                ? Colors.white
                                                : Colors.black87,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(msg.time,
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: isMine
                                                  ? Colors.white60
                                                  : Colors.black38,
                                            )),
                                        if (isMine) ...[
                                          const SizedBox(width: 4),
                                          Icon(statusIcon,
                                              size: 12,
                                              color: statusColor),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              if (isMine)
                                Padding(
                                  padding:
                                      const EdgeInsets.only(top: 2, right: 2),
                                  child: Text(statusLabel,
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: msg.status ==
                                                  MeshDeliveryStatus.rejected
                                              ? Colors.red
                                              : Colors.grey)),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Input — only show when connected
          if (isConnected)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
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
                  const Icon(Icons.alt_route,
                      color: Color(0xFF7D3C98), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      decoration: InputDecoration(
                        hintText: 'Relay message to $peerName...',
                        filled: true,
                        fillColor: const Color(0xFFF5F5F5),
                        border: const OutlineInputBorder(
                          borderRadius:
                              BorderRadius.all(Radius.circular(24)),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: () async {
                      final text = controller.text;
                      if (text.trim().isNotEmpty) {
                        await _sendRelayMessage(peerName, text);
                        controller.clear();
                      }
                    },
                    icon: const Icon(Icons.send_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF7D3C98),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.orange[50],
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 16, color: Colors.orange),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Connect via Proximity Chat to send relay messages',
                      style: TextStyle(fontSize: 12, color: Colors.orange),
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