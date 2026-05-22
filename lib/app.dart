import 'package:flutter/material.dart';
import 'features/channels/channel_screen.dart';
import 'features/discovery/peer_list_screen.dart';
import 'features/discovery/wifi_direct_screen.dart';
import 'services/storage_service.dart';
import 'services/wifi_direct_service.dart';

class CampusMeshApp extends StatelessWidget {
  final StorageService storage;
  const CampusMeshApp({super.key, required this.storage});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CampusMesh',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      home: MainScreen(storage: storage),
    );
  }
}

class MainScreen extends StatefulWidget {
  final StorageService storage;
  const MainScreen({super.key, required this.storage});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final WifiDirectService _wifiService = WifiDirectService();

  @override
  void dispose() {
    _wifiService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      const PeerListScreen(),
      WifiDirectScreen(
        storage: widget.storage,
        service: _wifiService,
      ),
      ChannelScreen(
        storage: widget.storage,
        service: _wifiService,
      ),
    ];

    return Scaffold(
      body: screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) =>
            setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.bluetooth),
            label: 'BLE Peers',
          ),
          NavigationDestination(
            icon: Icon(Icons.wifi),
            label: 'Direct Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.group),
            label: 'Channel',
          ),
        ],
      ),
    );
  }
}