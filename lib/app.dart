import 'package:flutter/material.dart';
import 'features/discovery/peer_list_screen.dart';

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
      home: const PeerListScreen(),
    );
  }
}