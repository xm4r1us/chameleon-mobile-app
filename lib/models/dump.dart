import 'dart:convert';
import 'dart:typed_data';

import '../protocol/byte_utils.dart';
import '../protocol/tag_types.dart';

enum DumpKind { mf1, mfu, lf, raw }

class Mf1Keys {
  Mf1Keys({Map<int, Uint8List>? keyA, Map<int, Uint8List>? keyB})
      : keyA = keyA ?? {},
        keyB = keyB ?? {};

  final Map<int, Uint8List> keyA;
  final Map<int, Uint8List> keyB;

  Mf1Keys copy() => Mf1Keys(
        keyA: {for (final e in keyA.entries) e.key: Uint8List.fromList(e.value)},
        keyB: {for (final e in keyB.entries) e.key: Uint8List.fromList(e.value)},
      );

  Set<String> get allKeyHex => {
        for (final key in keyA.values) bytesToHexUpper(key),
        for (final key in keyB.values) bytesToHexUpper(key),
      };

  bool get isEmpty => keyA.isEmpty && keyB.isEmpty;

  Map<String, dynamic> toJson() => {
        'a': {for (final e in keyA.entries) '${e.key}': bytesToHexUpper(e.value)},
        'b': {for (final e in keyB.entries) '${e.key}': bytesToHexUpper(e.value)},
      };

  static Mf1Keys fromJson(Map<String, dynamic>? json) {
    if (json == null) return Mf1Keys();
    final a = <int, Uint8List>{};
    final b = <int, Uint8List>{};
    (json['a'] as Map<String, dynamic>? ?? {}).forEach((key, value) {
      final sector = int.tryParse(key);
      if (sector != null) a[sector] = hexToBytes(value as String);
    });
    (json['b'] as Map<String, dynamic>? ?? {}).forEach((key, value) {
      final sector = int.tryParse(key);
      if (sector != null) b[sector] = hexToBytes(value as String);
    });
    return Mf1Keys(keyA: a, keyB: b);
  }
}

class DumpRecord {
  DumpRecord({
    required this.id,
    required this.name,
    required this.kind,
    required this.tagTypeId,
    required this.data,
    required this.createdAt,
    Mf1Keys? keys,
    this.source = 'tag',
    this.note = '',
    this.version,
    this.signature,
  }) : keys = keys ?? Mf1Keys();

  final String id;
  String name;
  final DumpKind kind;
  final int tagTypeId;
  Uint8List data;
  final DateTime createdAt;
  Mf1Keys keys;
  String source;
  String note;
  Uint8List? version;
  Uint8List? signature;

  TagType get tagType => TagTypes.byId(tagTypeId);
  int get byteLength => data.length;
  bool get isMf1 => kind == DumpKind.mf1;
  bool get isMfu => kind == DumpKind.mfu;
  bool get isLf => kind == DumpKind.lf;

  String get sizeLabel => isMf1 ? '${data.length ~/ 16} blocks' : '${data.length} B';

  String get displayName => name.isNotEmpty ? name : '${tagType.name} dump';

  DumpRecord copyWith({String? name, String? note}) => DumpRecord(
        id: id,
        name: name ?? this.name,
        kind: kind,
        tagTypeId: tagTypeId,
        data: data,
        createdAt: createdAt,
        keys: keys,
        source: source,
        note: note ?? this.note,
        version: version,
        signature: signature,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'tagType': tagTypeId,
        'data': base64Encode(data),
        'createdAt': createdAt.toIso8601String(),
        'keys': keys.toJson(),
        'source': source,
        'note': note,
        if (version != null) 'version': base64Encode(version!),
        if (signature != null) 'signature': base64Encode(signature!),
      };

  static DumpRecord fromJson(Map<String, dynamic> json) => DumpRecord(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        kind: DumpKind.values.firstWhere(
          (k) => k.name == json['kind'],
          orElse: () => DumpKind.raw,
        ),
        tagTypeId: json['tagType'] as int? ?? 0,
        data: base64Decode(json['data'] as String),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        keys: Mf1Keys.fromJson(json['keys'] as Map<String, dynamic>?),
        source: json['source'] as String? ?? 'import',
        note: json['note'] as String? ?? '',
        version: json['version'] != null ? base64Decode(json['version'] as String) : null,
        signature: json['signature'] != null ? base64Decode(json['signature'] as String) : null,
      );
}
