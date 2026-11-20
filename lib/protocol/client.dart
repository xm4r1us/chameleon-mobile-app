import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../models/device_models.dart';
import 'byte_utils.dart';
import 'commands.dart';
import 'frame.dart';
import 'tag_types.dart';
import 'transport.dart';

class _Waiter {
  _Waiter(this.command, this.completer);
  final int command;
  final Completer<ChameleonFrame> completer;
}

/// High-level Chameleon Ultra protocol client.
///
/// Commands are serialised because the firmware protocol has no transaction
/// ids: only one command may be in flight at a time.
class ChameleonClient {
  ChameleonClient(this.transport, {this.log});

  final ChameleonTransport transport;
  final void Function(String line)? log;

  final FrameDecoder _decoder = FrameDecoder();
  final List<ChameleonFrame> _unsolicited = [];
  StreamSubscription<Uint8List>? _incomingSub;
  StreamSubscription<void>? _disconnectSub;
  _Waiter? _waiter;
  Future<void> _tail = Future<void>.value();
  bool _closed = false;

  Stream<Uint8List> get incoming => transport.incoming;

  List<ChameleonFrame> get unsolicitedFrames => List.unmodifiable(_unsolicited);

  void open() {
    _incomingSub ??= transport.incoming.listen(
      _onData,
      onError: (Object error) => _failPending('Transport error: $error'),
      onDone: () => _failPending('Transport closed'),
    );
    _disconnectSub ??= transport.disconnected.listen((_) {
      _failPending('Device disconnected');
    });
  }

  Future<void> close() async {
    _closed = true;
    await _incomingSub?.cancel();
    await _disconnectSub?.cancel();
    _incomingSub = null;
    _disconnectSub = null;
    _failPending('Client closed');
  }

  void _onData(Uint8List chunk) {
    final frames = _decoder.add(chunk);
    for (final frame in frames) {
      final waiter = _waiter;
      if (waiter != null && waiter.command == frame.command) {
        _waiter = null;
        if (!waiter.completer.isCompleted) waiter.completer.complete(frame);
      } else {
        _unsolicited.add(frame);
        if (_unsolicited.length > 32) _unsolicited.removeAt(0);
        log?.call('RX unsolicited ${frame.command}: ${bytesToHex(frame.data)}');
      }
    }
  }

  void _failPending(String message) {
    final waiter = _waiter;
    _waiter = null;
    if (waiter != null && !waiter.completer.isCompleted) {
      waiter.completer.completeError(ChameleonException(message));
    }
  }

  Future<ChameleonFrame> send(
    int command, {
    List<int>? data,
    Duration timeout = const Duration(seconds: 5),
    Set<int>? allowedStatus,
    bool skipStatusCheck = false,
  }) async {
    if (_closed) throw ChameleonException('Client is closed');
    final previous = _tail;
    final gate = Completer<void>();
    _tail = gate.future;
    await previous;
    try {
      return await _sendNow(
        command,
        data: data,
        timeout: timeout,
        allowedStatus: allowedStatus,
        skipStatusCheck: skipStatusCheck,
      );
    } finally {
      if (!gate.isCompleted) gate.complete();
    }
  }

  Future<ChameleonFrame> _sendNow(
    int command, {
    List<int>? data,
    required Duration timeout,
    Set<int>? allowedStatus,
    required bool skipStatusCheck,
  }) async {
    final payload = data == null ? Uint8List(0) : Uint8List.fromList(data);
    final encoded = ChameleonFrame(command, 0, payload).encode();
    final completer = Completer<ChameleonFrame>();
    _waiter = _Waiter(command, completer);
    log?.call('TX $command: ${bytesToHex(payload)}');
    try {
      await transport.write(encoded);
    } catch (error) {
      _waiter = null;
      rethrow;
    }

    ChameleonFrame frame;
    try {
      frame = await completer.future.timeout(
        timeout,
        onTimeout: () {
          _waiter = null;
          throw ChameleonException(
            'Timeout waiting for response to command $command after ${timeout.inSeconds}s',
          );
        },
      );
    } finally {
      if (identical(_waiter?.command, command)) _waiter = null;
    }

    log?.call('RX ${frame.command} [0x${frame.status.toRadixString(16)}]: ${bytesToHex(frame.data)}');
    if (!skipStatusCheck) {
      final allowed = allowedStatus ?? Status.successStatuses;
      if (!allowed.contains(frame.status)) {
        throw ChameleonException(Status.describe(frame.status), status: frame.status);
      }
    }
    return frame;
  }

  // ---------------------------------------------------------------------------
  // Device
  // ---------------------------------------------------------------------------

  Future<DeviceVersion> getVersion() async {
    final versionFrame = await send(Cmd.getAppVersion);
    final major = versionFrame.data.isNotEmpty ? versionFrame.data[0] : 0;
    final minor = versionFrame.data.length > 1 ? versionFrame.data[1] : 0;

    String? git;
    try {
      final gitFrame = await send(Cmd.getGitVersion);
      git = utf8.decode(gitFrame.data, allowMalformed: true);
    } catch (_) {
      // Older firmware does not expose the git version.
    }

    int? model;
    try {
      final modelFrame = await send(Cmd.getDeviceModel);
      if (modelFrame.data.isNotEmpty) model = modelFrame.data[0];
    } catch (_) {}

    return DeviceVersion(major: major, minor: minor, gitVersion: git, model: model);
  }

  Future<String> getChipId() async {
    final frame = await send(Cmd.getDeviceChipId);
    return bytesToHexUpper(frame.data);
  }

  Future<String> getBleAddress() async {
    final frame = await send(Cmd.getDeviceAddress);
    return bytesToHexUpper(frame.data, separator: ':');
  }

  Future<List<int>> getCapabilities() async {
    try {
      final frame = await send(Cmd.getDeviceCapabilities);
      final out = <int>[];
      for (var i = 0; i + 1 < frame.data.length; i += 2) {
        out.add(u16(frame.data, i));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<bool> getReaderMode() async {
    final frame = await send(Cmd.getDeviceMode);
    return frame.data.isNotEmpty && frame.data[0] == 1;
  }

  Future<void> setReaderMode(bool reader) =>
      send(Cmd.changeDeviceMode, data: [reader ? 1 : 0]);

  Future<BatteryInfo> getBattery() async {
    final frame = await send(Cmd.getBatteryInfo);
    if (frame.data.length < 3) return const BatteryInfo(0, 0);
    return BatteryInfo(u16(frame.data), frame.data[2]);
  }

  Future<List<SlotInfo>> getSlots() async {
    final infoFrame = await send(Cmd.getSlotInfo);
    final enabledFrame = await send(Cmd.getEnabledSlots);
    final activeFrame = await send(Cmd.getActiveSlot);
    Uint8List nickData = Uint8List(0);
    try {
      nickData = (await send(Cmd.getAllSlotNicks)).data;
    } catch (_) {
      // Older firmware lacks the bulk nickname command.
    }
    final active = activeFrame.data.isNotEmpty ? activeFrame.data[0] : 0;
    final nicks = _parseNicks(nickData);

    final slots = <SlotInfo>[];
    for (var i = 0; i < 8; i++) {
      final offset = i * 4;
      final hfId = offset + 3 < infoFrame.data.length ? u16(infoFrame.data, offset) : 0;
      final lfId = offset + 3 < infoFrame.data.length ? u16(infoFrame.data, offset + 2) : 0;
      final enabledOffset = i * 2;
      final hfEnabled = enabledOffset + 1 < enabledFrame.data.length && enabledFrame.data[enabledOffset] != 0;
      final lfEnabled = enabledOffset + 1 < enabledFrame.data.length && enabledFrame.data[enabledOffset + 1] != 0;
      slots.add(SlotInfo(
        index: i,
        hfType: TagTypes.byId(hfId),
        lfType: TagTypes.byId(lfId),
        hfEnabled: hfEnabled,
        lfEnabled: lfEnabled,
        hfNick: i < nicks.length ? nicks[i].$1 : '',
        lfNick: i < nicks.length ? nicks[i].$2 : '',
        active: i == active,
      ));
    }
    return slots;
  }

  List<(String, String)> _parseNicks(Uint8List data) {
    final out = <(String, String)>[];
    var i = 0;
    while (i < data.length && out.length < 8) {
      var hf = '';
      var lf = '';
      if (i < data.length) {
        final len = data[i++];
        if (len > 0 && i + len <= data.length) {
          hf = utf8.decode(data.sublist(i, i + len), allowMalformed: true);
        }
        i += len;
      }
      if (i < data.length) {
        final len = data[i++];
        if (len > 0 && i + len <= data.length) {
          lf = utf8.decode(data.sublist(i, i + len), allowMalformed: true);
        }
        i += len;
      }
      out.add((hf, lf));
    }
    while (out.length < 8) {
      out.add(('', ''));
    }
    return out;
  }

  Future<void> setActiveSlot(int firmwareSlot) =>
      send(Cmd.setActiveSlot, data: [firmwareSlot]);

  Future<void> setSlotType(int firmwareSlot, TagType type) =>
      send(Cmd.setSlotTagType, data: [...[firmwareSlot], ...be16(type.id)]);

  Future<void> initSlot(int firmwareSlot, TagType type) =>
      send(Cmd.setSlotDataDefault, data: [...[firmwareSlot], ...be16(type.id)]);

  Future<void> setSlotEnabled(int firmwareSlot, TagSense sense, bool enabled) =>
      send(Cmd.setSlotEnable, data: [firmwareSlot, sense.value, enabled ? 1 : 0]);

  Future<void> setSlotNick(int firmwareSlot, TagSense sense, String nick) {
    final bytes = utf8.encode(nick);
    if (bytes.length > 32) throw ArgumentError('Nickname must be at most 32 bytes');
    return send(Cmd.setSlotTagNick, data: [firmwareSlot, sense.value, ...bytes]);
  }

  Future<void> deleteSlotNick(int firmwareSlot, TagSense sense) =>
      send(Cmd.deleteSlotTagNick, data: [firmwareSlot, sense.value]);

  Future<void> deleteSlotSense(int firmwareSlot, TagSense sense) =>
      send(Cmd.deleteSlotSenseType, data: [firmwareSlot, sense.value]);

  Future<void> saveSlot() => send(Cmd.slotDataConfigSave);

  Future<AntiCollData?> getAntiCollData() async {
    final frame = await send(Cmd.hf14aGetAntiCollData);
    if (frame.data.isEmpty) return null;
    return AntiCollData.parse(frame.data);
  }

  Future<void> setAntiCollData(AntiCollData data) =>
      send(Cmd.hf14aSetAntiCollData, data: data.encode());

  // ---------------------------------------------------------------------------
  // HF reader
  // ---------------------------------------------------------------------------

  Future<List<AntiCollData>> scanHf() async {
    final frame = await send(Cmd.hf14aScan, allowedStatus: {Status.hfTagOk, Status.hfTagNo});
    if (frame.status == Status.hfTagNo || frame.data.isEmpty) return const [];
    final out = <AntiCollData>[];
    var offset = 0;
    while (offset < frame.data.length) {
      final parsed = AntiCollData.parse(frame.data, offset);
      if (parsed == null) break;
      out.add(parsed);
      offset += parsed.encode().length;
    }
    return out;
  }

  Future<bool> mf1Supported() async {
    final frame = await send(Cmd.mf1DetectSupport, allowedStatus: {Status.hfTagOk, Status.hfTagNo});
    return frame.status == Status.hfTagOk;
  }

  Future<int?> mf1PrngLevel() async {
    final frame = await send(Cmd.mf1DetectPrng, allowedStatus: {Status.hfTagOk, Status.hfTagNo});
    if (frame.status != Status.hfTagOk || frame.data.isEmpty) return null;
    return frame.data[0];
  }

  Future<(int uid, int distance)> mf1NtDistance(
    int blockKnown,
    int typeKnown,
    Uint8List keyKnown,
  ) async {
    final frame = await send(
      Cmd.mf1DetectNtDist,
      data: [typeKnown, blockKnown, ...keyKnown],
      allowedStatus: {Status.hfTagOk, Status.mfErrAuth},
    );
    if (frame.status != Status.hfTagOk) {
      throw ChameleonException(Status.describe(frame.status), status: frame.status);
    }
    return (u32(frame.data), u32(frame.data, 4));
  }

  Future<Mf1NestedData> mf1NestedAcquire({
    required int blockKnown,
    required int typeKnown,
    required Uint8List keyKnown,
    required int blockTarget,
    required int typeTarget,
  }) async {
    final frame = await send(
      Cmd.mf1NestedAcquire,
      data: [typeKnown, blockKnown, ...keyKnown, typeTarget, blockTarget],
      timeout: const Duration(seconds: 15),
      allowedStatus: {Status.hfTagOk, Status.mfErrAuth},
    );
    if (frame.status != Status.hfTagOk) {
      throw ChameleonException(Status.describe(frame.status), status: frame.status);
    }
    final nonces = <Mf1NestedNonce>[];
    for (var i = 0; i + 8 < frame.data.length; i += 9) {
      nonces.add(Mf1NestedNonce(u32(frame.data, i), u32(frame.data, i + 4), frame.data[i + 8]));
    }
    return Mf1NestedData(uid: 0, nonces: nonces);
  }

  Future<Mf1StaticNestedData> mf1StaticNestedAcquire({
    required int blockKnown,
    required int typeKnown,
    required Uint8List keyKnown,
    required int blockTarget,
    required int typeTarget,
  }) async {
    final frame = await send(
      Cmd.mf1StaticNestedAcquire,
      data: [typeKnown, blockKnown, ...keyKnown, typeTarget, blockTarget],
      timeout: const Duration(seconds: 15),
      allowedStatus: {Status.hfTagOk, Status.mfErrAuth},
    );
    if (frame.status != Status.hfTagOk) {
      throw ChameleonException(Status.describe(frame.status), status: frame.status);
    }
    final nonces = <Mf1NestedNonce>[];
    for (var i = 4; i + 7 < frame.data.length; i += 8) {
      nonces.add(Mf1NestedNonce(u32(frame.data, i), u32(frame.data, i + 4), 0));
    }
    return Mf1StaticNestedData(uid: u32(frame.data), nonces: nonces);
  }

  Future<Mf1DarksideData> mf1DarksideAcquire({
    required int blockTarget,
    required int typeTarget,
    bool firstRecover = true,
    int syncMax = 30,
  }) async {
    final frame = await send(
      Cmd.mf1DarksideAcquire,
      data: [typeTarget, blockTarget, firstRecover ? 1 : 0, syncMax],
      timeout: Duration(seconds: (syncMax * 10).clamp(10, 300)),
      allowedStatus: {Status.hfTagOk, Status.hfTagNo, Status.hfCollision},
    );
    if (frame.status != Status.hfTagOk || frame.data.isEmpty) {
      return Mf1DarksideData(
        status: frame.status,
        uid: 0,
        nt1: 0,
        par: 0,
        ks1: 0,
        nr: 0,
        ar: 0,
      );
    }
    if (frame.data[0] != 0 || frame.data.length < 33) {
      return Mf1DarksideData(
        status: frame.data[0],
        uid: 0,
        nt1: 0,
        par: 0,
        ks1: 0,
        nr: 0,
        ar: 0,
      );
    }
    return Mf1DarksideData(
      status: frame.data[0],
      uid: u32(frame.data, 1),
      nt1: u32(frame.data, 5),
      par: u64(frame.data, 9),
      ks1: u64(frame.data, 17),
      nr: u32(frame.data, 25),
      ar: u32(frame.data, 29),
    );
  }

  Future<bool> mf1AuthBlock(int block, int type, Uint8List key) async {
    final frame = await send(
      Cmd.mf1AuthOneKeyBlock,
      data: [type, block, ...key],
      allowedStatus: {Status.hfTagOk, Status.mfErrAuth, Status.hfTagNo},
    );
    return frame.status == Status.hfTagOk;
  }

  Future<Uint8List> mf1ReadBlock(int block, int type, Uint8List key) async {
    final frame = await send(
      Cmd.mf1ReadOneBlock,
      data: [type, block, ...key],
      allowedStatus: {Status.hfTagOk, Status.mfErrAuth, Status.hfTagNo},
    );
    if (frame.status != Status.hfTagOk) {
      throw ChameleonException(Status.describe(frame.status), status: frame.status);
    }
    if (frame.data.length != 16) {
      throw ChameleonException('Unexpected block length ${frame.data.length}');
    }
    return Uint8List.fromList(frame.data);
  }

  Future<bool> mf1WriteBlock(int block, int type, Uint8List key, Uint8List data) async {
    if (data.length != 16) throw ArgumentError('Block must be 16 bytes');
    final frame = await send(
      Cmd.mf1WriteOneBlock,
      data: [type, block, ...key, ...data],
      allowedStatus: {Status.hfTagOk, Status.mfErrAuth, Status.hfTagNo},
    );
    return frame.status == Status.hfTagOk;
  }

  Future<Uint8List> hf14aRaw({
    bool activateRf = true,
    bool waitResponse = true,
    bool appendCrc = false,
    bool autoSelect = false,
    bool keepField = false,
    bool checkCrc = false,
    int responseTimeoutMs = 200,
    required List<int> data,
    int? bitLength,
  }) async {
    var options = 0;
    if (activateRf) options |= 0x80;
    if (waitResponse) options |= 0x40;
    if (appendCrc) options |= 0x20;
    if (autoSelect) options |= 0x10;
    if (keepField) options |= 0x08;
    if (checkCrc) options |= 0x04;

    final bits = bitLength ?? data.length * 8;
    final frame = await send(
      Cmd.hf14aRaw,
      data: [
        options,
        (responseTimeoutMs >> 8) & 0xff,
        responseTimeoutMs & 0xff,
        (bits >> 8) & 0xff,
        bits & 0xff,
        ...data,
      ],
      timeout: Duration(milliseconds: responseTimeoutMs + 1500),
      allowedStatus: Status.successStatuses,
    );
    return Uint8List.fromList(frame.data);
  }

  Future<Mf1KeyCheckResult> checkKeysOfSectors({
    required Uint8List mask,
    required List<Uint8List> keys,
  }) async {
    if (mask.length != 10) throw ArgumentError('Mask must be 10 bytes');
    if (keys.isEmpty || keys.length > 83) throw ArgumentError('1..83 keys');
    var bits = 80;
    for (final b in mask) {
      var value = b;
      while (value > 0) {
        bits -= value & 1;
        value >>= 1;
      }
    }
    if (bits < 1) {
      return Mf1KeyCheckResult(foundMask: Uint8List(10), keys: {});
    }
    final frame = await send(
      Cmd.mf1CheckKeysOfSectors,
      data: [...mask, for (final k in keys) ...k],
      timeout: Duration(milliseconds: (1000 + (bits + 1) * keys.length * 100).clamp(2000, 300000)),
      allowedStatus: {Status.hfTagOk, Status.hfTagNo},
    );
    if (frame.status != Status.hfTagOk || frame.data.length != 490) {
      return Mf1KeyCheckResult(foundMask: Uint8List(10), keys: {});
    }
    final foundMask = Uint8List.fromList(frame.data.sublist(0, 10));
    final found = <int, Uint8List>{};
    for (var i = 0; i < 80; i++) {
      final byte = foundMask[i >> 3];
      final bit = (byte >> (7 - (i & 7))) & 1;
      if (bit == 1) {
        found[i] = Uint8List.fromList(frame.data.sublist(10 + 6 * i, 16 + 6 * i));
      }
    }
    return Mf1KeyCheckResult(foundMask: foundMask, keys: found);
  }

  Future<Uint8List?> checkKeysOnBlock(int block, int type, List<Uint8List> keys) async {
    if (keys.isEmpty || keys.length > 83) throw ArgumentError('1..83 keys');
    final frame = await send(
      Cmd.mf1CheckKeysOnBlock,
      data: [block, type, keys.length, for (final k in keys) ...k],
      timeout: const Duration(seconds: 15),
      allowedStatus: {Status.hfTagOk, Status.hfTagNo, Status.mfErrAuth},
    );
    if (frame.status == Status.hfTagOk && frame.data.length >= 7 && frame.data[0] != 0) {
      return Uint8List.fromList(frame.data.sublist(1, 7));
    }
    return null;
  }

  Future<bool> manipulateValueBlock({
    required int srcBlock,
    required int srcType,
    required Uint8List srcKey,
    required int operator,
    required int operand,
    required int dstBlock,
    required int dstType,
    required Uint8List dstKey,
  }) async {
    final frame = await send(
      Cmd.mf1ManipulateValueBlock,
      data: [
        srcType,
        srcBlock,
        ...srcKey,
        operator,
        (operand >> 24) & 0xff,
        (operand >> 16) & 0xff,
        (operand >> 8) & 0xff,
        operand & 0xff,
        dstType,
        dstBlock,
        ...dstKey,
      ],
      allowedStatus: {Status.hfTagOk, Status.hfTagNo, Status.mfErrAuth},
    );
    return frame.status == Status.hfTagOk;
  }

  // ---------------------------------------------------------------------------
  // MIFARE Classic emulator
  // ---------------------------------------------------------------------------

  Future<void> mf1WriteEmuBlocks(int startBlock, Uint8List data) =>
      send(Cmd.mf1WriteEmuBlockData, data: [startBlock, ...data]);

  Future<Uint8List> mf1ReadEmuBlocks(int startBlock, int count) async {
    final frame = await send(Cmd.mf1ReadEmuBlockData, data: [startBlock, count]);
    return Uint8List.fromList(frame.data);
  }

  Future<Mf1EmulatorConfig> mf1GetEmuConfig() async {
    final frame = await send(Cmd.mf1GetEmulatorConfig);
    final data = frame.data;
    if (data.length < 5) {
      throw ChameleonException('Unexpected emulator config payload');
    }
    var fieldOff = false;
    var prng = 1;
    try {
      final f = await send(Cmd.mf1GetFieldOffDoReset);
      fieldOff = f.data.isNotEmpty && f.data[0] == 1;
    } catch (_) {}
    try {
      final p = await send(Cmd.mf1GetPrngType);
      if (p.data.isNotEmpty) prng = p.data[0];
    } catch (_) {}
    return Mf1EmulatorConfig(
      detection: data[0] == 1,
      gen1a: data[1] == 1,
      gen2: data[2] == 1,
      blockAntiColl: data[3] == 1,
      writeMode: data[4],
      fieldOffReset: fieldOff,
      prngType: prng,
    );
  }

  Future<void> mf1SetEmuOption(int command, bool enabled) =>
      send(command, data: [enabled ? 1 : 0]);

  Future<void> mf1SetWriteMode(int mode) => send(Cmd.mf1SetWriteMode, data: [mode]);

  Future<void> mf1SetFieldOffReset(bool enabled) =>
      send(Cmd.mf1SetFieldOffDoReset, data: [enabled ? 1 : 0]);

  Future<void> mf1SetPrngType(int type) => send(Cmd.mf1SetPrngType, data: [type]);

  Future<void> mf1SetDetection(bool enabled) =>
      send(Cmd.mf1SetDetectionEnable, data: [enabled ? 1 : 0]);

  Future<int> mf1DetectionCount() async {
    final frame = await send(Cmd.mf1GetDetectionCount);
    return frame.data.length >= 4 ? u32(frame.data) : 0;
  }

  Future<List<Mf1DetectionRecord>> mf1DetectionLog({int index = 0}) async {
    final frame = await send(Cmd.mf1GetDetectionLog, data: be32(index));
    final out = <Mf1DetectionRecord>[];
    for (var pos = 0; pos + 17 < frame.data.length; pos += 18) {
      final bitfield = frame.data[pos + 1];
      out.add(Mf1DetectionRecord(
        block: frame.data[pos],
        keyType: (bitfield & 1) == 0 ? 'A' : 'B',
        isNested: (bitfield & 2) != 0,
        uid: Uint8List.fromList(frame.data.sublist(pos + 2, pos + 6)),
        nt: Uint8List.fromList(frame.data.sublist(pos + 6, pos + 10)),
        nr: Uint8List.fromList(frame.data.sublist(pos + 10, pos + 14)),
        ar: Uint8List.fromList(frame.data.sublist(pos + 14, pos + 18)),
      ));
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // MIFARE Ultralight / NTAG
  // ---------------------------------------------------------------------------

  Future<int> mfuEmuPageCount() async {
    final frame = await send(Cmd.mf0NtagGetPageCount);
    return frame.data.isNotEmpty ? frame.data[0] : 0;
  }

  Future<Uint8List> mfuReadEmuPages(int page, int count) async {
    final frame = await send(Cmd.mf0NtagReadEmuPageData, data: [page, count]);
    return Uint8List.fromList(frame.data);
  }

  Future<void> mfuWriteEmuPages(int page, Uint8List data) {
    if (data.length % 4 != 0) throw ArgumentError('Page data must be 4-byte aligned');
    return send(Cmd.mf0NtagWriteEmuPageData, data: [page, data.length ~/ 4, ...data]);
  }

  Future<bool> mfuGetUidMagic() async {
    final frame = await send(Cmd.mf0NtagGetUidMagicMode);
    return frame.data.isNotEmpty && frame.data[0] != 0;
  }

  Future<void> mfuSetUidMagic(bool enabled) =>
      send(Cmd.mf0NtagSetUidMagicMode, data: [enabled ? 1 : 0]);

  Future<Uint8List> mfuGetVersion() async {
    final frame = await send(Cmd.mf0NtagGetVersionData);
    return Uint8List.fromList(frame.data);
  }

  Future<void> mfuSetVersion(Uint8List data) {
    if (data.length != 8) throw ArgumentError('Version must be 8 bytes');
    return send(Cmd.mf0NtagSetVersionData, data: data);
  }

  Future<Uint8List> mfuGetSignature() async {
    final frame = await send(Cmd.mf0NtagGetSignatureData);
    return Uint8List.fromList(frame.data);
  }

  Future<void> mfuSetSignature(Uint8List data) {
    if (data.length != 32) throw ArgumentError('Signature must be 32 bytes');
    return send(Cmd.mf0NtagSetSignatureData, data: data);
  }

  Future<(int value, bool tearing)> mfuGetCounter(int index) async {
    final frame = await send(Cmd.mf0NtagGetCounterData, data: [index]);
    if (frame.data.length < 4) throw ChameleonException('Invalid counter payload');
    final value = (frame.data[2] << 16) | (frame.data[1] << 8) | frame.data[0];
    return (value, frame.data[3] == 0xBD);
  }

  Future<void> mfuSetCounter(int index, int value, {bool resetTearing = false}) =>
      send(Cmd.mf0NtagSetCounterData, data: [
        index | (resetTearing ? 0x80 : 0),
        value & 0xff,
        (value >> 8) & 0xff,
        (value >> 16) & 0xff,
      ]);

  Future<int> mfuResetAuthCounter() async {
    final frame = await send(Cmd.mf0NtagResetAuthCnt);
    return frame.data.isNotEmpty ? frame.data[0] : 0;
  }

  Future<int> mfuGetWriteMode() async {
    final frame = await send(Cmd.mf0NtagGetWriteMode);
    return frame.data.isNotEmpty ? frame.data[0] : 0;
  }

  Future<void> mfuSetWriteMode(int mode) =>
      send(Cmd.mf0NtagSetWriteMode, data: [mode]);

  Future<void> mfuSetDetection(bool enabled) =>
      send(Cmd.mf0NtagSetDetectionEnable, data: [enabled ? 1 : 0]);

  Future<bool> ulcAuth(Uint8List key) async {
    final frame = await send(
      Cmd.mf0UlcAuth,
      data: key,
      allowedStatus: {Status.hfTagOk, Status.mfErrAuth, Status.hfTagNo},
    );
    return frame.status == Status.hfTagOk;
  }

  Future<Uint8List> ulcRead(Uint8List key, int page, int count) async {
    final frame = await send(Cmd.mf0UlcRead, data: [...key, page, count]);
    return Uint8List.fromList(frame.data);
  }

  Future<void> ulcWrite(Uint8List key, int page, Uint8List data) {
    if (data.length != 4) throw ArgumentError('ULC page must be 4 bytes');
    return send(Cmd.mf0UlcWrite, data: [...key, page, ...data]);
  }

  Future<void> ulcSetKey(Uint8List oldKey, Uint8List newKey) {
    if (oldKey.length != 16 || newKey.length != 16) {
      throw ArgumentError('ULC keys must be 16 bytes');
    }
    return send(Cmd.mf0UlcSetKey, data: [...oldKey, ...newKey]);
  }

  // ---------------------------------------------------------------------------
  // LF
  // ---------------------------------------------------------------------------

  Future<LfScanResult?> scanLf(TagType type) async {
    switch (type.id) {
      case 100:
      case 101:
      case 102:
      case 103:
      case 104:
        return _scanEm410x();
      case 150:
        return _scanPac();
      case 170:
        return _scanViking();
      case 180:
        return _scanJablotron();
      case 200:
        return _scanHidProx();
      case 201:
        return _scanIoProx();
      case 202:
        return _scanPyramid();
      case 310:
        return _scanIdteck();
      default:
        throw ChameleonException('${type.name} scanning is not supported');
    }
  }

  Future<LfScanResult?> _lfSend(int command, TagType type) async {
    final frame = await send(
      command,
      allowedStatus: {Status.lfTagOk, Status.lfTagNoFound},
      timeout: const Duration(seconds: 8),
    );
    if (frame.status != Status.lfTagOk || frame.data.isEmpty) return null;
    return LfScanResult(type: type, raw: Uint8List.fromList(frame.data), summary: '');
  }

  Future<LfScanResult?> _scanEm410x() async {
    final base = await _lfSend(Cmd.em410xScan, TagTypes.em410x);
    if (base == null) return null;
    var data = base.raw;
    var type = TagTypes.em410x;
    if (data.length >= 2) {
      final typeId = u16(data);
      if (typeId == TagTypes.em410xElectra.id) {
        type = TagTypes.em410xElectra;
        data = Uint8List.fromList(data.sublist(2));
      } else if (typeId == 100 || typeId == 101 || typeId == 102 || typeId == 103) {
        type = TagTypes.byId(typeId);
        data = Uint8List.fromList(data.sublist(2));
      }
    }
    final hex = bytesToHexUpper(data);
    return LfScanResult(
      type: type,
      raw: data,
      summary: type.id == TagTypes.em410xElectra.id ? 'EM410x Electra $hex' : 'EM410x $hex',
      fields: {'ID': hex},
    );
  }

  Future<LfScanResult?> _scanHidProx() async {
    final frame = await send(
      Cmd.hidproxScan,
      data: [1], // H10301
      allowedStatus: {Status.lfTagOk, Status.lfTagNoFound},
      timeout: const Duration(seconds: 8),
    );
    if (frame.status != Status.lfTagOk || frame.data.length < 13) return null;
    final format = frame.data[0];
    final facility = u32(frame.data, 1);
    final card = frame.data.sublist(5, 10);
    final issue = frame.data[10];
    final oem = u16(frame.data, 11);
    final cardNumber = card.fold<int>(0, (acc, b) => (acc << 8) | b);
    return LfScanResult(
      type: TagTypes.hidProx,
      raw: Uint8List.fromList(frame.data),
      summary: 'HID Prox FC $facility / CN $cardNumber',
      fields: {
        'Format': '$format',
        'Facility': '$facility',
        'Card': '$cardNumber',
        'Issue': '$issue',
        'OEM': '$oem',
      },
    );
  }

  Future<LfScanResult?> _scanIoProx() async {
    final base = await _lfSend(Cmd.ioproxScan, TagTypes.ioProx);
    if (base == null || base.raw.length < 16) return null;
    final version = base.raw[0];
    final facility = base.raw[1];
    final card = u16(base.raw, 2);
    return LfScanResult(
      type: TagTypes.ioProx,
      raw: base.raw,
      summary: 'ioProx v$version FC $facility / CN $card',
      fields: {'Version': '$version', 'Facility': '$facility', 'Card': '$card'},
    );
  }

  Future<LfScanResult?> _scanViking() async {
    final base = await _lfSend(Cmd.vikingScan, TagTypes.viking);
    if (base == null) return null;
    final hex = bytesToHexUpper(base.raw);
    return LfScanResult(type: TagTypes.viking, raw: base.raw, summary: 'Viking $hex', fields: {'ID': hex});
  }

  Future<LfScanResult?> _scanPac() async {
    final base = await _lfSend(Cmd.pacScan, TagTypes.pac);
    if (base == null) return null;
    final text = utf8.decode(base.raw, allowMalformed: true);
    return LfScanResult(type: TagTypes.pac, raw: base.raw, summary: 'PAC/Stanley $text', fields: {'ID': text});
  }

  Future<LfScanResult?> _scanJablotron() async {
    final base = await _lfSend(Cmd.jablotronScan, TagTypes.jablotron);
    if (base == null) return null;
    final hex = bytesToHexUpper(base.raw);
    return LfScanResult(
      type: TagTypes.jablotron,
      raw: base.raw,
      summary: 'Jablotron $hex',
      fields: {'ID': hex},
    );
  }

  Future<LfScanResult?> _scanPyramid() async {
    final base = await _lfSend(Cmd.pyramidScan, TagTypes.pyramid);
    if (base == null) return null;
    final hex = bytesToHexUpper(base.raw);
    return LfScanResult(type: TagTypes.pyramid, raw: base.raw, summary: 'Pyramid $hex', fields: {'Raw': hex});
  }

  Future<LfScanResult?> _scanIdteck() async {
    // IDTECK is PSK; the CLI reads it through the raw LF sampler. Firmware
    // exposes a dedicated write-only command, so scanning is not available.
    throw ChameleonException('IDTECK reading requires the raw LF sampler and is not supported by this firmware');
  }

  Future<void> lfWriteToT55xx(TagType type, Uint8List id, {List<Uint8List> oldKeys = const []}) async {
    final newKey = Uint8List.fromList([0x20, 0x20, 0x66, 0x66]);
    final keys = oldKeys.isEmpty
        ? [Uint8List.fromList([0x51, 0x24, 0x36, 0x48])]
        : oldKeys;
    int command;
    switch (type.id) {
      case 100:
      case 101:
      case 102:
      case 103:
      case 104:
        command = id.length == 13 ? Cmd.em410xElectraWriteToT55xx : Cmd.em410xWriteToT55xx;
        break;
      case 200:
        command = Cmd.hidproxWriteToT55xx;
        break;
      case 201:
        command = Cmd.ioproxWriteToT55xx;
        break;
      case 150:
        command = Cmd.pacWriteToT55xx;
        break;
      case 170:
        command = Cmd.vikingWriteToT55xx;
        break;
      case 180:
        command = Cmd.jablotronWriteToT55xx;
        break;
      case 310:
        command = Cmd.idteckWriteToT55xx;
        break;
      default:
        throw ChameleonException('Writing ${type.name} to T55xx is not supported');
    }
    await send(
      command,
      data: [...id, ...newKey, for (final key in keys) ...key],
      timeout: const Duration(seconds: 10),
      allowedStatus: {Status.lfTagOk, Status.lfTagNoFound, Status.parErr},
    );
  }

  Future<Uint8List?> getLfEmuId(TagType type) async {
    final command = switch (type.id) {
      100 || 101 || 102 || 103 || 104 => Cmd.em410xGetEmuId,
      150 => Cmd.pacGetEmuId,
      170 => Cmd.vikingGetEmuId,
      180 => Cmd.jablotronGetEmuId,
      200 => Cmd.hidproxGetEmuId,
      201 => Cmd.ioproxGetEmuId,
      310 => Cmd.idteckGetEmuId,
      _ => null,
    };
    if (command == null) return null;
    final frame = await send(command);
    final data = Uint8List.fromList(frame.data);
    // EM410x responses may include the tag type (u16) in front of the ID.
    if (type.id >= 100 && type.id <= 104 && data.length >= 2) {
      final prefix = u16(data);
      final expected = prefix == TagTypes.em410xElectra.id ? 13 : 5;
      if (prefix >= 100 && prefix <= 104 && data.length == expected + 2) {
        return Uint8List.fromList(data.sublist(2));
      }
    }
    return data;
  }

  Future<void> setLfEmuId(TagType type, Uint8List id) async {
    final command = switch (type.id) {
      100 || 101 || 102 || 103 || 104 => Cmd.em410xSetEmuId,
      150 => Cmd.pacSetEmuId,
      170 => Cmd.vikingSetEmuId,
      180 => Cmd.jablotronSetEmuId,
      200 => Cmd.hidproxSetEmuId,
      201 => Cmd.ioproxSetEmuId,
      310 => Cmd.idteckSetEmuId,
      _ => null,
    };
    if (command == null) throw ChameleonException('${type.name} emulation is not supported');
    await send(command, data: id);
  }

  // ---------------------------------------------------------------------------
  // ISO14443-4 / APDU reader
  // ---------------------------------------------------------------------------

  /// Sends one ISO7816-4 APDU to a card in the field. The firmware performs
  /// the 14A select, RATS, CRC and PCB framing; the returned bytes are the
  /// card's response including SW1/SW2.
  Future<Uint8List> hf14a4ReaderApdu(Uint8List apdu) async {
    if (apdu.isEmpty) throw ArgumentError('APDU must not be empty');
    if (apdu.length > 512) throw ArgumentError('APDU exceeds 512 bytes');
    final frame = await send(
      Cmd.hf14a4ReaderApdu,
      data: apdu,
      timeout: const Duration(seconds: 6),
      allowedStatus: {
        Status.success,
        Status.hfTagOk,
        Status.hfTagNo,
        Status.hfErrStat,
        Status.hfErrCrc,
        Status.hfCollision,
        Status.parErr,
      },
    );
    if (frame.status == Status.hfTagNo) {
      throw ChameleonException('No ISO14443-4 card in field', status: frame.status);
    }
    if (frame.status != Status.success && frame.status != Status.hfTagOk) {
      throw ChameleonException(Status.describe(frame.status), status: frame.status);
    }
    return Uint8List.fromList(frame.data);
  }

  /// Runs the firmware's one-shot EMV scan: field cycle, PPSE, SELECT AID,
  /// GPO and READ RECORD all execute inside the Chameleon. This avoids
  /// re-activating the RC522 between host APDUs, which overruns its 64-byte
  /// receive path on real card records.
  Future<Uint8List> hf14a4EmvScan() async {
    final frame = await send(
      Cmd.hf14a4EmvScan,
      timeout: const Duration(seconds: 30),
      allowedStatus: {
        Status.success,
        Status.hfTagOk,
        Status.hfTagNo,
        Status.hfErrStat,
        Status.hfErrCrc,
        Status.hfCollision,
        Status.hfErrParity,
        Status.hfErrAts,
        Status.parErr,
      },
    );
    if (frame.status == Status.hfTagNo) {
      throw ChameleonException('No ISO14443-4 card in field', status: frame.status);
    }
    if (frame.status != Status.success && frame.status != Status.hfTagOk) {
      throw ChameleonException(Status.describe(frame.status), status: frame.status);
    }
    return Uint8List.fromList(frame.data);
  }

  // ---------------------------------------------------------------------------
  // Device settings
  // ---------------------------------------------------------------------------

  Future<int> getAnimationMode() async {
    final frame = await send(Cmd.getAnimationMode);
    return frame.data.isNotEmpty ? frame.data[0] : 0;
  }

  Future<void> setAnimationMode(int mode) => send(Cmd.setAnimationMode, data: [mode]);

  Future<int> getSleepTimeout() async {
    final frame = await send(Cmd.getSleepTimeout);
    return frame.data.isNotEmpty ? frame.data[0] : 0;
  }

  Future<void> setSleepTimeout(int seconds) =>
      send(Cmd.setSleepTimeout, data: [seconds.clamp(0, 255)]);

  Future<int> getLongPressThreshold() async {
    final frame = await send(Cmd.getLongPressThreshold);
    return frame.data.length >= 2 ? u16(frame.data) : 0;
  }

  Future<void> setLongPressThreshold(int ms) =>
      send(Cmd.setLongPressThreshold, data: be16(ms.clamp(0, 65535)));

  Future<int> getButtonPress(int buttonCode, {bool long = false}) async {
    final frame = await send(long ? Cmd.getLongButtonPressConfig : Cmd.getButtonPressConfig, data: [buttonCode]);
    return frame.data.isNotEmpty ? frame.data[0] : 0;
  }

  Future<void> setButtonPress(int buttonCode, int function, {bool long = false}) =>
      send(long ? Cmd.setLongButtonPressConfig : Cmd.setButtonPressConfig, data: [buttonCode, function]);

  Future<String> getBlePairingKey() async {
    final frame = await send(Cmd.getBlePairingKey);
    return ascii.decode(frame.data, allowInvalid: true);
  }

  Future<void> setBlePairingKey(String key) {
    final bytes = ascii.encode(key);
    if (bytes.length != 6) throw ArgumentError('BLE pairing key must be 6 characters');
    return send(Cmd.setBlePairingKey, data: bytes);
  }

  Future<bool> getBlePairingEnabled() async {
    final frame = await send(Cmd.getBlePairingEnable);
    return frame.data.isNotEmpty && frame.data[0] != 0;
  }

  Future<void> setBlePairingEnabled(bool enabled) =>
      send(Cmd.setBlePairingEnable, data: [enabled ? 1 : 0]);

  Future<void> deleteAllBleBonds() => send(Cmd.deleteAllBleBonds);

  Future<void> saveSettings() => send(Cmd.saveSettings);

  Future<void> resetSettings() => send(Cmd.resetSettings);

  Future<void> factoryReset() async {
    await send(Cmd.wipeFds);
  }

  Future<void> enterBootloader() async {
    await send(Cmd.enterBootloader, skipStatusCheck: true, timeout: const Duration(seconds: 2));
  }

  Future<DeviceSettings> getDeviceSettings() async {
    final frame = await send(Cmd.getDeviceSettings);
    final data = frame.data;
    if (data.length < 14) throw ChameleonException('Invalid settings payload');
    var longPress = 0;
    try {
      longPress = await getLongPressThreshold();
    } catch (_) {}
    return DeviceSettings(
      animationMode: data[1],
      buttonPressA: data[2],
      buttonPressB: data[3],
      longPressA: data[4],
      longPressB: data[5],
      blePairingEnabled: data[6] != 0,
      blePairingKey: ascii.decode(data.sublist(7, 13), allowInvalid: true),
      sleepTimeout: data[13],
      longPressThreshold: longPress,
    );
  }

  Future<void> setReaderModeChecked() async {
    final reader = await getReaderMode();
    if (!reader) await setReaderMode(true);
  }
}

class Mf1KeyCheckResult {
  Mf1KeyCheckResult({required this.foundMask, required this.keys});
  final Uint8List foundMask;
  final Map<int, Uint8List> keys;
}
