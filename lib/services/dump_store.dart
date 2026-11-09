import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/dump.dart';
import '../protocol/tag_types.dart';
import 'dump_codec.dart';

class DumpStore extends ChangeNotifier {
  final List<DumpRecord> _dumps = [];
  bool _loaded = false;
  File? _file;

  bool get loaded => _loaded;
  List<DumpRecord> get dumps => List.unmodifiable(
        [..._dumps]..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      );

  DumpRecord? byId(String id) {
    for (final dump in _dumps) {
      if (dump.id == id) return dump;
    }
    return null;
  }

  Future<void> load() async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/dumps');
    if (!await folder.exists()) await folder.create(recursive: true);
    _file = File('${folder.path}/dumps.json');
    if (await _file!.exists()) {
      try {
        final decoded = jsonDecode(await _file!.readAsString());
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map<String, dynamic>) {
              _dumps.add(DumpRecord.fromJson(item));
            }
          }
        }
      } catch (error) {
        debugPrint('Failed to load dumps: $error');
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> save() async {
    if (_file == null) return;
    final json = jsonEncode(_dumps.map((d) => d.toJson()).toList());
    await _file!.writeAsString(json, flush: true);
  }

  Future<void> add(DumpRecord record) async {
    _dumps.add(record);
    await save();
    notifyListeners();
  }

  Future<void> update(DumpRecord record) async {
    final index = _dumps.indexWhere((d) => d.id == record.id);
    if (index >= 0) _dumps[index] = record;
    await save();
    notifyListeners();
  }

  Future<void> delete(String id) async {
    _dumps.removeWhere((d) => d.id == id);
    await save();
    notifyListeners();
  }

  Future<void> clear() async {
    _dumps.clear();
    await save();
    notifyListeners();
  }

  Future<DumpRecord> importFile(String filename, Uint8List bytes, {TagType? forcedType}) async {
    var record = DumpCodec.decodeFile(filename, bytes, forcedType: forcedType);
    if (record == null) {
      throw FormatException('Could not decode $filename');
    }
    if (byId(record.id) != null) {
      record = DumpRecord(
        id: '${DateTime.now().microsecondsSinceEpoch}-${record.data.length}',
        name: record.name,
        kind: record.kind,
        tagTypeId: record.tagTypeId,
        data: record.data,
        createdAt: record.createdAt,
        keys: record.keys,
        source: record.source,
        note: record.note,
        version: record.version,
        signature: record.signature,
      );
    }
    await add(record);
    return record;
  }

  Future<DumpRecord> duplicate(DumpRecord record, {String? name}) async {
    final copy = DumpRecord(
      id: '${DateTime.now().microsecondsSinceEpoch}-${record.data.length}',
      name: name ?? '${record.displayName} copy',
      kind: record.kind,
      tagTypeId: record.tagTypeId,
      data: Uint8List.fromList(record.data),
      createdAt: DateTime.now(),
      keys: record.keys.copy(),
      source: record.source,
      note: record.note,
      version: record.version,
      signature: record.signature,
    );
    await add(copy);
    return copy;
  }
}
