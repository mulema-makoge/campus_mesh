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
  StreamSubscription<int>? _latencySubscription;
  final List<List<String>> _hopPaths = [];
  final List<int> _latencies = [];

  int get _avgLatency => _latencies.isEmpty
      ? 0
      : _latencies.reduce((a, b) => a + b) ~/ _latencies.length;
  int get _minLatency =>
      _latencies.isEmpty ? 0 : _latencies.reduce((a, b) => a < b ? a : b);
  int get _maxLatency =>
      _latencies.isEmpty ? 0 : _latencies.reduce((a, b) => a > b ? a : b);

  @override
  void initState() {
    super.initState();
    _relaySubscription = widget.service?.relayStream.listen((hopPath) {
      setState(() {
        _hopPaths.add(hopPath);
        if (_hopPaths.length > 10) _hopPaths.removeAt(0);
      });
    });
    _latencySubscription =
        widget.service?.latencyStream.listen((latency) {
      setState(() {
        _latencies.add(latency);
        if (_latencies.length > 50) _latencies.removeAt(0);
      });
    });
  }

  @override
  void dispose() {
    _relaySubscription?.cancel();
    _latencySubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Relay Map'),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear_all),
            onPressed: () => setState(() {
              _hopPaths.clear();
              _latencies.clear();
            }),
            tooltip: 'Clear',
          ),
        ],
      ),
      body: Column(
        children: [
          // Metrics bar
          if (_latencies.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.blue[50],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildMetric('Avg', '$_avgLatency ms', Colors.blue),
                  _buildMetric('Min', '$_minLatency ms', Colors.green),
                  _buildMetric('Max', '$_maxLatency ms', Colors.orange),
                  _buildMetric(
                      'Count', '${_latencies.length}', Colors.purple),
                ],
              ),
            ),

          // Relay paths
          Expanded(
            child: _hopPaths.isEmpty && _latencies.isEmpty
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
                          'Send messages to see latency metrics\nand relay paths appear here',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Latency history
                      if (_latencies.isNotEmpty) ...[
                        const Text('Message Latency',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                        const SizedBox(height: 8),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              children: _latencies.reversed
                                  .take(5)
                                  .toList()
                                  .asMap()
                                  .entries
                                  .map((e) {
                                final latency = e.value;
                                final color = latency < 100
                                    ? Colors.green
                                    : latency < 500
                                        ? Colors.orange
                                        : Colors.red;
                                return Padding(
                                  padding:
                                      const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    children: [
                                      Icon(Icons.circle,
                                          size: 8, color: color),
                                      const SizedBox(width: 8),
                                      Text('Message ${_latencies.length - e.key}'),
                                      const Spacer(),
                                      Text(
                                        '$latency ms',
                                        style: TextStyle(
                                            color: color,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Relay paths
                      if (_hopPaths.isNotEmpty) ...[
                        const Text('Relay Paths',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                        const SizedBox(height: 8),
                        ..._hopPaths.reversed.map((path) => Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${path.length} hop${path.length == 1 ? '' : 's'}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13),
                                    ),
                                    const SizedBox(height: 8),
                                    SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                        children: [
                                          for (int i = 0;
                                              i < path.length;
                                              i++) ...[
                                            _buildHopNode(
                                                path[i], i, path.length),
                                            if (i < path.length - 1)
                                              _buildHopArrow(),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetric(String label, String value, Color color) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color)),
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
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
        Text(label,
            style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.bold)),
        Text(
          nodeId.length > 8
              ? '${nodeId.substring(0, 8)}...'
              : nodeId,
          style: const TextStyle(fontSize: 9, color: Colors.grey),
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