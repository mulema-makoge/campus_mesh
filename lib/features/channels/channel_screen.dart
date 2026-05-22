import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/channel.dart';
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
  final TextEditingController _messageController = TextEditingController();
  final List<ChannelMessage> _messages = [];
  final List<ChannelMember> _members = [];
  bool _isBroadcast = false;
  bool _isInChannel = false;
  UserProfile? _myProfile;
  StreamSubscription<String>? _messageSubscription;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _listenForMessages();
  }

  Future<void> _loadProfile() async {
    final profile = widget.storage.getProfile();
    if (profile != null) {
      setState(() => _myProfile = profile);
      // Auto join channel when screen opens if connected
      if (widget.service?.cryptoReady == true) {
        _joinChannel();
      }
    }
  }

  void _listenForMessages() {
    _messageSubscription =
        widget.service?.messageStream.listen((message) {
      if (message.startsWith('CHANNEL_JOIN:')) {
        final memberJson = message.substring(13);
        final member = ChannelMember.fromJson(memberJson);
        setState(() {
          // Add member if not already in list
          if (!_members.any((m) => m.id == member.id)) {
            _members.add(member);
          }
          _isInChannel = true;
        });
      } else if (message.startsWith('CHANNEL:') ||
          message.startsWith('BROADCAST:')) {
        final isBroadcast = message.startsWith('BROADCAST:');
        final prefix = isBroadcast ? 'BROADCAST:' : 'CHANNEL:';
        final content = message.substring(prefix.length);

        // Parse sender info from content: "name|color|text"
        final parts = content.split('|');
        if (parts.length >= 3) {
          final senderName = parts[0];
          final senderColor =
              int.tryParse(parts[1]) ?? 0xFF2196F3;
          final text = parts.sublist(2).join('|');
          final now = DateTime.now();
          final time =
              '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

          setState(() => _messages.add(ChannelMessage(
                senderId: senderName,
                senderName: senderName,
                senderColor: senderColor,
                content: text,
                time: time,
                isBroadcast: isBroadcast,
              )));
        }
      }
    });
  }

  Future<void> _joinChannel() async {
    if (_myProfile == null || widget.service == null) return;
    final member = ChannelMember(
      id: _myProfile!.displayName,
      displayName: _myProfile!.displayName,
      avatarColorValue: _myProfile!.avatarColorValue,
    );
    // Add ourselves to member list
    setState(() {
      if (!_members.any((m) => m.id == member.id)) {
        _members.add(member);
      }
      _isInChannel = true;
    });
    // Announce join to peers
    await widget.service
        ?.sendMessage('CHANNEL_JOIN:${member.toJson()}');
  }

  Future<void> _sendChannelMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _myProfile == null) return;

    // Format: "name|color|message"
    final payload =
        '${_myProfile!.displayName}|${_myProfile!.avatarColorValue}|$text';

    await widget.service
        ?.sendChannelMessage(payload, isBroadcast: _isBroadcast);

    final now = DateTime.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    setState(() => _messages.add(ChannelMessage(
          senderId: _myProfile!.displayName,
          senderName: _myProfile!.displayName,
          senderColor: _myProfile!.avatarColorValue,
          content: text,
          time: time,
          isBroadcast: _isBroadcast,
        )));

    _messageController.clear();
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Campus Channel'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          // Member count
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Text(
                '👥 ${_members.length}',
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Channel status bar
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: _isInChannel ? Colors.green[50] : Colors.orange[50],
            child: Row(
              children: [
                Icon(
                  _isInChannel ? Icons.wifi_tethering : Icons.wifi_off,
                  size: 16,
                  color: _isInChannel ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isInChannel
                        ? '🟢 Campus channel · ${_members.length} member${_members.length == 1 ? '' : 's'}'
                        : '🟡 Not in channel — connect first',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                if (!_isInChannel &&
                    widget.service?.cryptoReady == true)
                  TextButton(
                    onPressed: _joinChannel,
                    child: const Text('Join'),
                  ),
              ],
            ),
          ),

          // Member list
          if (_members.isNotEmpty)
            Container(
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _members.length,
                itemBuilder: (context, index) {
                  final member = _members[index];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8, top: 8),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor:
                              Color(member.avatarColorValue),
                          child: Text(
                            member.displayName[0].toUpperCase(),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          member.displayName.length > 6
                              ? '${member.displayName.substring(0, 6)}...'
                              : member.displayName,
                          style: const TextStyle(fontSize: 9),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

          // Messages
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text(
                      'No messages yet\nBe the first to say something!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isMine =
                          msg.senderId == _myProfile?.displayName;

                      return Align(
                        alignment: isMine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin:
                              const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: msg.isBroadcast
                                ? Colors.amber[100]
                                : isMine
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primary
                                    : Colors.grey[200],
                            borderRadius: BorderRadius.circular(12),
                            border: msg.isBroadcast
                                ? Border.all(
                                    color: Colors.amber, width: 1)
                                : null,
                          ),
                          child: Column(
                            crossAxisAlignment: isMine
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              if (!isMine)
                                Text(
                                  msg.senderName,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color:
                                        Color(msg.senderColor),
                                  ),
                                ),
                              if (msg.isBroadcast)
                                const Text(
                                  '📢 Broadcast',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.orange),
                                ),
                              Text(
                                msg.content,
                                style: TextStyle(
                                  color: msg.isBroadcast
                                      ? Colors.black87
                                      : isMine
                                          ? Colors.white
                                          : Colors.black,
                                ),
                              ),
                              Text(
                                msg.time,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isMine && !msg.isBroadcast
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

          // Broadcast toggle + input
          if (_isInChannel)
            Column(
              children: [
                // Broadcast toggle
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.campaign, size: 16),
                      const SizedBox(width: 4),
                      const Text('Broadcast mode',
                          style: TextStyle(fontSize: 13)),
                      const Spacer(),
                      Switch(
                        value: _isBroadcast,
                        onChanged: (val) =>
                            setState(() => _isBroadcast = val),
                      ),
                    ],
                  ),
                ),
                // Message input
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          decoration: InputDecoration(
                            hintText: _isBroadcast
                                ? '📢 Type a broadcast...'
                                : 'Type a channel message...',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _sendChannelMessage,
                        icon: const Icon(Icons.send),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}