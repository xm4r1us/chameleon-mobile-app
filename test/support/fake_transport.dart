import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:chameleon_cli/protocol/byte_utils.dart';
import 'package:chameleon_cli/protocol/commands.dart';
import 'package:chameleon_cli/protocol/frame.dart';
import 'package:chameleon_cli/protocol/tag_types.dart';
import 'package:chameleon_cli/protocol/transport.dart';

/// Simulated Chameleon Ultra used only by tests.
///
/// It speaks the real frame protocol so the client and decoder are exercised
/// end-to-end without hardware.
class FakeTransport implements ChameleonTransport {
  FakeTransport() {
    _reset();
  }

  final StreamController<Uint8List> _incoming = StreamController<Uint8List>.broadcast();
  final FrameDecoder _decoder = FrameDecoder();
  bool _connected = false;
  bool _readerMode = false;
  int _activeSlot = 0;
  int _animation = 0;
  final int _battery = 87;
  int _sleepTimeout = 15;
  int _longPressThreshold = 800;
  bool _blePairing = false;
  String _bleKey = '123456';
  bool _detection = false;
  int _prng = 1;
  int _writeMode = 0;
  bool _fieldOffReset = false;

  final List<TagType> _hfTypes = List<TagType>.filled(8, TagTypes.undefined);
  final List<TagType> _lfTypes = List<TagType>.filled(8, TagTypes.undefined);
  final List<bool> _hfEnabled = List<bool>.filled(8, false);
  final List<bool> _lfEnabled = List<bool>.filled(8, false);
  final List<String> _hfNicks = List<String>.filled(8, '');
  final List<String> _lfNicks = List<String>.filled(8, '');

  final Map<int, Uint8List> _mf1Data = {};
  Uint8List _tagMf1 = Uint8List(0);
  final Map<int, Uint8List> _mfuData = {};

  static final Uint8List _defaultKey = Uint8List.fromList([0xff, 0xff, 0xff, 0xff, 0xff, 0xff]);
  static final Uint8List _uid = Uint8List.fromList([0xde, 0xad, 0xbe, 0xef]);

  @override
  String get description => 'Test Chameleon';

  @override
  bool get isConnected => _connected;

  @override
  Stream<Uint8List> get incoming => _incoming.stream;

  @override
  Stream<void> get disconnected => const Stream.empty();

  @override
  Future<void> connect() async {
    _connected = true;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
  }

  @override
  Future<void> write(Uint8List data) async {
    if (!_connected) throw TransportException('Test link is not connected');
    for (final frame in _decoder.add(data)) {
      await Future<void>.delayed(const Duration(milliseconds: 15));
      final response = _handle(frame);
      if (response != null) _incoming.add(response.encode());
    }
  }

  void _reset() {
    _hfTypes[0] = TagTypes.mifare1024;
    _hfEnabled[0] = true;
    _hfNicks[0] = 'Test Classic 1K';
    _lfTypes[1] = TagTypes.em410x;
    _lfEnabled[1] = true;
    _lfNicks[1] = 'Test EM410x';
    _activeSlot = 0;
    _mf1Data[0] = _makeClassicDump(64);
    _tagMf1 = _makeClassicDump(256);
    _mfuData[0] = _makeNtagDump(45);
  }

  Uint8List _makeClassicDump(int blocks) {
    final data = Uint8List(blocks * 16);
    // Block 0: UID + BCC + SAK + ATQA.
    data.setRange(0, 4, _uid);
    data[4] = _uid[0] ^ _uid[1] ^ _uid[2] ^ _uid[3];
    data[5] = 0x08;
    data[6] = 0x04;
    data[7] = 0x00;
    final sectors = MifareClassic.sectorCountForBlocks(blocks);
    for (var sector = 0; sector < sectors; sector++) {
      final trailer = MifareClassic.trailerBlockOfSector(sector);
      if (trailer >= blocks) break;
      data.setRange(trailer * 16, trailer * 16 + 6, _defaultKey);
      data.setRange(trailer * 16 + 6, trailer * 16 + 9, [0xff, 0x07, 0x80]);
      data.setRange(trailer * 16 + 10, trailer * 16 + 16, _defaultKey);
    }
    // A little recognisable payload in block 1.
    data.setRange(16, 24, ascii.encode('CHAMELEO'));
    return data;
  }

  Uint8List _makeNtagDump(int pages) {
    final data = Uint8List(pages * 4);
    data.setRange(0, 4, _uid);
    data[4] = _uid[0] ^ _uid[1] ^ _uid[2] ^ _uid[3];
    data[5] = 0x00;
    data[6] = 0x00;
    data[7] = 0x00;
    data[8] = 0x01; // CC
    data[9] = 0x03;
    data[10] = 0x00;
    data[11] = 0x00;
    return data;
  }

  ChameleonFrame? _handle(ChameleonFrame request) {
    try {
      final data = _dispatch(request.command, request.data);
      return ChameleonFrame(request.command, data.$1, data.$2);
    } on _NoReply {
      return null;
    } catch (error) {
      return ChameleonFrame(request.command, Status.parErr, Uint8List(0));
    }
  }

  (int, Uint8List) _ok([List<int> data = const []]) =>
      (Status.success, Uint8List.fromList(data));

  (int, Uint8List) _hf([List<int> data = const []]) =>
      (Status.hfTagOk, Uint8List.fromList(data));

  (int, Uint8List) _lf([List<int> data = const []]) =>
      (Status.lfTagOk, Uint8List.fromList(data));

  (int, Uint8List) _err(int status) => (status, Uint8List(0));

  (int, Uint8List) _dispatch(int cmd, Uint8List d) {
    switch (cmd) {
      case Cmd.getAppVersion:
        return _ok([2, 1]);
      case Cmd.getGitVersion:
        return _ok(utf8.encode('v2.1.0-test'));
      case Cmd.getDeviceChipId:
        return _ok([0xde, 0xad, 0xbe, 0xef, 0x12, 0x34, 0x56, 0x78]);
      case Cmd.getDeviceAddress:
        return _ok([0xc0, 0xff, 0xee, 0x12, 0x34, 0x56]);
      case Cmd.getDeviceModel:
        return _ok([0]);
      case Cmd.getDeviceCapabilities:
        return _ok([
          for (final id in [1000, 1019, 1023, 1025, 2000, 2001, 2008, 2009, 2012, 4000, 4008, 4009, 4021, 4030, 5000, 5001])
            ...be16(id),
        ]);
      case Cmd.getDeviceMode:
        return _ok([_readerMode ? 1 : 0]);
      case Cmd.changeDeviceMode:
        if (d.isEmpty) return _err(Status.parErr);
        _readerMode = d[0] != 0;
        return _ok();
      case Cmd.getBatteryInfo:
        return _ok([(4100 >> 8) & 0xff, 4100 & 0xff, _battery]);
      case Cmd.getBatteryInfoEx:
        return _ok([(4100 >> 8) & 0xff, 4100 & 0xff, _battery, 3]);
      case Cmd.getSlotInfo:
        final out = <int>[];
        for (var i = 0; i < 8; i++) {
          out.addAll(be16(_hfTypes[i].id));
          out.addAll(be16(_lfTypes[i].id));
        }
        return _ok(out);
      case Cmd.getEnabledSlots:
        return _ok([
          for (var i = 0; i < 8; i++) ...[_hfEnabled[i] ? 1 : 0, _lfEnabled[i] ? 1 : 0],
        ]);
      case Cmd.getActiveSlot:
        return _ok([_activeSlot]);
      case Cmd.setActiveSlot:
        if (d.isEmpty || d[0] > 7) return _err(Status.parErr);
        _activeSlot = d[0];
        return _ok();
      case Cmd.getAllSlotNicks:
        final out = <int>[];
        for (var i = 0; i < 8; i++) {
          final hf = utf8.encode(_hfNicks[i]);
          final lf = utf8.encode(_lfNicks[i]);
          out.addAll([hf.length, ...hf, lf.length, ...lf]);
        }
        return _ok(out);
      case Cmd.setSlotTagType:
        if (d.length < 3 || d[0] > 7) return _err(Status.parErr);
        final type = TagTypes.byId(u16(d, 1));
        if (type.sense == TagSense.hf) {
          _hfTypes[d[0]] = type;
        } else {
          _lfTypes[d[0]] = type;
        }
        return _ok();
      case Cmd.setSlotDataDefault:
        if (d.length < 3 || d[0] > 7) return _err(Status.parErr);
        final type = TagTypes.byId(u16(d, 1));
        if (type.isMifareClassic) {
          _hfTypes[d[0]] = type;
          _mf1Data[d[0]] = _makeClassicDump(type.mf1Blocks!);
        } else if (type.isUltralight) {
          _hfTypes[d[0]] = type;
          _mfuData[d[0]] = _makeNtagDump(type.mfuPages!);
        } else {
          _lfTypes[d[0]] = type;
        }
        return _ok();
      case Cmd.setSlotEnable:
        if (d.length < 3 || d[0] > 7) return _err(Status.parErr);
        final sense = TagSense.fromValue(d[1]);
        if (sense == TagSense.hf) {
          _hfEnabled[d[0]] = d[2] != 0;
        } else if (sense == TagSense.lf) {
          _lfEnabled[d[0]] = d[2] != 0;
        } else {
          return _err(Status.parErr);
        }
        return _ok();
      case Cmd.setSlotTagNick:
        if (d.length < 2 || d[0] > 7) return _err(Status.parErr);
        final nick = utf8.decode(d.sublist(2), allowMalformed: true);
        if (d[1] == TagSense.hf.value) {
          _hfNicks[d[0]] = nick;
        } else {
          _lfNicks[d[0]] = nick;
        }
        return _ok();
      case Cmd.deleteSlotTagNick:
        if (d.length < 2 || d[0] > 7) return _err(Status.parErr);
        if (d[1] == TagSense.hf.value) {
          _hfNicks[d[0]] = '';
        } else {
          _lfNicks[d[0]] = '';
        }
        return _ok();
      case Cmd.deleteSlotSenseType:
        if (d.length < 2 || d[0] > 7) return _err(Status.parErr);
        if (d[1] == TagSense.hf.value) {
          _hfTypes[d[0]] = TagTypes.undefined;
          _hfEnabled[d[0]] = false;
        } else {
          _lfTypes[d[0]] = TagTypes.undefined;
          _lfEnabled[d[0]] = false;
        }
        return _ok();
      case Cmd.slotDataConfigSave:
        return _ok();

      case Cmd.hf14aScan:
        return _hf([4, ..._uid, 0x04, 0x00, 0x08, 0x00]);
      case Cmd.hf14aGetAntiCollData:
        return _ok([4, ..._uid, 0x04, 0x00, 0x08, 0x00]);
      case Cmd.hf14aSetAntiCollData:
        return _ok();
      case Cmd.mf1DetectSupport:
        return _hf([1]);
      case Cmd.mf1DetectPrng:
        return _hf([_prng]);
      case Cmd.mf1DetectNtDist:
        return _hf([...be32(0xdeadbeef), ...be32(160)]);
      case Cmd.mf1NestedAcquire:
        return _hf([]);
      case Cmd.mf1StaticNestedAcquire:
        return _hf([...be32(0xdeadbeef)]);
      case Cmd.mf1DarksideAcquire:
        return _err(Status.hfTagNo);

      case Cmd.mf1AuthOneKeyBlock:
        if (d.length < 8) return _err(Status.parErr);
        return _defaultKey.every((b) => b == 0xff) && _bytesEqual(d.sublist(2, 8), _defaultKey)
            ? _hf()
            : _err(Status.mfErrAuth);
      case Cmd.mf1ReadOneBlock:
        if (d.length < 8) return _err(Status.parErr);
        final block = d[1];
        final dump = _tagMf1;
        if ((block + 1) * 16 > dump.length) return _err(Status.hfTagNo);
        if (!_bytesEqual(d.sublist(2, 8), _defaultKey)) return _err(Status.mfErrAuth);
        return _hf(dump.sublist(block * 16, block * 16 + 16));
      case Cmd.mf1WriteOneBlock:
        if (d.length < 24) return _err(Status.parErr);
        final dump = _tagMf1;
        if ((d[1] + 1) * 16 > dump.length) return _err(Status.hfTagNo);
        if (!_bytesEqual(d.sublist(2, 8), _defaultKey)) return _err(Status.mfErrAuth);
        dump.setRange(d[1] * 16, d[1] * 16 + 16, d.sublist(8, 24));
        return _hf();
      case Cmd.mf1CheckKeysOfSectors:
        return _fchk(d);
      case Cmd.mf1CheckKeysOnBlock:
        if (d.length < 10) return _err(Status.parErr);
        final keyCount = d[2];
        final keys = <Uint8List>[];
        for (var i = 0; i < keyCount; i++) {
          keys.add(Uint8List.fromList(d.sublist(3 + i * 6, 9 + i * 6)));
        }
        final found = keys.any((k) => _bytesEqual(k, _defaultKey));
        return found ? (Status.hfTagOk, Uint8List.fromList([1, ..._defaultKey])) : _err(Status.mfErrAuth);
      case Cmd.hf14aRaw:
        return _raw(d);

      case Cmd.mf1WriteEmuBlockData:
        if (d.isEmpty) return _err(Status.parErr);
        final dump = _activeMf1;
        if (dump == null) return _err(Status.parErr);
        final start = d[0] * 16;
        final payload = d.sublist(1);
        if (start + payload.length > dump.length) return _err(Status.parErr);
        dump.setRange(start, start + payload.length, payload);
        return _ok();
      case Cmd.mf1ReadEmuBlockData:
        if (d.length < 2) return _err(Status.parErr);
        final dump = _activeMf1;
        if (dump == null) return _err(Status.parErr);
        final end = ((d[0] + d[1]) * 16).clamp(0, dump.length);
        return _ok(dump.sublist(d[0] * 16, end));
      case Cmd.mf1GetEmulatorConfig:
        return _ok([_detection ? 1 : 0, 0, 0, 0, _writeMode]);
      case Cmd.mf1GetFieldOffDoReset:
        return _ok([_fieldOffReset ? 1 : 0]);
      case Cmd.mf1SetFieldOffDoReset:
        _fieldOffReset = d.isNotEmpty && d[0] != 0;
        return _ok();
      case Cmd.mf1GetPrngType:
        return _ok([_prng]);
      case Cmd.mf1SetPrngType:
        if (d.isNotEmpty) _prng = d[0];
        return _ok();
      case Cmd.mf1SetDetectionEnable:
        _detection = d.isNotEmpty && d[0] != 0;
        return _ok();
      case Cmd.mf1GetDetectionCount:
        return _ok([0, 0, 0, 0]);
      case Cmd.mf1GetDetectionLog:
        return _ok();
      case Cmd.mf1SetGen1aMode:
      case Cmd.mf1SetGen2Mode:
      case Cmd.mf1SetBlockAntiCollMode:
        return _ok();
      case Cmd.mf1SetWriteMode:
        if (d.isNotEmpty) _writeMode = d[0];
        return _ok();

      case Cmd.mf0NtagGetPageCount:
        final type = _hfTypes[_activeSlot];
        return _ok([type.isUltralight ? type.mfuPages! : 45]);
      case Cmd.mf0NtagReadEmuPageData:
        if (d.length < 2) return _err(Status.parErr);
        final dump = _activeMfu;
        if (dump == null) return _err(Status.parErr);
        final start = (d[0] * 4).clamp(0, dump.length);
        final end = ((d[0] + d[1]) * 4).clamp(0, dump.length);
        return _ok(dump.sublist(start, end));
      case Cmd.mf0NtagWriteEmuPageData:
        if (d.length < 2) return _err(Status.parErr);
        final dump = _activeMfu;
        if (dump == null) return _err(Status.parErr);
        final start = d[0] * 4;
        final payload = d.sublist(2);
        if (start + payload.length > dump.length) return _err(Status.parErr);
        dump.setRange(start, start + payload.length, payload);
        return _ok();
      case Cmd.mf0NtagGetUidMagicMode:
        return _ok([0]);
      case Cmd.mf0NtagSetUidMagicMode:
        return _ok();
      case Cmd.mf0NtagGetVersionData:
        return _ok([0x00, 0x04, 0x04, 0x02, 0x01, 0x00, 0x0f, 0x03]);
      case Cmd.mf0NtagGetSignatureData:
        return _ok(List<int>.filled(32, 0));
      case Cmd.mf0NtagGetCounterData:
        return _ok([0, 0, 0, 0xbd]);
      case Cmd.mf0NtagSetCounterData:
        return _ok();
      case Cmd.mf0NtagGetWriteMode:
        return _ok([0]);
      case Cmd.mf0NtagSetWriteMode:
        return _ok();

      case Cmd.em410xScan:
        return _lf([0, 100, 0x12, 0x34, 0x56, 0x78, 0x90]);
      case Cmd.hidproxScan:
        return _lf([1, 0, 0, 0, 107, 0, 0, 0, 0, 0x27, 0x3c, 0, 0]);
      case Cmd.ioproxScan:
        return _lf([1, 12, 0x12, 0x34, 1, 2, 3, 4, 5, 6, 7, 8, 0, 0, 0, 0]);
      case Cmd.vikingScan:
        return _lf([0x12, 0x34, 0x56, 0x78]);
      case Cmd.pacScan:
        return _lf(ascii.encode('12345678'));
      case Cmd.jablotronScan:
        return _lf([1, 2, 3, 4, 5]);
      case Cmd.pyramidScan:
        return _lf(List<int>.filled(16, 0x5a));
      case Cmd.em410xWriteToT55xx:
      case Cmd.hidproxWriteToT55xx:
      case Cmd.ioproxWriteToT55xx:
      case Cmd.vikingWriteToT55xx:
      case Cmd.pacWriteToT55xx:
      case Cmd.jablotronWriteToT55xx:
      case Cmd.idteckWriteToT55xx:
        return _lf();
      case Cmd.em410xSetEmuId:
      case Cmd.hidproxSetEmuId:
      case Cmd.ioproxSetEmuId:
      case Cmd.vikingSetEmuId:
      case Cmd.pacSetEmuId:
      case Cmd.jablotronSetEmuId:
      case Cmd.idteckSetEmuId:
        return _ok();
      case Cmd.em410xGetEmuId:
        return _ok([0, 100, 0x12, 0x34, 0x56, 0x78, 0x90]);
      case Cmd.hidproxGetEmuId:
        return _ok([1, 0, 0, 0, 107, 0, 0, 0, 0, 0x27, 0x3c, 0, 0]);
      case Cmd.ioproxGetEmuId:
        return _ok([1, 12, 0x12, 0x34, 1, 2, 3, 4, 5, 6, 7, 8, 0, 0, 0, 0]);
      case Cmd.vikingGetEmuId:
        return _ok([0x12, 0x34, 0x56, 0x78]);
      case Cmd.pacGetEmuId:
        return _ok(ascii.encode('12345678'));
      case Cmd.jablotronGetEmuId:
        return _ok([1, 2, 3, 4, 5]);
      case Cmd.idteckGetEmuId:
        return _ok(List<int>.filled(8, 0x11));

      case Cmd.hf14a4ReaderApdu:
        return _ok([
          0x6f, 0x09, 0x84, 0x07, 0xa0, 0x00, 0x00, 0x00, 0x03, 0x10, 0x10, 0x90, 0x00,
        ]);

      case Cmd.getAnimationMode:
        return _ok([_animation]);
      case Cmd.setAnimationMode:
        if (d.isNotEmpty) _animation = d[0];
        return _ok();
      case Cmd.getSleepTimeout:
        return _ok([_sleepTimeout]);
      case Cmd.setSleepTimeout:
        if (d.isNotEmpty) _sleepTimeout = d[0];
        return _ok();
      case Cmd.getLongPressThreshold:
        return _ok(be16(_longPressThreshold));
      case Cmd.setLongPressThreshold:
        if (d.length >= 2) _longPressThreshold = u16(d);
        return _ok();
      case Cmd.getBlePairingKey:
        return _ok(ascii.encode(_bleKey));
      case Cmd.setBlePairingKey:
        _bleKey = ascii.decode(d, allowInvalid: true);
        return _ok();
      case Cmd.getBlePairingEnable:
        return _ok([_blePairing ? 1 : 0]);
      case Cmd.setBlePairingEnable:
        _blePairing = d.isNotEmpty && d[0] != 0;
        return _ok();
      case Cmd.deleteAllBleBonds:
        return _ok();
      case Cmd.getButtonPressConfig:
      case Cmd.getLongButtonPressConfig:
        return _ok([0]);
      case Cmd.setButtonPressConfig:
      case Cmd.setLongButtonPressConfig:
        return _ok();
      case Cmd.saveSettings:
      case Cmd.resetSettings:
        return _ok();
      case Cmd.getDeviceSettings:
        return _ok([7, _animation, 0, 0, 0, 0, _blePairing ? 1 : 0, ...ascii.encode(_bleKey), _sleepTimeout]);
      case Cmd.wipeFds:
        _reset();
        return _ok();
      case Cmd.enterBootloader:
        throw _NoReply();

      default:
        return _err(Status.invalidCmd);
    }
  }

  Uint8List? get _activeMf1 {
    final type = _hfTypes[_activeSlot];
    if (!type.isMifareClassic) return null;
    final existing = _mf1Data[_activeSlot];
    if (existing == null || existing.length != type.mf1Blocks! * 16) {
      final fresh = _makeClassicDump(type.mf1Blocks!);
      _mf1Data[_activeSlot] = fresh;
      return fresh;
    }
    return existing;
  }

  Uint8List? get _activeMfu {
    final type = _hfTypes[_activeSlot];
    if (!type.isUltralight) return null;
    return _mfuData.putIfAbsent(_activeSlot, () => _makeNtagDump(type.mfuPages ?? 45));
  }

  bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  (int, Uint8List) _fchk(Uint8List data) {
    if (data.length < 16) return _err(Status.parErr);
    final mask = data.sublist(0, 10);
    final keyCount = (data.length - 10) ~/ 6;
    final keys = <Uint8List>[];
    for (var i = 0; i < keyCount; i++) {
      keys.add(Uint8List.fromList(data.sublist(10 + i * 6, 16 + i * 6)));
    }
    if (!keys.any((k) => _bytesEqual(k, _defaultKey))) {
      return _hf();
    }
    final found = Uint8List(10);
    final sectorKeys = Uint8List(480);
    for (var i = 0; i < 80; i++) {
      final skip = (mask[i >> 3] >> (7 - (i & 7))) & 1;
      if (skip == 0) {
        found[i >> 3] |= 1 << (7 - (i & 7));
        sectorKeys.setRange(i * 6, i * 6 + 6, _defaultKey);
      }
    }
    return _hf([...found, ...sectorKeys]);
  }

  (int, Uint8List) _raw(Uint8List data) {
    if (data.length < 6) return _err(Status.parErr);
    final command = data.sublist(5);
    if (command.isNotEmpty && command[0] == 0x30 && command.length >= 2) {
      final dump = _activeMfu;
      if (dump == null) return _err(Status.hfTagNo);
      final start = (command[1] * 4).clamp(0, dump.length);
      final end = ((command[1] + 4) * 4).clamp(0, dump.length);
      return _hf(dump.sublist(start, end));
    }
    if (command.isNotEmpty && (command[0] == 0x60 || command[0] == 0x1b)) {
      return _hf(List<int>.filled(8, 0));
    }
    return _err(Status.hfTagNo);
  }


}

class _NoReply implements Exception {}
