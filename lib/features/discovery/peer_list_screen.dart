import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../services/ble_service.dart';

class PeerListScreen extends StatefulWidget {
  const PeerListScreen({super.key});

  @override
  State<PeerListScreen> createState() => _PeerListScreenState();
}

class _PeerListScreenState extends State<PeerListScreen> {
  final BleService _bleService = BleService();
  List<ScanResult> _peers = [];
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _bleService.devicesStream.listen((devices) {
      setState(() => _peers = devices);
    });
  }

  Future<void> _toggleScan() async {
    if (_isScanning) {
      await _bleService.stopScan();
      setState(() => _isScanning = false);
    } else {
      setState(() => _isScanning = true);
      await _bleService.startScan();
      setState(() => _isScanning = false);
    }
  }

  @override
  void dispose() {
    _bleService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CampusMesh'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          if (_isScanning)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
            ),
        ],
      ),
      body: _peers.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.bluetooth_searching,
                      size: 64,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    _isScanning ? 'Scanning for peers...' : 'No peers found',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap the button below to scan',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _peers.length,
              itemBuilder: (context, index) {
                final peer = _peers[index];
                final name = peer.device.platformName.isNotEmpty
                    ? peer.device.platformName
                    : 'Unknown Device';
                final rssi = peer.rssi;
                final proximity = rssi > -60
                    ? 'Nearby'
                    : rssi > -80
                        ? 'Same Building'
                        : 'Same Area';
                final proximityColor = rssi > -60
                    ? Colors.green
                    : rssi > -80
                        ? Colors.orange
                        : Colors.red;

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    child: Text(name[0].toUpperCase()),
                  ),
                  title: Text(name),
                  subtitle: Text('${peer.device.remoteId}'),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        proximity,
                        style: TextStyle(
                          color: proximityColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        '$rssi dBm',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _toggleScan,
        icon: Icon(_isScanning ? Icons.stop : Icons.bluetooth_searching),
        label: Text(_isScanning ? 'Stop' : 'Scan'),
      ),
    );
  }
}