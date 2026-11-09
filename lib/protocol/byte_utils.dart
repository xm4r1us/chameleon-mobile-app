import 'dart:typed_data';

String bytesToHex(Iterable<int> bytes, {String separator = ''}) =>
    bytes.map((b) => (b & 0xff).toRadixString(16).padLeft(2, '0')).join(separator);

String bytesToHexUpper(Iterable<int> bytes, {String separator = ''}) =>
    bytesToHex(bytes, separator: separator).toUpperCase();

Uint8List hexToBytes(String hex) {
  var clean = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
  if (clean.length.isOdd) {
    throw const FormatException('Hex string must have an even number of digits');
  }
  final out = Uint8List(clean.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

bool isHex(String value) {
  final clean = value.replaceAll(RegExp(r'\s'), '');
  return clean.isNotEmpty && clean.length.isEven && RegExp(r'^[0-9a-fA-F]+$').hasMatch(clean);
}

Uint8List be16(int value) => Uint8List.fromList([(value >> 8) & 0xff, value & 0xff]);

Uint8List be32(int value) => Uint8List.fromList([
      (value >> 24) & 0xff,
      (value >> 16) & 0xff,
      (value >> 8) & 0xff,
      value & 0xff,
    ]);

int u16(List<int> data, [int offset = 0]) => ((data[offset] & 0xff) << 8) | (data[offset + 1] & 0xff);

int u32(List<int> data, [int offset = 0]) =>
    ((data[offset] & 0xff) << 24) |
    ((data[offset + 1] & 0xff) << 16) |
    ((data[offset + 2] & 0xff) << 8) |
    (data[offset + 3] & 0xff);

int u64(List<int> data, [int offset = 0]) {
  var value = 0;
  for (var i = 0; i < 8; i++) {
    value = (value << 8) | (data[offset + i] & 0xff);
  }
  return value;
}

int signed32(int value) => value >= 0x80000000 ? value - 0x100000000 : value;

/// Formats a classic memory dump as blocks of [perLine] bytes.
String formatHexDump(Uint8List data, {int perLine = 16, int baseAddress = 0}) {
  final out = StringBuffer();
  for (var offset = 0; offset < data.length; offset += perLine) {
    final end = (offset + perLine < data.length) ? offset + perLine : data.length;
    final address = (baseAddress + offset).toRadixString(16).padLeft(4, '0');
    out.writeln('$address  ${bytesToHexUpper(data.sublist(offset, end), separator: ' ')}');
  }
  return out.toString();
}
