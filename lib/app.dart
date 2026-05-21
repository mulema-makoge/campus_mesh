import 'package:flutter/material.dart';
import 'features/discovery/peer_list_screen.dart';
import 'features/discovery/wifi_direct_screen.dart';
import 'services/storage_service.dart';

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

  @override
  Widget build(BuildContext context) {
    final screens = [
      const PeerListScreen(),
      WifiDirectScreen(storage: widget.storage),
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
            label: 'Wi-Fi Direct',
          ),
        ],
      ),
    );
  }
}