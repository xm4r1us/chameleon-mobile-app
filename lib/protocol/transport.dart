import 'dart:async';
import 'dart:typed_data';

/// Byte-stream transport to a Chameleon Ultra (BLE today, USB can be added
/// without touching the protocol client).
abstract class ChameleonTransport {
  String get description;

  bool get isConnected;

  Stream<Uint8List> get incoming;

  /// Emits when the underlying link drops unexpectedly.
  Stream<void> get disconnected;

  Future<void> connect();

  Future<void> disconnect();

  Future<void> write(Uint8List data);
}

class TransportException implements Exception {
  final String message;
  TransportException(this.message);

  @override
  String toString() => message;
}
