import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../protocol/ble_transport.dart';

class BleScanEntry {
  BleScanEntry(this.device, this.name, this.rssi, {this.hasUartService = false});
  final BluetoothDevice device;
  final String name;
  final int rssi;
  final bool hasUartService;

  String get id => device.remoteId.str;

  bool get isChameleon {
    final lower = name.toLowerCase();
    return lower.startsWith('chameleonultra') ||
        lower.startsWith('chameleonlite') ||
        lower.startsWith('chameleon ultra') ||
        lower.startsWith('chameleon lite');
  }

  bool get isUsable => isChameleon || hasUartService;
}

class BleScanner extends ChangeNotifier {
  final Map<String, BleScanEntry> _found = {};
  StreamSubscription<List<ScanResult>>? _resultSub;
  StreamSubscription<bool>? _scanningSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  bool _scanning = false;
  String? _error;
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;
  DateTime? _lastStart;

  List<BleScanEntry> get devices {
    final list = _found.values.where((e) => e.isUsable).toList();
    list.sort((a, b) => b.rssi.compareTo(a.rssi));
    return list;
  }

  bool get scanning => _scanning;
  String? get error => _error;
  bool get bluetoothOn => _adapterState == BluetoothAdapterState.on;

  Future<void> init() async {
    _adapterSub ??= FlutterBluePlus.adapterState.listen((state) {
      _adapterState = state;
      notifyListeners();
    });
    _scanningSub ??= FlutterBluePlus.isScanning.listen((value) {
      _scanning = value;
      notifyListeners();
    });
    _resultSub ??= FlutterBluePlus.onScanResults.listen((results) {
      for (final result in results) {
        final name = result.advertisementData.advName.isNotEmpty
            ? result.advertisementData.advName
            : result.device.platformName;
        final hasUart = result.advertisementData.serviceUuids
            .any((uuid) => uuid == ChameleonBleUuids.service);
        final entry = BleScanEntry(result.device, name, result.rssi, hasUartService: hasUart);
        if (entry.isUsable) {
          _found[entry.id] = entry;
        }
      }
      notifyListeners();
    }, onError: (Object error) {
      _error = error.toString();
      notifyListeners();
    });
  }

  Future<void> start() async {
    await init();
    if (_scanning) return;
    // Android throttles scans to five per 30 seconds.
    final now = DateTime.now();
    if (_lastStart != null && now.difference(_lastStart!) < const Duration(seconds: 3)) {
      await Future<void>.delayed(const Duration(milliseconds: 800));
    }
    _lastStart = now;
    _error = null;
    _found.clear();
    notifyListeners();
    try {
      final state = await FlutterBluePlus.adapterState.where((s) => s != BluetoothAdapterState.unknown).first
          .timeout(const Duration(seconds: 3), onTimeout: () => BluetoothAdapterState.unknown);
      _adapterState = state;
      if (state == BluetoothAdapterState.off) {
        _error = 'bluetooth_off';
        notifyListeners();
        return;
      }
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 12),
        androidScanMode: AndroidScanMode.lowLatency,
      );
    } catch (error) {
      _error = error.toString();
      _scanning = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    _scanning = false;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _resultSub?.cancel();
    _scanningSub?.cancel();
    _adapterSub?.cancel();
    super.dispose();
  }
}
