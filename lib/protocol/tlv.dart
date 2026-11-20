import 'dart:typed_data';

import 'byte_utils.dart';

/// Generic BER-TLV node. No EMV semantics are attached: tags are shown as
/// hexadecimal identifiers and values as data.
class TlvNode {
  TlvNode({
    required this.tag,
    required this.tagBytes,
    required this.value,
    required this.offset,
    required this.constructed,
    this.children = const [],
  });

  final int tag;
  final Uint8List tagBytes;
  final Uint8List value;
  final int offset;
  final bool constructed;
  final List<TlvNode> children;

  String get tagHex => bytesToHexUpper(tagBytes);
  String get valueHex => bytesToHexUpper(value, separator: ' ');
}

class TlvParseResult {
  TlvParseResult(this.nodes, {this.error});
  final List<TlvNode> nodes;
  final String? error;
}

/// Walks [nodes] depth-first and yields every node whose tag matches
/// [tagHex] (case-insensitive, e.g. `'9F38'`).
Iterable<TlvNode> findTlvTag(Iterable<TlvNode> nodes, String tagHex) sync* {
  final wanted = tagHex.toUpperCase();
  for (final node in nodes) {
    if (node.tagHex == wanted) yield node;
    yield* findTlvTag(node.children, wanted);
  }
}

/// Parses a sequence of BER-TLV objects. Constructed tags are decoded
/// recursively; a malformed nested value is kept as a primitive leaf.
TlvParseResult parseTlv(Uint8List data, {int maxDepth = 12}) {
  try {
    return TlvParseResult(_parseSequence(data, 0, data.length, 0, maxDepth));
  } on FormatException catch (error) {
    return TlvParseResult(const [], error: error.message);
  }
}

List<TlvNode> _parseSequence(
  Uint8List data,
  int start,
  int end,
  int depth,
  int maxDepth,
) {
  final nodes = <TlvNode>[];
  var pos = start;
  while (pos < end) {
    if (depth > maxDepth) throw const FormatException('TLV nesting too deep');
    final nodeStart = pos;
    final tagInfo = _readTag(data, pos, end);
    pos = tagInfo.next;
    final lengthInfo = _readLength(data, pos, end);
    pos = lengthInfo.next;
    final valueEnd = pos + lengthInfo.length;
    if (valueEnd > end) throw const FormatException('TLV length exceeds data');
    final value = Uint8List.fromList(data.sublist(pos, valueEnd));
    final constructed = (data[nodeStart] & 0x20) != 0;
    var children = const <TlvNode>[];
    if (constructed && value.isNotEmpty && depth < maxDepth) {
      try {
        children = _parseSequence(value, 0, value.length, depth + 1, maxDepth);
      } on FormatException {
        // Keep malformed constructed payloads inspectable as raw bytes.
        children = const [];
      }
    }
    nodes.add(TlvNode(
      tag: tagInfo.tag,
      tagBytes: tagInfo.bytes,
      value: value,
      offset: nodeStart,
      constructed: constructed,
      children: children,
    ));
    pos = valueEnd;
  }
  return nodes;
}

class _TagInfo {
  _TagInfo(this.tag, this.bytes, this.next);
  final int tag;
  final Uint8List bytes;
  final int next;
}

_TagInfo _readTag(Uint8List data, int offset, int end) {
  if (offset >= end) throw const FormatException('Missing TLV tag');
  final first = data[offset];
  final bytes = <int>[first];
  var tag = first;
  var pos = offset + 1;
  if ((first & 0x1f) == 0x1f) {
    var count = 0;
    while (true) {
      if (pos >= end) throw const FormatException('Truncated multi-byte tag');
      final byte = data[pos++];
      bytes.add(byte);
      tag = (tag << 8) | byte;
      count++;
      if ((byte & 0x80) == 0) break;
      if (count > 3) throw const FormatException('Tag too long');
    }
  }
  return _TagInfo(tag, Uint8List.fromList(bytes), pos);
}

class _LengthInfo {
  _LengthInfo(this.length, this.next);
  final int length;
  final int next;
}

_LengthInfo _readLength(Uint8List data, int offset, int end) {
  if (offset >= end) throw const FormatException('Missing TLV length');
  final first = data[offset];
  if (first < 0x80) return _LengthInfo(first, offset + 1);
  final count = first & 0x7f;
  if (count == 0 || count > 3) throw const FormatException('Unsupported TLV length');
  if (offset + 1 + count > end) throw const FormatException('Truncated TLV length');
  var length = 0;
  for (var i = 0; i < count; i++) {
    length = (length << 8) | data[offset + 1 + i];
  }
  return _LengthInfo(length, offset + 1 + count);
}

String swDescription(int sw) {
  if (sw == 0x9000) return 'OK';
  if (sw >= 0x6100 && sw <= 0x61ff) return 'Response bytes available';
  if (sw == 0x6200) return 'Warning: state unchanged';
  if (sw == 0x6283) return 'Selected file invalidated';
  if (sw == 0x6300) return 'Authentication failed';
  if (sw == 0x6400) return 'Execution error';
  if (sw == 0x6500) return 'Memory failure';
  if (sw == 0x6700) return 'Wrong length';
  if (sw == 0x6882) return 'Secure messaging not supported';
  if (sw == 0x6982) return 'Security status not satisfied';
  if (sw == 0x6985) return 'Conditions not satisfied';
  if (sw == 0x6986) return 'Command not allowed';
  if (sw == 0x6a80) return 'Incorrect data';
  if (sw == 0x6a82) return 'File or application not found';
  if (sw == 0x6a83) return 'Record not found';
  if (sw == 0x6a84) return 'Not enough memory';
  if (sw == 0x6a86) return 'Incorrect P1/P2';
  if (sw == 0x6a88) return 'Referenced data not found';
  if (sw == 0x6b00) return 'Wrong parameters';
  if (sw == 0x6d00) return 'Instruction not supported';
  if (sw == 0x6e00) return 'Class not supported';
  if (sw == 0x6f00) return 'Unknown error';
  return 'Unknown status word';
}
