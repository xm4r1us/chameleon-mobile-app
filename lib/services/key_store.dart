import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../protocol/byte_utils.dart';
import 'dump_codec.dart';

/// Bundled public MIFARE Classic keys plus a user-editable dictionary.
class KeyStore extends ChangeNotifier {
  static const _prefsKey = 'user_mifare_keys_v1';

  static const List<String> bundledHex = [
    'FFFFFFFFFFFF',
    'A0A1A2A3A4A5',
    'D3F7D3F7D3F7',
    '000000000000',
    'AABBCCDDEEFF',
    '010203040506',
    '1234567890AB',
    '123456789ABC',
    '4D3A99C351DD',
    '1A982C7E459A',
    'A64598A77478',
    '26940B21FF5D',
    'FC00018778F7',
    '00000FFE2488',
    '5C8FF9990DA2',
    'D01AFEEB890A',
    '75CCB59C9BED',
    '2149B914AB6C',
    '0F4B9A2C1D3E',
    '484558414354',
    '504974455249',
    '313233343536',
    '444546474849',
    'B0B1B2B3B4B5',
    'C0C1C2C3C4C5',
    'D0D1D2D3D4D5',
    'E0E1E2E3E4E5',
    'F0F1F2F3F4F5',
    'A1B2C3D4E5F6',
    '1A2B3C4D5E6F',
    '000000000001',
    '00000000000A',
    '00000000000B',
    '00000000000C',
    '00000000000D',
    '00000000000E',
    '00000000000F',
    '000000000010',
    '0000000000FF',
    'FFFFFFFF0000',
    '555555555555',
    'AAAAAAAAAAAA',
    'BBBBBBBBBBBB',
    'CCCCCCCCCCCC',
    'DDDDDDDDDDDD',
    'EEEEEEEEEEEE',
    '111111111111',
    '222222222222',
    '333333333333',
    '444444444444',
    '666666666666',
    '777777777777',
    '888888888888',
    '999999999999',
    'ABCDEF123456',
    'A0B0C0D0E0F0',
    'B0A1B2C3D4E5',
    'A1A2A3A4A5A6',
    'B1B2B3B4B5B6',
    'C1C2C3C4C5C6',
    'D1D2D3D4D5D6',
    'E1E2E3E4E5E6',
    'F1F2F3F4F5F6',
    '0123456789AB',
    '9876543210AB',
    '112233445566',
    '142857142857',
    '369258147369',
    'F0E1D2C3B4A5',
    'A5A4A3A2A1A0',
    'B5B4B3B2B1B0',
    'C5C4C3C2C1C0',
    'D5D4D3D2D1D0',
    'E5E4E3E2E1E0',
    'F5F4F3F2F1F0',
    '5A3F1B2C4D6E',
    'B2C3D4E5F601',
    'A0A1A2A3A4A5',
  ];

  final Set<String> _user = {};
  bool _loaded = false;

  bool get loaded => _loaded;

  Set<String> get userKeys => Set.unmodifiable(_user);

  List<Uint8List> get effectiveKeys {
    final keys = <String>{...bundledHex.map((k) => k.toUpperCase()), ..._user};
    return keys.map(hexToBytes).toList();
  }

  int get totalCount => {...bundledHex, ..._user}.length;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_prefsKey) ?? const [];
    _user
      ..clear()
      ..addAll(stored.map((k) => k.trim().toUpperCase()).where((k) => k.length == 12));
    _loaded = true;
    notifyListeners();
  }

  Future<void> addKey(String hex) async {
    final clean = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toUpperCase();
    if (clean.length != 12) throw const FormatException('Key must be 12 hex digits');
    _user.add(clean);
    await _persist();
    notifyListeners();
  }

  Future<void> addKeys(Iterable<Uint8List> keys) async {
    for (final key in keys) {
      _user.add(bytesToHexUpper(key));
    }
    await _persist();
    notifyListeners();
  }

  Future<void> removeKey(String hex) async {
    _user.remove(hex.toUpperCase());
    await _persist();
    notifyListeners();
  }

  Future<int> importDictionary(String text) async {
    final parsed = DumpCodec.parseKeyDictionary(text);
    _user.addAll(parsed.map(bytesToHexUpper));
    await _persist();
    notifyListeners();
    return parsed.length;
  }

  String exportDictionary() => DumpCodec.encodeKeyDictionary(effectiveKeys);

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, _user.toList()..sort());
  }

  String jsonSummary() => jsonEncode({'bundled': bundledHex.length, 'user': _user.length});
}
