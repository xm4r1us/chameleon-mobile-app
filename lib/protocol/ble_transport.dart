import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'transport.dart';

class ChameleonBleUuids {
  static final service = Guid('6E400001-B5A3-F393-E0A9-E50E24DCCA9E');
  static final rx = Guid('6E400002-B5A3-F393-E0A9-E50E24DCCA9E'); // write
  static final tx = Guid('6E400003-B5A3-F393-E0A9-E50E24DCCA9E'); // notify
}

class BleTransport implements ChameleonTransport {
  BleTransport(this.device);

  final BluetoothDevice device;

  final StreamController<Uint8List> _incoming = StreamController<Uint8List>.broadcast();
  final StreamController<void> _disconnected = StreamController<void>.broadcast();
  StreamSubscription<List<int>>? _valueSub;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  BluetoothCharacteristic? _rx;
  bool _connected = false;
  bool _intentionalDisconnect = false;

  @override
  String get description => 'BLE ${device.remoteId}';

  @override
  bool get isConnected => _connected;

  @override
  Stream<Uint8List> get incoming => _incoming.stream;

  @override
  Stream<void> get disconnected => _disconnected.stream;

  @override
  Future<void> connect() async {
    _intentionalDisconnect = false;
    await device.connect(timeout: const Duration(seconds: 25), mtu: 512);
    try {
      await device.requestMtu(512);
    } catch (_) {
      // Android negotiates during connect; iOS/macOS manage MTU themselves.
    }

    final services = await device.discoverServices();
    BluetoothService? uart;
    for (final service in services) {
      if (service.uuid == ChameleonBleUuids.service) {
        uart = service;
        break;
      }
    }
    if (uart == null) {
      await device.disconnect();
      throw TransportException('Chameleon UART service not found');
    }

    for (final c in uart.characteristics) {
      if (c.uuid == ChameleonBleUuids.rx) _rx = c;
    }
    BluetoothCharacteristic? tx;
    for (final c in uart.characteristics) {
      if (c.uuid == ChameleonBleUuids.tx) tx = c;
    }
    if (_rx == null || tx == null) {
      await device.disconnect();
      throw TransportException('Chameleon UART characteristics not found');
    }

    _connected = true;
    _valueSub = tx.onValueReceived.listen((value) => _incoming.add(Uint8List.fromList(value)));
    await tx.setNotifyValue(true);

    _connectionSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected && _connected) {
        _connected = false;
        if (!_intentionalDisconnect) {
          _disconnected.add(null);
        }
      }
    });
  }

  @override
  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _connected = false;
    await _valueSub?.cancel();
    _valueSub = null;
    await _connectionSub?.cancel();
    _connectionSub = null;
    try {
      if (device.isConnected) await device.disconnect();
    } catch (_) {
      // Already gone.
    }
  }

  @override
  Future<void> write(Uint8List data) async {
    final characteristic = _rx;
    if (characteristic == null || !_connected) {
      throw TransportException('BLE link is not connected');
    }

    // The firmware parses a byte stream, so splitting a frame over multiple
    // GATT writes is safe. Keep each chunk inside the negotiated MTU.
    final mtu = Platform.isAndroid ? device.mtuNow : 185;
    final chunkSize = (mtu - 3).clamp(20, 509);
    for (var offset = 0; offset < data.length; offset += chunkSize) {
      final end = (offset + chunkSize < data.length) ? offset + chunkSize : data.length;
      await characteristic.write(
        data.sublist(offset, end),
        withoutResponse: false,
        timeout: 10,
      );
    }
  }
}
