import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/wifi_direct_service.dart';

class RelayMapScreen extends StatefulWidget {
  final WifiDirectService? service;
  const RelayMapScreen({super.key, this.service});

  @override
  State<RelayMapScreen> createState() => _RelayMapScreenState();
}

class _RelayMapScreenState extends State<RelayMapScreen> {
  StreamSubscription<List<String>>? _relaySubscription;
  final List<List<String>> _hopPaths = [];

  @override
  void initState() {
    super.initState();
    _relaySubscription = widget.service?.relayStream.listen((hopPath) {
      setState(() {
        _hopPaths.add(hopPath);
        // Keep last 10 relay paths
        if (_hopPaths.length > 10) _hopPaths.removeAt(0);
      });
    });
  }

  @override
  void dispose() {
    _relaySubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Relay Map'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.clear_all),
            onPressed: () => setState(() => _hopPaths.clear()),
            tooltip: 'Clear',
          ),
        ],
      ),
      body: _hopPaths.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.alt_route, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No relay activity yet',
                    style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                        fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Messages relayed through the mesh\nwill appear here',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Summary bar
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: Colors.blue[50],
                  child: Text(
                    '📡 ${_hopPaths.length} relayed message${_hopPaths.length == 1 ? '' : 's'} detected',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                // Hop path list
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _hopPaths.length,
                    itemBuilder: (context, index) {
                      final path = _hopPaths[
                          _hopPaths.length - 1 - index]; // newest first
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Relay path #${_hopPaths.length - index}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13),
                              ),
                              const SizedBox(height: 8),
                              // Animated hop path
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    for (int i = 0;
                                        i < path.length;
                                        i++) ...[
                                      _buildHopNode(path[i], i, path.length),
                                      if (i < path.length - 1)
                                        _buildHopArrow(),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${path.length} hop${path.length == 1 ? '' : 's'}',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildHopNode(String nodeId, int index, int total) {
    final isFirst = index == 0;
    final isLast = index == total - 1;
    final color = isFirst
        ? Colors.green
        : isLast
            ? Colors.blue
            : Colors.orange;
    final label = isFirst
        ? 'Origin'
        : isLast
            ? 'Dest'
            : 'Relay';

    return Column(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            isFirst
                ? Icons.send
                : isLast
                    ? Icons.inbox
                    : Icons.alt_route,
            color: Colors.white,
            size: 20,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.bold),
        ),
        Text(
          nodeId.length > 8
              ? '${nodeId.substring(0, 8)}...'
              : nodeId,
          style:
              const TextStyle(fontSize: 9, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildHopArrow() {
    return const Padding(
      padding: EdgeInsets.only(bottom: 20),
      child: Row(
        children: [
          SizedBox(width: 4),
          Icon(Icons.arrow_forward, color: Colors.grey, size: 20),
          SizedBox(width: 4),
        ],
      ),
    );
  }
}