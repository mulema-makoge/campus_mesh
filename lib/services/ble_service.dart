import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleService {
  final _devicesController = StreamController<List<ScanResult>>.broadcast();
  Stream<List<ScanResult>> get devicesStream => _devicesController.stream;
  final List<ScanResult> _foundDevices = [];

  // CampusMesh service UUID — identifies our app to other devices
  static const String serviceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';

  Future<void> startScan() async {
    _foundDevices.clear();

    if (await FlutterBluePlus.isSupported == false) {
      print('BLE not supported on this device');
      return;
    }

    await FlutterBluePlus.adapterState
        .where((state) => state == BluetoothAdapterState.on)
        .first;

    FlutterBluePlus.scanResults.listen((results) {
      // Filter to only show CampusMesh devices
      final meshDevices = results.where((r) {
        return r.advertisementData.serviceUuids
            .any((uuid) => uuid.toString().toLowerCase() == serviceUuid.toLowerCase())
        || r.device.platformName.contains('CampusMesh');
      }).toList();

      // If no mesh devices found yet show all devices
      final toShow = meshDevices.isEmpty ? results : meshDevices;
      _foundDevices.clear();
      _foundDevices.addAll(toShow);
      _devicesController.add(List.from(_foundDevices));
    });

    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 10),
      androidUsesFineLocation: true,
    );
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  bool get isScanning => FlutterBluePlus.isScanningNow;

  void dispose() {
    _devicesController.close();
  }
}