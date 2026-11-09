import 'dart:convert';
import 'dart:typed_data';

import '../models/dump.dart';
import '../protocol/byte_utils.dart';
import '../protocol/tag_types.dart';

class DumpCodec {
  static String suggestedExtension(DumpRecord record) => switch (record.kind) {
        DumpKind.mf1 || DumpKind.mfu => 'bin',
        DumpKind.lf => 'txt',
        DumpKind.raw => 'bin',
      };

  static Uint8List encodeBinary(DumpRecord record) => record.data;

  static String encodeEml(DumpRecord record) {
    final out = StringBuffer();
    if (record.isMfu) {
      if (record.version != null && record.version!.isNotEmpty) {
        out.writeln('# Version: ${bytesToHex(record.version!)}');
      }
      if (record.signature != null && record.signature!.any((b) => b != 0)) {
        out.writeln('# Signature: ${bytesToHex(record.signature!)}');
      }
      for (var offset = 0; offset < record.data.length; offset += 4) {
        final end = (offset + 4 < record.data.length) ? offset + 4 : record.data.length;
        out.writeln(bytesToHex(record.data.sublist(offset, end)));
      }
    } else {
      for (var offset = 0; offset < record.data.length; offset += 16) {
        final end = (offset + 16 < record.data.length) ? offset + 16 : record.data.length;
        out.writeln(bytesToHex(record.data.sublist(offset, end)));
      }
    }
    return out.toString();
  }

  static String encodeJson(DumpRecord record) =>
      const JsonEncoder.withIndent('  ').convert(record.toJson());

  static Uint8List exportBytes(DumpRecord record, {required bool asEml, required bool asJson}) {
    if (asJson) return Uint8List.fromList(utf8.encode(encodeJson(record)));
    if (asEml) return Uint8List.fromList(utf8.encode(encodeEml(record)));
    return record.data;
  }

  /// Decodes a .bin/.eml/.json dump. [forcedType] disambiguates raw dumps with
  /// an unusual length.
  static DumpRecord? decodeFile(
    String filename,
    Uint8List bytes, {
    TagType? forcedType,
  }) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.json')) {
      try {
        final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
        if (decoded is Map<String, dynamic>) return DumpRecord.fromJson(decoded);
        if (decoded is List && decoded.isNotEmpty && decoded.first is Map<String, dynamic>) {
          return DumpRecord.fromJson(decoded.first as Map<String, dynamic>);
        }
      } catch (_) {
        return null;
      }
      return null;
    }

    if (lower.endsWith('.eml') || lower.endsWith('.txt')) {
      final text = utf8.decode(bytes, allowMalformed: true);
      final hex = _extractHex(text);
      if (hex == null || hex.isEmpty) return null;
      final record = _makeRecord(filename, hex, forcedType);
      if (record == null) return null;
      final version = RegExp(r'^#\s*Version:\s*([0-9a-fA-F]{16})', multiLine: true).firstMatch(text);
      final signature = RegExp(r'^#\s*Signature:\s*([0-9a-fA-F]{64})', multiLine: true).firstMatch(text);
      if (record.isMfu && version != null) {
        record.version = hexToBytes(version.group(1)!);
      }
      if (record.isMfu && signature != null) {
        record.signature = hexToBytes(signature.group(1)!);
      }
      return record;
    }

    return _makeRecord(filename, bytes, forcedType);
  }

  static Uint8List? _extractHex(String text) {
    final out = BytesBuilder();
    var found = false;
    for (var line in const LineSplitter().convert(text)) {
      line = line.split('#').first.trim();
      if (line.isEmpty) continue;
      line = line.replaceFirst(RegExp(r'^[^:]{1,16}:\s*'), '');
      final match = RegExp(r'^([0-9a-fA-F]+)$').firstMatch(line.replaceAll(RegExp(r'\s'), ''));
      if (match == null) continue;
      var value = match.group(1)!;
      if (value.length.isOdd) value = value.substring(1);
      try {
        out.add(hexToBytes(value));
        found = true;
      } catch (_) {}
    }
    return found ? out.toBytes() : null;
  }

  static DumpRecord? _makeRecord(String filename, Uint8List bytes, TagType? forcedType) {
    if (bytes.isEmpty) return null;
    final baseName = filename.split('/').last.replaceFirst(RegExp(r'\.[^.]+$'), '');
    final id = '${DateTime.now().microsecondsSinceEpoch}-${bytes.length}';
    final type = forcedType ?? TagTypes.fromDumpLength(bytes.length);

    if (type != null && type.isMifareClassic) {
      final expected = type.mf1Blocks! * 16;
      if (bytes.length != expected) return null;
      return DumpRecord(
        id: id,
        name: baseName,
        kind: DumpKind.mf1,
        tagTypeId: type.id,
        data: Uint8List.fromList(bytes),
        createdAt: DateTime.now(),
        source: 'import',
      );
    }

    if (type != null && type.isUltralight) {
      final max = type.mfuPages! * 4;
      if (bytes.length > max || bytes.length % 4 != 0) return null;
      return DumpRecord(
        id: id,
        name: baseName,
        kind: DumpKind.mfu,
        tagTypeId: type.id,
        data: Uint8List.fromList(bytes),
        createdAt: DateTime.now(),
        source: 'import',
      );
    }

    // Unknown length: keep as a generic binary dump instead of guessing wrong.
    return DumpRecord(
      id: id,
      name: baseName,
      kind: DumpKind.raw,
      tagTypeId: 0,
      data: Uint8List.fromList(bytes),
      createdAt: DateTime.now(),
      source: 'import',
    );
  }

  static List<Uint8List> parseKeyDictionary(String text) {
    final keys = <String>{};
    for (final line in const LineSplitter().convert(text)) {
      final clean = line.trim().replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
      if (clean.length == 12) keys.add(clean.toUpperCase());
    }
    return keys.map((hex) => hexToBytes(hex)).toList();
  }

  static String encodeKeyDictionary(Iterable<Uint8List> keys) =>
      keys.map((key) => bytesToHexUpper(key)).toSet().join('\n');
}
