import 'dart:async';
import 'dart:math';
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
  final List<List<String>> _paths = [];
  final List<int> _latencies = [];
  final Map<String, String> _nodeLabels = {};

  int get _avgLatency => _latencies.isEmpty
      ? 0
      : _latencies.reduce((a, b) => a + b) ~/ _latencies.length;
  int get _minLatency => _latencies.isEmpty
      ? 0
      : _latencies.reduce((a, b) => a < b ? a : b);
  int get _maxLatency => _latencies.isEmpty
      ? 0
      : _latencies.reduce((a, b) => a > b ? a : b);

  Set<String> get _allNodes {
    final nodes = <String>{};
    for (final path in _paths) {
      nodes.addAll(path);
    }
    return nodes;
  }

  void _processPath(List<String> path) {
    _paths.add(path);
    if (_paths.length > 50) _paths.removeAt(0);
    for (final node in path) {
      if (!_nodeLabels.containsKey(node)) {
        if (node == 'peer') {
          _nodeLabels[node] = 'Peer';
        } else if (node == 'me') {
          _nodeLabels[node] = 'Me';
        } else if (node.startsWith('host_')) {
          _nodeLabels[node] = 'Host\n${node.substring(5)}';
        } else if (node.startsWith('client_')) {
          _nodeLabels[node] = 'Node\n${node.substring(7)}';
        } else {
          _nodeLabels[node] =
              node.length > 6 ? node.substring(0, 6) : node;
        }
      }
    }
  }

  @override
  void initState() {
    super.initState();

    // Pre-populate from buffered events (catches events
    // emitted before this screen subscribed)
    final buffered = widget.service?.recentRelayPaths ?? [];
    for (final path in buffered) {
      _processPath(path);
    }

    _relaySubscription =
        widget.service?.relayStream.listen((path) {
      setState(() => _processPath(path));
    });

    _latencySubscription =
        widget.service?.latencyStream.listen((latency) {
      setState(() {
        _latencies.add(latency);
        if (_latencies.length > 100) _latencies.removeAt(0);
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
    final nodes = _allNodes.toList();
    final latestPath = _paths.isNotEmpty ? _paths.last : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Network Topology'),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear_all),
            onPressed: () => setState(() {
              _paths.clear();
              _latencies.clear();
              _nodeLabels.clear();
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
                mainAxisAlignment:
                    MainAxisAlignment.spaceAround,
                children: [
                  _buildMetric('Avg RTT',
                      '$_avgLatency ms', Colors.blue),
                  _buildMetric('Min RTT',
                      '$_minLatency ms', Colors.green),
                  _buildMetric('Max RTT',
                      '$_maxLatency ms', Colors.orange),
                  _buildMetric('Messages',
                      '${_latencies.length}', Colors.purple),
                ],
              ),
            ),

          // Topology canvas
          Expanded(
            flex: 2,
            child: nodes.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment:
                          MainAxisAlignment.center,
                      children: [
                        Icon(Icons.device_hub,
                            size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'No network activity yet',
                          style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey,
                              fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Send messages to see the\nnetwork topology here',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : Container(
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1B2A),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: CustomPaint(
                        painter: NetworkTopologyPainter(
                          nodes: nodes,
                          paths: _paths,
                          latestPath: latestPath,
                          nodeLabels: _nodeLabels,
                        ),
                        child: const SizedBox(
                          width: double.infinity,
                          height: double.infinity,
                        ),
                      ),
                    ),
                  ),
          ),

          // Legend
          if (nodes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildLegend(
                      'Origin', const Color(0xFF27AE60)),
                  const SizedBox(width: 16),
                  _buildLegend(
                      'Relay', const Color(0xFFE67E22)),
                  const SizedBox(width: 16),
                  _buildLegend('Destination',
                      const Color(0xFF2E86C1)),
                ],
              ),
            ),

          // Path list
          if (_paths.isNotEmpty)
            Expanded(
              flex: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding:
                        EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(
                      'Recent Message Paths',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16),
                      itemCount: min(_paths.length, 5),
                      itemBuilder: (context, index) {
                        final path = _paths[
                            _paths.length - 1 - index];
                        final latency =
                            index < _latencies.length
                                ? _latencies[
                                    _latencies.length -
                                        1 -
                                        index]
                                : null;
                        final isHop = path.length > 2;
                        return Padding(
                          padding: const EdgeInsets.only(
                              bottom: 6),
                          child: Row(
                            children: [
                              Icon(
                                isHop
                                    ? Icons.alt_route
                                    : Icons.arrow_forward,
                                size: 14,
                                color: isHop
                                    ? Colors.purple
                                    : Colors.blue,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  path
                                      .map((n) =>
                                          (_nodeLabels[n] ??
                                                  n)
                                              .replaceAll(
                                                  '\n', ' '))
                                      .join(' → '),
                                  style: const TextStyle(
                                      fontSize: 12),
                                  overflow:
                                      TextOverflow.ellipsis,
                                ),
                              ),
                              if (latency != null)
                                Text(
                                  '${latency}ms',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight:
                                        FontWeight.bold,
                                    color: latency < 100
                                        ? Colors.green
                                        : latency < 500
                                            ? Colors.orange
                                            : Colors.red,
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMetric(
      String label, String value, Color color) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: color)),
        Text(label,
            style: const TextStyle(
                fontSize: 10, color: Colors.grey)),
      ],
    );
  }

  Widget _buildLegend(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
              color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}

class NetworkTopologyPainter extends CustomPainter {
  final List<String> nodes;
  final List<List<String>> paths;
  final List<String>? latestPath;
  final Map<String, String> nodeLabels;

  const NetworkTopologyPainter({
    required this.nodes,
    required this.paths,
    this.latestPath,
    required this.nodeLabels,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) * 0.30;
    const nodeRadius = 26.0;

    final Map<String, Offset> positions = {};
    if (nodes.length == 1) {
      positions[nodes[0]] = center;
    } else if (nodes.length == 2) {
      positions[nodes[0]] =
          Offset(size.width * 0.28, size.height / 2);
      positions[nodes[1]] =
          Offset(size.width * 0.72, size.height / 2);
    } else {
      for (int i = 0; i < nodes.length; i++) {
        final angle =
            (2 * pi * i / nodes.length) - (pi / 2);
        positions[nodes[i]] = Offset(
          center.dx + radius * cos(angle),
          center.dy + radius * sin(angle),
        );
      }
    }

    // Faint edges for all known paths
    final Set<String> drawnEdges = {};
    for (final path in paths) {
      for (int i = 0; i < path.length - 1; i++) {
        final key = [path[i], path[i + 1]]..sort();
        final edgeKey = key.join('-');
        if (!drawnEdges.contains(edgeKey)) {
          drawnEdges.add(edgeKey);
          final p1 = positions[path[i]];
          final p2 = positions[path[i + 1]];
          if (p1 != null && p2 != null) {
            canvas.drawLine(
              p1,
              p2,
              Paint()
                ..color =
                    Colors.white.withValues(alpha: 0.12)
                ..strokeWidth = 1.5
                ..style = PaintingStyle.stroke,
            );
          }
        }
      }
    }

    // Highlighted latest path with glow + arrows
    if (latestPath != null && latestPath!.length > 1) {
      for (int i = 0; i < latestPath!.length - 1; i++) {
        final p1 = positions[latestPath![i]];
        final p2 = positions[latestPath![i + 1]];
        if (p1 == null || p2 == null) continue;

        canvas.drawLine(
          p1,
          p2,
          Paint()
            ..color = const Color(0xFF2E86C1)
                .withValues(alpha: 0.25)
            ..strokeWidth = 10
            ..style = PaintingStyle.stroke,
        );
        canvas.drawLine(
          p1,
          p2,
          Paint()
            ..color = const Color(0xFF5DADE2)
            ..strokeWidth = 2.5
            ..style = PaintingStyle.stroke,
        );
        _drawArrow(canvas, p1, p2);
      }
    }

    // Nodes
    for (final node in nodes) {
      final pos = positions[node];
      if (pos == null) continue;

      Color nodeColor;
      if (latestPath != null && latestPath!.isNotEmpty) {
        if (node == latestPath!.first) {
          nodeColor = const Color(0xFF27AE60);
        } else if (node == latestPath!.last) {
          nodeColor = const Color(0xFF2E86C1);
        } else if (latestPath!.contains(node)) {
          nodeColor = const Color(0xFFE67E22);
        } else {
          nodeColor = const Color(0xFF566573);
        }
      } else {
        nodeColor = const Color(0xFF2E86C1);
      }

      // Glow
      canvas.drawCircle(
        pos,
        nodeRadius + 8,
        Paint()
          ..color = nodeColor.withValues(alpha: 0.2)
          ..style = PaintingStyle.fill,
      );
      // Fill
      canvas.drawCircle(
          pos, nodeRadius, Paint()..color = nodeColor);
      // Border
      canvas.drawCircle(
        pos,
        nodeRadius,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.5)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );

      // Initial
      final label = nodeLabels[node] ?? node;
      final initial =
          label.isNotEmpty ? label[0].toUpperCase() : '?';
      final tp = TextPainter(
        text: TextSpan(
          text: initial,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas,
          pos - Offset(tp.width / 2, tp.height / 2));

      // Label below
      final displayLabel =
          (nodeLabels[node] ?? node).replaceAll('\n', ' ');
      final shortLabel = displayLabel.length > 12
          ? displayLabel.substring(0, 12)
          : displayLabel;
      final lp = TextPainter(
        text: TextSpan(
          text: shortLabel,
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 9.5),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      lp.paint(
        canvas,
        Offset(pos.dx - lp.width / 2,
            pos.dy + nodeRadius + 5),
      );
    }
  }

  void _drawArrow(Canvas canvas, Offset from, Offset to) {
    final mid = Offset(
        (from.dx + to.dx) / 2, (from.dy + to.dy) / 2);
    final angle =
        atan2(to.dy - from.dy, to.dx - from.dx);
    const s = 9.0;
    final path = Path()
      ..moveTo(mid.dx + s * cos(angle),
          mid.dy + s * sin(angle))
      ..lineTo(mid.dx + s * cos(angle + 2.5),
          mid.dy + s * sin(angle + 2.5))
      ..lineTo(mid.dx + s * cos(angle - 2.5),
          mid.dy + s * sin(angle - 2.5))
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF5DADE2)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(NetworkTopologyPainter old) =>
      old.paths != paths || old.latestPath != latestPath;
}