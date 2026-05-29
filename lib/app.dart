import 'package:flutter/material.dart';
import 'features/channels/channel_screen.dart';
import 'features/discovery/wifi_direct_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/relay_map/relay_map_screen.dart';
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
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B4F8A),
          primary: const Color(0xFF1B4F8A),
          secondary: const Color(0xFF2E86C1),
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1B4F8A),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor:
              const Color(0xFF1B4F8A).withValues(alpha: 0.12),
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1B4F8A),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: Color(0xFFAED6F1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
                color: Color(0xFF1B4F8A), width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 12),
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      home: _RootRouter(storage: storage),
    );
  }
}

class _RootRouter extends StatefulWidget {
  final StorageService storage;
  const _RootRouter({required this.storage});

  @override
  State<_RootRouter> createState() => _RootRouterState();
}

class _RootRouterState extends State<_RootRouter> {
  @override
  Widget build(BuildContext context) {
    if (!widget.storage.onboardingDone) {
      return OnboardingScreen(
        onDone: () async {
          await widget.storage.setOnboardingDone();
          if (mounted) setState(() {});
        },
      );
    }
    return MainScreen(storage: widget.storage);
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
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          WifiDirectScreen(
            storage: widget.storage,
            service: _wifiService,
          ),
          ChannelScreen(
            storage: widget.storage,
            service: _wifiService,
          ),
          RelayMapScreen(service: _wifiService),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) =>
            setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.sensors_outlined),
            selectedIcon: Icon(Icons.sensors),
            label: 'Nearby',
          ),
          NavigationDestination(
            icon: Icon(Icons.alt_route_outlined),
            selectedIcon: Icon(Icons.alt_route),
            label: 'Mesh Relay',
          ),
          NavigationDestination(
            icon: Icon(Icons.device_hub_outlined),
            selectedIcon: Icon(Icons.device_hub),
            label: 'Network',
          ),
        ],
      ),
    );
  }
}