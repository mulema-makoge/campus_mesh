import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BleService {
  final _devicesController = StreamController<List<ScanResult>>.broadcast();
  Stream<List<ScanResult>> get devicesStream => _devicesController.stream;
  final List<ScanResult> _foundDevices = [];

  static const String serviceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';

Future<bool> requestPermissions() async {
  // Android 12+ uses new BLE permissions
  // Android 11 and below uses location only
  if (await Permission.bluetoothScan.status.isGranted) {
    // Android 12+ — request new permissions
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.locationWhenInUse,
    ].request();
    return statuses.values.every((s) => s == PermissionStatus.granted);
  } else {
    // Android 11 and below — location is enough
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.locationWhenInUse,
    ].request();
    return statuses.values.every((s) => s == PermissionStatus.granted);
  }
}

  Future<void> startScan() async {
    _foundDevices.clear();

    if (await FlutterBluePlus.isSupported == false) {
      print('BLE not supported on this device');
      return;
    }

    // Request permissions before scanning
    final granted = await requestPermissions();
    if (!granted) {
      print('Permissions not granted');
      return;
    }

    // Make sure location is enabled (required on Android <12)
    final locationEnabled = await Permission.location.serviceStatus.isEnabled;
    if (!locationEnabled) {
      print('Location services are disabled');
      return;
    }

    await FlutterBluePlus.adapterState
        .where((state) => state == BluetoothAdapterState.on)
        .first;

    FlutterBluePlus.scanResults.listen((results) {
      final meshDevices = results.where((r) {
        return r.advertisementData.serviceUuids
            .any((uuid) => uuid.toString().toLowerCase() ==
                serviceUuid.toLowerCase()) ||
            r.device.platformName.contains('CampusMesh');
      }).toList();

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