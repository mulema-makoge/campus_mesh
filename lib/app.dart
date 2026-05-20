import 'package:flutter/material.dart';
import 'features/discovery/peer_list_screen.dart';
import 'features/discovery/wifi_direct_screen.dart';

class CampusMeshApp extends StatelessWidget {
  const CampusMeshApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CampusMesh',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    PeerListScreen(),
    WifiDirectScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
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
