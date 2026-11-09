import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../models/device_models.dart';
import '../models/dump.dart';
import '../protocol/ble_transport.dart';
import '../protocol/byte_utils.dart';
import '../protocol/client.dart';
import '../protocol/commands.dart';
import '../protocol/key_recovery.dart';
import '../protocol/tag_types.dart';
import '../protocol/transport.dart';
import 'ble_scanner.dart';

enum LinkState { disconnected, connecting, connected }

class LogEntry {
  LogEntry(this.message, {this.isError = false, this.isTx = false});
  final String message;
  final bool isError;
  final bool isTx;
  final DateTime at = DateTime.now();
}

class DeviceSession extends ChangeNotifier {
  ChameleonClient? _client;
  ChameleonTransport? _transport;
  LinkState _state = LinkState.disconnected;
  bool _busy = false;
  String _busyLabel = '';
  double? _progress;
  String? _lastError;
  String? _lastErrorDetail;
  bool _readerMode = false;
  DeviceVersion? _version;
  String? _chipId;
  String? _bleAddress;
  BatteryInfo? _battery;
  List<SlotInfo> _slots = const [];
  List<int> _capabilities = const [];
  final List<LogEntry> _logs = [];

  LinkState get state => _state;
  bool get isConnected => _state == LinkState.connected;
  bool get isConnecting => _state == LinkState.connecting;
  bool get isBusy => _busy;
  String get busyLabel => _busyLabel;
  double? get progress => _progress;
  String? get lastError => _lastError;
  String? get lastErrorDetail => _lastErrorDetail;
  bool get readerMode => _readerMode;
  DeviceVersion? get version => _version;
  String? get chipId => _chipId;
  String? get bleAddress => _bleAddress;
  BatteryInfo? get battery => _battery;
  List<SlotInfo> get slots => _slots;
  List<int> get capabilities => _capabilities;
  List<LogEntry> get logs => List.unmodifiable(_logs);
  SlotInfo? get activeSlot {
    for (final slot in _slots) {
      if (slot.active) return slot;
    }
    return _slots.isEmpty ? null : _slots.first;
  }

  ChameleonClient? get client => _client;

  void clearError() {
    _lastError = null;
    _lastErrorDetail = null;
    notifyListeners();
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  void _log(String message, {bool isError = false, bool isTx = false}) {
    _logs.add(LogEntry(message, isError: isError, isTx: isTx));
    if (_logs.length > 400) _logs.removeAt(0);
  }

  Future<bool> connectBle(BleScanEntry entry) =>
      connectTransport(BleTransport(entry.device), label: '${entry.name} (${entry.id})');

  /// Connects a byte-stream transport and performs the initial device refresh.
  /// BLE uses this today; a USB serial transport can plug in without changes.
  Future<bool> connectTransport(ChameleonTransport transport, {String? label}) async {
    await _disconnectInternal();
    _state = LinkState.connecting;
    notifyListeners();
    try {
      await transport.connect();
      final client = ChameleonClient(transport, log: (line) {
        _log(line, isTx: line.startsWith('TX'));
      });
      client.open();
      _client = client;
      _transport = transport;
      _state = LinkState.connected;
      transport.disconnected.listen((_) => _handleDisconnect());
      _log('Connected to ${label ?? transport.description}');
      notifyListeners();
      await refreshAll();
      return true;
    } catch (error) {
      await transport.disconnect();
      _state = LinkState.disconnected;
      _lastError = _friendly(error);
      _lastErrorDetail = error.toString();
      _log('Connection failed: $error', isError: true);
      notifyListeners();
      return false;
    }
  }

  Future<void> disconnect() async {
    await _disconnectInternal();
    _state = LinkState.disconnected;
    notifyListeners();
  }

  Future<void> _disconnectInternal() async {
    try {
      await _client?.close();
    } catch (_) {}
    try {
      await _transport?.disconnect();
    } catch (_) {}
    _client = null;
    _transport = null;
    _version = null;
    _chipId = null;
    _bleAddress = null;
    _battery = null;
    _slots = const [];
    _capabilities = const [];
    _readerMode = false;
    _progress = null;
    _busy = false;
  }

  void _handleDisconnect() {
    _client = null;
    _transport = null;
    _state = LinkState.disconnected;
    _log('Device disconnected', isError: true);
    notifyListeners();
  }

  Future<void> refreshAll() async {
    final client = _client;
    if (client == null) return;
    try {
      _version = await client.getVersion();
    } catch (error) {
      _log('Version query failed: $error', isError: true);
    }
    try {
      _chipId = await client.getChipId();
    } catch (_) {}
    try {
      _bleAddress = await client.getBleAddress();
    } catch (_) {}
    try {
      _capabilities = await client.getCapabilities();
    } catch (_) {}
    try {
      _readerMode = await client.getReaderMode();
    } catch (_) {}
    try {
      _battery = await client.getBattery();
    } catch (_) {}
    try {
      _slots = await client.getSlots();
    } catch (error) {
      _log('Slot query failed: $error', isError: true);
    }
    notifyListeners();
  }

  Future<void> refreshSlots() async {
    final client = _client;
    if (client == null) return;
    _slots = await client.getSlots();
    notifyListeners();
  }

  Future<void> refreshBattery() async {
    final client = _client;
    if (client == null) return;
    _battery = await client.getBattery();
    notifyListeners();
  }

  Future<void> setReaderMode(bool reader) async {
    final client = _client;
    if (client == null) throw ChameleonException('Not connected');
    await client.setReaderMode(reader);
    _readerMode = reader;
    notifyListeners();
  }

  Future<void> setActiveSlot(int firmwareSlot) async {
    final client = _client;
    if (client == null) throw ChameleonException('Not connected');
    await client.setActiveSlot(firmwareSlot);
    _slots = [
      for (final slot in _slots) slot.copyWith(active: slot.index == firmwareSlot),
    ];
    notifyListeners();
  }

  Future<T?> guard<T>(String label, Future<T> Function() action) async {
    if (_busy) return null;
    _busy = true;
    _busyLabel = label;
    _progress = null;
    _lastError = null;
    _lastErrorDetail = null;
    notifyListeners();
    try {
      return await action();
    } catch (error) {
      _lastError = _friendly(error);
      _lastErrorDetail = error.toString();
      _log('$label: ${_friendly(error)}', isError: true);
      return null;
    } finally {
      _busy = false;
      _busyLabel = '';
      _progress = null;
      notifyListeners();
    }
  }

  void reportProgress(String label, [double? value]) => _setProgress(label, value);

  void _setProgress(String label, [double? value]) {
    _busyLabel = label;
    _progress = value;
    notifyListeners();
  }

  String _friendly(Object error) {
    if (error is ChameleonException) return error.message;
    if (error is TimeoutException) return 'Request timed out';
    if (error is TransportException) return error.message;
    return error.toString().replaceFirst('Exception: ', '');
  }

  // ---------------------------------------------------------------------------
  // Slot operations
  // ---------------------------------------------------------------------------

  Future<void> configureSlot({
    required int firmwareSlot,
    required TagType type,
    String? nick,
    bool activate = false,
    bool enable = true,
    bool initialize = true,
  }) async {
    final client = _client;
    if (client == null) throw ChameleonException('Not connected');
    await client.setSlotType(firmwareSlot, type);
    if (initialize) await client.initSlot(firmwareSlot, type);
    if (enable) await client.setSlotEnabled(firmwareSlot, type.sense, true);
    if (nick != null && nick.isNotEmpty) {
      await client.setSlotNick(firmwareSlot, type.sense, nick);
    }
    if (activate) await client.setActiveSlot(firmwareSlot);
    await client.saveSlot();
    await refreshSlots();
  }

  Future<void> enableSlot(int firmwareSlot, TagSense sense, bool enabled) async {
    final client = _client;
    if (client == null) throw ChameleonException('Not connected');
    await client.setSlotEnabled(firmwareSlot, sense, enabled);
    await client.saveSlot();
    await refreshSlots();
  }

  Future<void> renameSlot(int firmwareSlot, TagSense sense, String nick) async {
    final client = _client;
    if (client == null) throw ChameleonException('Not connected');
    if (nick.isEmpty) {
      await client.deleteSlotNick(firmwareSlot, sense);
    } else {
      await client.setSlotNick(firmwareSlot, sense, nick);
    }
    await client.saveSlot();
    await refreshSlots();
  }

  Future<void> removeSlotSense(int firmwareSlot, TagSense sense) async {
    final client = _client;
    if (client == null) throw ChameleonException('Not connected');
    await client.deleteSlotSense(firmwareSlot, sense);
    await client.saveSlot();
    await refreshSlots();
  }

  Future<void> saveSlots() async {
    final client = _client;
    if (client == null) throw ChameleonException('Not connected');
    await client.saveSlot();
  }

  // ---------------------------------------------------------------------------
  // HF reading
  // ---------------------------------------------------------------------------

  Future<HfScanResult?> scanHf() async {
    final client = _client;
    if (client == null) throw ChameleonException('Not connected');
    final tags = await client.scanHf();
    if (tags.isEmpty) return null;
    final coll = tags.first;
    final classic = await client.mf1Supported();
    int? prng;
    if (classic) {
      try {
        prng = await client.mf1PrngLevel();
      } catch (_) {}
    }
    return HfScanResult(coll: coll, isClassic: classic, prngLevel: prng);
  }


  // ---------------------------------------------------------------------------
  // MIFARE Classic key recovery
  // ---------------------------------------------------------------------------

  Future<List<Uint8List>> recoverKeysFromDetectionLog(
    List<Mf1DetectionRecord> records, {
    void Function(String label, double? progress)? onProgress,
  }) async {
    if (!KeyRecovery.init()) {
      throw ChameleonException('Native recovery library is unavailable on this build');
    }
    final groups = <String, List<Mf1DetectionRecord>>{};
    for (final record in records) {
      final key = '${record.uidInt.toRadixString(16)}-${record.block}-${record.keyType}';
      groups.putIfAbsent(key, () => []).add(record);
    }

    final recovered = <String, Uint8List>{};
    var groupIndex = 0;
    for (final group in groups.values) {
      groupIndex++;
      onProgress?.call(
        'Recovering key group $groupIndex of ${groups.length}',
        groups.isEmpty ? null : groupIndex / groups.length,
      );
      if (group.length < 2) continue;
      var attempts = 0;
      for (var i = 0; i < group.length && attempts < 24; i++) {
        for (var j = i + 1; j < group.length && attempts < 24; j++, attempts++) {
          final a = group[i];
          final b = group[j];
          if (a.ntInt == b.ntInt) continue;
          final keyInt = KeyRecovery.mfkey32v2(
            uid: a.uidInt,
            nt0: a.ntInt,
            nr0Enc: a.nrInt,
            ar0Enc: a.arInt,
            nt1: b.ntInt,
            nr1Enc: b.nrInt,
            ar1Enc: b.arInt,
          );
          if (keyInt != null) {
            final key = KeyRecovery.keyFromInt(keyInt);
            recovered[bytesToHexUpper(key)] = key;
          }
        }
      }
    }
    return recovered.values.toList();
  }

  Future<Uint8List?> recoverMf1Darkside({
    int block = 3,
    int keyType = MifareClassic.keyA,
    int maxAttempts = 8,
    void Function(String label, double? progress)? onProgress,
  }) async {
    final client = _client;
    if (client == null) throw ChameleonException('Not connected');
    if (!KeyRecovery.init()) {
      throw ChameleonException('Native recovery library is unavailable on this build');
    }
    final items = <Mf1DarksideData>[];
    var first = true;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      onProgress?.call('Darkside acquisition ${attempt + 1}/$maxAttempts', attempt / maxAttempts);
      final data = await client.mf1DarksideAcquire(
        blockTarget: block,
        typeTarget: keyType,
        firstRecover: first,
        syncMax: 30,
      );
      first = false;
      if (!data.ok) {
        if (data.status == Status.hfTagNo) continue;
        break;
      }
      if (data.par != 0) items.clear();
      items.add(data);
      final candidates = KeyRecovery.darkside(
        uid: data.uid,
        nt1: items.map((e) => e.nt1).toList(),
        ks1: items.map((e) => e.ks1).toList(),
        par: items.map((e) => e.par).toList(),
        nr: items.map((e) => e.nr).toList(),
        ar: items.map((e) => e.ar).toList(),
      );
      for (final candidate in candidates) {
        final key = KeyRecovery.keyFromInt(candidate);
        if (await client.mf1AuthBlock(block, keyType, key)) {
          return key;
        }
      }
    }
    return null;
  }

  Future<Uint8List?> recoverMf1Nested({
    required int knownBlock,
    required int knownKeyType,
    required Uint8List knownKey,
    required int targetBlock,
    required int targetKeyType,
    void Function(String label, double? progress)? onProgress,
  }) async {
    final client = _client;
    if (client == null) throw ChameleonException('Not connected');
    if (!KeyRecovery.init()) {
      throw ChameleonException('Native recovery library is unavailable on this build');
    }
    final prng = await client.mf1PrngLevel();
    onProgress?.call('Collecting nonces…', 0.2);
    if (prng == 2) {
      throw ChameleonException('Tag uses a hard PRNG; hardnested is not available');
    }

    List<int> candidates;
    if (prng == 0) {
      final data = await client.mf1StaticNestedAcquire(
        blockKnown: knownBlock,
        typeKnown: knownKeyType,
        keyKnown: knownKey,
        blockTarget: targetBlock,
        typeTarget: targetKeyType,
      );
      candidates = KeyRecovery.staticNested(
        uid: data.uid,
        targetKeyType: targetKeyType,
        nt: data.nonces.map((e) => e.nt).toList(),
        ntEnc: data.nonces.map((e) => e.ntEnc).toList(),
      );
    } else {
      final distance = await client.mf1NtDistance(knownBlock, knownKeyType, knownKey);
      final data = await client.mf1NestedAcquire(
        blockKnown: knownBlock,
        typeKnown: knownKeyType,
        keyKnown: knownKey,
        blockTarget: targetBlock,
        typeTarget: targetKeyType,
      );
      candidates = KeyRecovery.nested(
        uid: distance.$1,
        distance: distance.$2,
        nt: data.nonces.map((e) => e.nt).toList(),
        ntEnc: data.nonces.map((e) => e.ntEnc).toList(),
        parity: data.nonces.map((e) => e.par).toList(),
      );
    }

    onProgress?.call('Verifying candidates…', 0.8);
    for (final candidate in candidates) {
      final key = KeyRecovery.keyFromInt(candidate);
      if (await client.mf1AuthBlock(targetBlock, targetKeyType, key)) {
        return key;
      }
    }
    return null;
  }

  Future<Map<int, Uint8List>> findMf1Keys({
    required TagType type,
    required List<Uint8List> keys,
    void Function(int attempted, int found)? onProgress,
  }) async {
    final client = _client;
    if (client == null) throw ChameleonException('Not connected');
    final sectors = MifareClassic.sectorCountForType(type);
    final positions = sectors * 2;
    final found = <int, Uint8List>{};
    final unique = <String, Uint8List>{};
    for (final key in keys) {
      if (key.length == 6) unique[bytesToHexUpper(key)] = key;
    }
    final keyList = unique.values.toList();
    if (keyList.isEmpty) return found;

    final mask = Uint8List(10); // bit 1 = skip; start with nothing skipped
    const batchSize = 24;
    for (var batchStart = 0; batchStart < keyList.length; batchStart += batchSize) {
      final end = (batchStart + batchSize < keyList.length) ? batchStart + batchSize : keyList.length;
      final batch = keyList.sublist(batchStart, end);
      final result = await client.checkKeysOfSectors(mask: mask, keys: batch);

      var skipped = 0;
      for (var i = 0; i < positions; i++) {
        final byte = mask[i >> 3];
        if (((byte >> (7 - (i & 7))) & 1) == 1) skipped++;
      }
      if (skipped >= positions) break;

      final newFound = result.keys;
      for (final entry in newFound.entries) {
        if (entry.key < positions) {
          found[entry.key] = entry.value;
          mask[entry.key >> 3] |= 1 << (7 - (entry.key & 7));
        }
      }
      onProgress?.call(positions - skipped, found.length);
      if (found.length >= positions) break;
    }
    return found;
  }

  Future<DumpRecord> readMf1Dump({
    required TagType type,
    required List<Uint8List> keys,
    required String name,
    void Function(String label, double? progress)? onProgress,
  }) async {
    final client = _client;
    if (client == null) throw ChameleonException('Not connected');
    final sectors = MifareClassic.sectorCountForType(type);
    final blockCount = type.mf1Blocks ?? (sectors * 4);

    onProgress?.call('Finding keys…', null);
    final found = await findMf1Keys(
      type: type,
      keys: keys,
      onProgress: (attempted, foundCount) => onProgress?.call(
        'Finding keys… ($foundCount/${sectors * 2})',
        attempted == 0 ? null : (foundCount / (sectors * 2)).clamp(0, 1),
      ),
    );

    final missing = <int>[];
    for (var sector = 0; sector < sectors; sector++) {
      if (!found.containsKey(sector * 2) && !found.containsKey(sector * 2 + 1)) {
        missing.add(sector);
      }
    }
    if (missing.isNotEmpty) {
      throw ChameleonException(
        'No key for sector${missing.length > 1 ? 's' : ''} ${missing.join(', ')}. '
        'Add more keys or run a key recovery attack.',
      );
    }

    final data = Uint8List(blockCount * 16);
    var done = 0;
    for (var sector = 0; sector < sectors; sector++) {
      final keyA = found[sector * 2];
      final keyB = found[sector * 2 + 1];
      final useA = keyA != null;
      final key = useA ? keyA : keyB!;
      final keyType = useA ? MifareClassic.keyA : MifareClassic.keyB;
      final first = MifareClassic.firstBlockOfSector(sector);
      final count = MifareClassic.blockCountOfSector(sector);

      for (var i = 0; i < count; i++) {
        final block = first + i;
        Uint8List blockData;
        try {
          blockData = await client.mf1ReadBlock(block, keyType, key);
        } catch (_) {
          // Fall back to the other key for this sector.
          final alternateKey = useA ? keyB : keyA;
          final alternateType = useA ? MifareClassic.keyB : MifareClassic.keyA;
          if (alternateKey == null) rethrow;
          blockData = await client.mf1ReadBlock(block, alternateType, alternateKey);
        }
        if (i == count - 1) {
          if (keyA != null) blockData.setRange(0, 6, keyA);
          if (keyB != null) blockData.setRange(10, 16, keyB);
        }
        data.setRange(block * 16, block * 16 + 16, blockData);
        done++;
        onProgress?.call(
          'Reading block $done of $blockCount',
          blockCount == 0 ? null : done / blockCount,
        );
      }
    }

    final keyMap = Mf1Keys();
    for (var sector = 0; sector < sectors; sector++) {
      if (found[sector * 2] != null) keyMap.keyA[sector] = found[sector * 2]!;
      if (found[sector * 2 + 1] != null) keyMap.keyB[sector] = found[sector * 2 + 1]!;
    }

    return DumpRecord(
      id: '${DateTime.now().microsecondsSinceEpoch}-${data.length}',
      name: name,
      kind: DumpKind.mf1,
      tagTypeId: type.id,
      data: data,
      createdAt: DateTime.now(),
      keys: keyMap,
      source: 'tag',
    );
  }

  Future<int> writeMf1DumpToTag(DumpRecord dump, {bool cloneAccessBits = false}) async {
    final client = _client;
    if (client == null) throw ChameleonException('Not connected');
    if (!dump.isMf1) throw ChameleonException('Not a MIFARE Classic dump');
    final type = dump.tagType;
    final sectors = MifareClassic.sectorCountForType(type);
    var written = 0;
    for (var sector = 0; sector < sectors; sector++) {
      final keyA = dump.keys.keyA[sector];
      final keyB = dump.keys.keyB[sector];
      if (keyA == null && keyB == null) {
        throw ChameleonException('No key for sector $sector');
      }
      final key = keyA ?? keyB!;
      final keyType = keyA != null ? MifareClassic.keyA : MifareClassic.keyB;
      final first = MifareClassic.firstBlockOfSector(sector);
      final count = MifareClassic.blockCountOfSector(sector);

      for (var i = 0; i < count; i++) {
        final block = first + i;
        var blockData = Uint8List.fromList(dump.data.sublist(block * 16, block * 16 + 16));
        if (i == count - 1 && !cloneAccessBits) {
          blockData = Uint8List.fromList([
            ...blockData.sublist(0, 6),
            0xff,
            0x07,
            0x80,
            ...blockData.sublist(9, 16),
          ]);
        }
        final ok = await client.mf1WriteBlock(block, keyType, key, blockData);
        if (ok) written++;
      }
    }
    return written;
  }

  Future<int> writeMf1DumpToSlot(
    DumpRecord dump, {
    required int firmwareSlot,
    bool activate = true,
  }) async {
    final client = _client;
    if (client == null) throw ChameleonException('Not connected');
    if (!dump.isMf1) throw ChameleonException('Not a MIFARE Classic dump');
    final type = dump.tagType;
    await client.setSlotType(firmwareSlot, type);
    await client.initSlot(firmwareSlot, type);
    await client.setSlotEnabled(firmwareSlot, TagSense.hf, true);

    const chunkBlocks = 31; // 496 bytes, within the 512-byte frame limit
    var offset = 0;
    while (offset < dump.data.length) {
      final end = (offset + chunkBlocks * 16 < dump.data.length)
          ? offset + chunkBlocks * 16
          : dump.data.length;
      await client.mf1WriteEmuBlocks(offset ~/ 16, Uint8List.fromList(dump.data.sublist(offset, end)));
      offset = end;
    }

    final antiColl = _antiCollFromBlock0(dump.data, type);
    if (antiColl != null) {
      await client.setAntiCollData(antiColl);
    }
    if (activate) await client.setActiveSlot(firmwareSlot);
    await client.saveSlot();
    await refreshSlots();
    return dump.data.length;
  }

  AntiCollData? _antiCollFromBlock0(Uint8List data, TagType type) {
    if (data.length < 16) return null;
    final block0 = data.sublist(0, 16);
    Uint8List uid;
    int sak;
    Uint8List atqa;
    if (type == TagTypes.mifare4096 || type == TagTypes.mifareMini) {
      // 4-byte UID layout: UID0..3, BCC, SAK, ATQA.
      uid = Uint8List.fromList(block0.sublist(0, 4));
      sak = block0[5];
      atqa = Uint8List.fromList(block0.sublist(6, 8));
    } else {
      uid = Uint8List.fromList(block0.sublist(0, 4));
      sak = block0[5];
      atqa = Uint8List.fromList(block0.sublist(6, 8));
    }
    final computedBcc = uid.fold<int>(0, (a, b) => a ^ b);
    if (block0[4] != computedBcc) return null;
    return AntiCollData(uid: uid, atqa: atqa, sak: sak, ats: Uint8List(0));
  }

  // ---------------------------------------------------------------------------
  // Ultralight / NTAG
  // ---------------------------------------------------------------------------

  Future<DumpRecord> readMfuDump({
    required TagType type,
    required String name,
    Uint8List? ulcKey,
    void Function(String label, double? progress)? onProgress,
  }) async {
    final client = _client;
    if (client == null) throw ChameleonException('Not connected');
    final pages = type.mfuPages ?? 45;
    final data = Uint8List(pages * 4);
    var done = 0;

    if (type == TagTypes.mf0icu2 && ulcKey != null) {
      if (!await client.ulcAuth(ulcKey)) {
        throw ChameleonException('Ultralight C authentication failed');
      }
      for (var page = 0; page < pages; page += 4) {
        final count = (page + 4 <= pages) ? 4 : pages - page;
        final chunk = await client.ulcRead(ulcKey, page, count);
        data.setRange(page * 4, page * 4 + chunk.length, chunk);
        done += chunk.length ~/ 4;
        onProgress?.call('Reading page $done of $pages', done / pages);
      }
    } else {
      for (var page = 0; page < pages; page += 4) {
        Uint8List chunk;
        try {
          chunk = await client.hf14aRaw(
            data: [0x30, page],
            appendCrc: true,
            autoSelect: true,
            checkCrc: true,
            responseTimeoutMs: 300,
          );
        } catch (_) {
          break;
        }
        final end = ((page + 4) * 4).clamp(0, data.length);
        final needed = end - page * 4;
        if (chunk.length < needed) break;
        data.setRange(page * 4, end, chunk.sublist(0, needed));
        done += needed ~/ 4;
        onProgress?.call('Reading page $done of $pages', done / pages);
      }
    }

    Uint8List? version;
    Uint8List? signature;
    try {
      final v = await client.hf14aRaw(
        data: [0x60],
        appendCrc: true,
        autoSelect: true,
        checkCrc: true,
        responseTimeoutMs: 300,
      );
      if (v.length >= 8) version = Uint8List.fromList(v.sublist(0, 8));
    } catch (_) {}
    try {
      final s = await client.hf14aRaw(
        data: [0x3c, 0x00],
        appendCrc: true,
        autoSelect: true,
        checkCrc: true,
        responseTimeoutMs: 300,
      );
      if (s.length >= 32) signature = Uint8List.fromList(s.sublist(0, 32));
    } catch (_) {}

    return DumpRecord(
      id: '${DateTime.now().microsecondsSinceEpoch}-${data.length}',
      name: name,
      kind: DumpKind.mfu,
      tagTypeId: type.id,
      data: data,
      createdAt: DateTime.now(),
      source: 'tag',
      version: version,
      signature: signature,
    );
  }

  Future<int> writeMfuDumpToTag(DumpRecord dump, {bool writeUidPages = false}) async {
    final client = _client;
    if (client == null) throw ChameleonException('Not connected');
    if (!dump.isMfu) throw ChameleonException('Not an Ultralight dump');
    final pages = dump.data.length ~/ 4;
    var written = 0;
    for (var page = writeUidPages ? 0 : 4; page < pages; page++) {
      final pageData = dump.data.sublist(page * 4, page * 4 + 4);
      try {
        final response = await client.hf14aRaw(
          data: [0xa2, page, ...pageData],
          appendCrc: true,
          autoSelect: true,
          checkCrc: true,
          responseTimeoutMs: 500,
        );
        if (response.isNotEmpty) written++;
      } catch (_) {
        // Locked or protected page; keep going and report the count.
      }
    }
    return written;
  }

  Future<int> writeMfuDumpToSlot(
    DumpRecord dump, {
    required int firmwareSlot,
    bool activate = true,
  }) async {
    final client = _client;
    if (client == null) throw ChameleonException('Not connected');
    if (!dump.isMfu) throw ChameleonException('Not an Ultralight dump');
    final type = dump.tagType;
    final pages = dump.data.length ~/ 4;
    await client.setSlotType(firmwareSlot, type);
    await client.initSlot(firmwareSlot, type);
    await client.setSlotEnabled(firmwareSlot, TagSense.hf, true);

    const chunkPages = 32;
    for (var page = 0; page < pages; page += chunkPages) {
      final end = (page + chunkPages < pages) ? page + chunkPages : pages;
      await client.mfuWriteEmuPages(page, Uint8List.fromList(dump.data.sublist(page * 4, end * 4)));
    }
    if (dump.version != null && dump.version!.length == 8) {
      try {
        await client.mfuSetVersion(dump.version!);
      } catch (_) {}
    }
    if (dump.signature != null && dump.signature!.length == 32) {
      try {
        await client.mfuSetSignature(dump.signature!);
      } catch (_) {}
    }

    final antiColl = _antiCollFromMfuPages(dump.data);
    if (antiColl != null) await client.setAntiCollData(antiColl);
    if (activate) await client.setActiveSlot(firmwareSlot);
    await client.saveSlot();
    await refreshSlots();
    return dump.data.length;
  }

  AntiCollData? _antiCollFromMfuPages(Uint8List data) {
    if (data.length < 16) return null;
    final uid = Uint8List.fromList([...data.sublist(0, 3), ...data.sublist(4, 8)]);
    return AntiCollData(
      uid: uid,
      atqa: Uint8List.fromList([0x44, 0x00]),
      sak: 0x00,
      ats: Uint8List(0),
    );
  }

  Future<DumpRecord> readMf1EmulatorDump({required String name}) async {
    final client = _client;
    if (client == null) throw ChameleonException('Not connected');
    final slot = activeSlot;
    if (slot == null || !slot.hfType.isMifareClassic) {
      throw ChameleonException('Active slot is not a MIFARE Classic slot');
    }
    final type = slot.hfType;
    final blocks = type.mf1Blocks!;
    final data = BytesBuilder();
    for (var block = 0; block < blocks; block += 32) {
      final count = (block + 32 < blocks) ? 32 : blocks - block;
      data.add(await client.mf1ReadEmuBlocks(block, count));
      _setProgress('Reading emulator block $block of $blocks', block / blocks);
    }
    return DumpRecord(
      id: '${DateTime.now().microsecondsSinceEpoch}-${data.length}',
      name: name,
      kind: DumpKind.mf1,
      tagTypeId: type.id,
      data: data.toBytes(),
      createdAt: DateTime.now(),
      source: 'emulator',
    );
  }

  Future<DumpRecord> readMfuEmulatorDump({required String name}) async {
    final client = _client;
    if (client == null) throw ChameleonException('Not connected');
    final slot = activeSlot;
    if (slot == null || !slot.hfType.isUltralight) {
      throw ChameleonException('Active slot is not an Ultralight/NTAG slot');
    }
    final pages = await client.mfuEmuPageCount();
    final data = BytesBuilder();
    for (var page = 0; page < pages; page += 32) {
      final count = (page + 32 < pages) ? 32 : pages - page;
      data.add(await client.mfuReadEmuPages(page, count));
      _setProgress('Reading emulator page $page of $pages', page / pages);
    }
    Uint8List? version;
    Uint8List? signature;
    try {
      version = await client.mfuGetVersion();
    } catch (_) {}
    try {
      signature = await client.mfuGetSignature();
    } catch (_) {}
    return DumpRecord(
      id: '${DateTime.now().microsecondsSinceEpoch}-${data.length}',
      name: name,
      kind: DumpKind.mfu,
      tagTypeId: slot.hfType.id,
      data: data.toBytes(),
      createdAt: DateTime.now(),
      source: 'emulator',
      version: version,
      signature: signature,
    );
  }

  // ---------------------------------------------------------------------------
  // LF
  // ---------------------------------------------------------------------------

  Future<LfScanResult?> scanLf(TagType type) async {
    final client = _client;
    if (client == null) throw ChameleonException('Not connected');
    return client.scanLf(type);
  }

  Future<void> writeLfToT55(TagType type, Uint8List id) async {
    final client = _client;
    if (client == null) throw ChameleonException('Not connected');
    await client.lfWriteToT55xx(type, id);
  }

  Future<int> writeLfToSlot(LfScanResult tag, {required int firmwareSlot}) async {
    final client = _client;
    if (client == null) throw ChameleonException('Not connected');
    final type = tag.type;
    await client.setSlotType(firmwareSlot, type);
    await client.initSlot(firmwareSlot, type);
    await client.setSlotEnabled(firmwareSlot, TagSense.lf, true);
    await client.setActiveSlot(firmwareSlot);
    await client.setLfEmuId(type, tag.raw);
    await client.saveSlot();
    await refreshSlots();
    return tag.raw.length;
  }

  Future<int> writeLfDumpToSlot(DumpRecord dump, {required int firmwareSlot}) async {
    final client = _client;
    if (client == null) throw ChameleonException('Not connected');
    if (!dump.isLf) throw ChameleonException('Not an LF dump');
    final type = dump.tagType;
    await client.setSlotType(firmwareSlot, type);
    await client.initSlot(firmwareSlot, type);
    await client.setSlotEnabled(firmwareSlot, TagSense.lf, true);
    await client.setActiveSlot(firmwareSlot);
    await client.setLfEmuId(type, dump.data);
    await client.saveSlot();
    await refreshSlots();
    return dump.data.length;
  }

  Future<Uint8List?> readLfEmulatorId(TagType type) async {
    final client = _client;
    if (client == null) throw ChameleonException('Not connected');
    return client.getLfEmuId(type);
  }

  Future<void> setLfEmulatorId(TagType type, Uint8List id) async {
    final client = _client;
    if (client == null) throw ChameleonException('Not connected');
    await client.setLfEmuId(type, id);
    await client.saveSlot();
  }
}
