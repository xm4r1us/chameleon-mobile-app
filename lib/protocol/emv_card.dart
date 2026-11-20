import 'dart:math';
import 'dart:typed_data';

import 'byte_utils.dart';
import 'tlv.dart';

/// Sends one ISO7816-4 APDU and returns the card response including SW1/SW2.
typedef ApduSender = Future<Uint8List> Function(Uint8List apdu);

/// Runs the firmware's one-shot EMV scan (command 6005) and parses its
/// transcript.
typedef EmvScanner = Future<EmvScanData> Function();

/// One raw APDU request/response pair captured by the firmware scan.
class EmvScanExchange {
  const EmvScanExchange({required this.command, required this.response});
  final Uint8List command;
  final Uint8List response;
}

/// Transcript of a complete one-shot EMV scan performed on the Chameleon.
class EmvScanData {
  const EmvScanData(this.exchanges);
  final List<EmvScanExchange> exchanges;
}

/// Parses the packed payload returned by firmware command `6005`:
/// tag info (UID/ATQA/SAK/ATS), APDU count, then
/// `cmd_len(1) cmd(n) resp_len(2 LE) resp(m)` pairs.
EmvScanData parseEmvScan(Uint8List payload) {
  final cursor = _PayloadCursor(payload);
  cursor.bytes(cursor.u8()); // UID
  cursor.bytes(2); // ATQA
  cursor.u8(); // SAK
  cursor.bytes(cursor.u8()); // ATS
  final count = cursor.u8();
  final exchanges = <EmvScanExchange>[];
  for (var i = 0; i < count; i++) {
    final command = cursor.bytes(cursor.u8());
    final response = cursor.bytes(cursor.u16le());
    exchanges.add(EmvScanExchange(command: command, response: response));
  }
  return EmvScanData(List.unmodifiable(exchanges));
}

class _PayloadCursor {
  _PayloadCursor(this.data);
  final Uint8List data;
  int _pos = 0;

  int u8() {
    if (_pos >= data.length) throw const EmvCardException('Truncated EMV scan response');
    return data[_pos++];
  }

  int u16le() => u8() | (u8() << 8);

  Uint8List bytes(int length) {
    if (length < 0 || _pos + length > data.length) {
      throw const EmvCardException('Truncated EMV scan response');
    }
    final out = Uint8List.fromList(data.sublist(_pos, _pos + length));
    _pos += length;
    return out;
  }
}

class EmvCardException implements Exception {
  const EmvCardException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Result of an EMV directory walk.
class EmvPanResult {
  const EmvPanResult({
    required this.pan,
    required this.aid,
    required this.sourceTag,
    required this.candidates,
  });

  /// Primary account number as decimal digits (no separators).
  final String pan;

  /// AID of the application that supplied the PAN, uppercase hex.
  final String aid;

  /// TLV tag the PAN was read from: `5A` or `57` (track 2 equivalent).
  final String sourceTag;

  /// Every AID found during discovery, in probing order.
  final List<String> candidates;
}

/// Minimal EMV contactless reader. With [EmvCardReader.scan] it consumes the
/// firmware's one-shot EMV transcript; with [EmvCardReader.send] it discovers
/// applications through PPSE, then PSE, then a known-AID fallback, starts each
/// application with a synthetic GPO and scans the AFL records for the PAN.
///
/// The APDU path is only for firmware without command 6005. Sending those
/// APDUs from the host re-activates the RC522 between records, which overruns
/// its 64-byte receive path on real cards.
///
/// It performs no authentication and extracts nothing except the PAN.
class EmvCardReader {
  EmvCardReader({
    ApduSender? send,
    EmvScanner? scan,
    this.onProgress,
    Random? random,
  })  : assert(send != null || scan != null, 'Give send or scan'),
        _send = send,
        _scan = scan,
        _random = random ?? Random.secure();

  final ApduSender? _send;
  final EmvScanner? _scan;

  /// Reports a language-neutral technical step (e.g. `PPSE`, `AID …`).
  final void Function(String step)? onProgress;

  final Random _random;

  static const String _ppse = '325041592E5359532E4444463031';
  static const String _pse = '315041592E5359532E4444463031';

  static const List<String> _fallbackAids = [
    'A0000000031010', // Visa credit/debit
    'A0000000032010', // Visa Electron
    'A0000000041010', // Mastercard
    'A0000000043060', // Maestro
    'A0000006723010', // Troy credit
    'A0000006723020', // Troy debit
    'A00000002501', // American Express
  ];

  static const Map<String, String> _pdolDefaults = {
    '9F66': '36004000', // TTQ
    '9F02': '000000000100', // amount authorised, 1.00
    '9F1A': '0792', // country code, Türkiye
    '5F2A': '0949', // currency code, TRY
  };

  Future<EmvPanResult> readPan() async {
    final scan = _scan;
    if (scan != null) {
      onProgress?.call('EMV SCAN');
      return _panFromScan(await scan());
    }

    final aids = await _discoverAids();

    for (final aidHex in aids) {
      onProgress?.call('AID $aidHex');
      final aid = hexToBytes(aidHex);

      final selectResponse = await _select(aid);
      if (_sw(selectResponse) != 0x9000) continue;

      final gpo = await _startProcessing(selectResponse);
      if (gpo == null) continue;

      final afl = _extractAfl(gpo);
      if (afl == null) continue;
      onProgress?.call('AFL ${bytesToHexUpper(afl)}');

      final pan = await _scanAfl(afl);
      if (pan != null) {
        return EmvPanResult(
          pan: pan.pan,
          aid: aidHex,
          sourceTag: pan.sourceTag,
          candidates: List.unmodifiable(aids),
        );
      }
    }

    throw const EmvCardException('No readable payment application on the card');
  }

  EmvPanResult _panFromScan(EmvScanData data) {
    var aidHex = '';
    final candidates = <String>[];

    for (final exchange in data.exchanges) {
      final nodes = _parse(exchange.response);
      for (final node in _find(nodes, '4F')) {
        final hex = bytesToHexUpper(node.value);
        if (hex.isNotEmpty && !candidates.contains(hex)) candidates.add(hex);
      }

      final command = exchange.command;
      if (command.length >= 5 &&
          command[0] == 0x00 &&
          command[1] == 0xA4 &&
          command[2] == 0x04) {
        final lc = command[4];
        if (lc > 0 && command.length >= 5 + lc) {
          final name = bytesToHexUpper(command.sublist(5, 5 + lc));
          if (name != _ppse && name != _pse) aidHex = name;
        }
      }

      final pan = _panFromNodes(nodes);
      if (pan != null) {
        return EmvPanResult(
          pan: pan.pan,
          aid: aidHex.isNotEmpty ? aidHex : (candidates.isEmpty ? '' : candidates.first),
          sourceTag: pan.sourceTag,
          candidates: List.unmodifiable(
            candidates.isEmpty && aidHex.isNotEmpty ? [aidHex] : candidates,
          ),
        );
      }
    }

    throw const EmvCardException('No readable payment application on the card');
  }

  // ---------------------------------------------------------------------------
  // Application discovery
  // ---------------------------------------------------------------------------

  Future<List<String>> _discoverAids() async {
    final aids = <String>[];

    onProgress?.call('PPSE');
    final ppseResponse = await _select(hexToBytes(_ppse));
    if (_sw(ppseResponse) == 0x9000) {
      _addAids(aids, _tagValues(ppseResponse, '4F'));
    }

    if (aids.isEmpty) {
      onProgress?.call('PSE');
      final pseResponse = await _select(hexToBytes(_pse));
      if (_sw(pseResponse) == 0x9000) {
        final sfiValue = _tagValue(pseResponse, '88');
        final sfi = sfiValue != null && sfiValue.isNotEmpty ? sfiValue[0] : null;
        if (sfi != null) {
          final p2 = (sfi << 3) | 0x04;
          for (var record = 1; record <= 0xFF; record++) {
            final response = await _readRecord(record, p2);
            if (_sw(response) != 0x9000) break;
            _addAids(aids, _tagValues(response, '4F'));
          }
        }
      }
    }

    if (aids.isEmpty) {
      onProgress?.call('Fallback AIDs');
      for (final candidate in _fallbackAids) {
        final response = await _select(hexToBytes(candidate));
        if (_sw(response) != 0x9000) continue;
        final name = _tagValue(response, '84');
        _addAids(aids, [if (name != null && name.isNotEmpty) name else hexToBytes(candidate)]);
      }
    }

    return aids;
  }

  void _addAids(List<String> target, Iterable<Uint8List> values) {
    for (final value in values) {
      if (value.isEmpty) continue;
      final hex = bytesToHexUpper(value);
      if (!target.contains(hex)) target.add(hex);
    }
  }

  // ---------------------------------------------------------------------------
  // GET PROCESSING OPTIONS
  // ---------------------------------------------------------------------------

  /// Selects the current application's PDOL, sends GPO and returns the
  /// response, or `null` when the card refuses processing.
  Future<Uint8List?> _startProcessing(Uint8List selectResponse) async {
    final pdol = _tagValue(selectResponse, '9F38');
    final data = pdol == null ? Uint8List(0) : _buildPdolData(pdol);
    final payload = _wrapTag(0x83, data);
    if (payload.length > 0xFF) {
      throw const EmvCardException('PDOL data exceeds a short APDU');
    }
    final command = Uint8List.fromList([
      0x80, 0xA8, 0x00, 0x00, payload.length, //
      ...payload, 0x00,
    ]);
    final response = await _send!(command);
    return _sw(response) == 0x9000 ? response : null;
  }

  Uint8List _buildPdolData(Uint8List pdol) {
    final out = BytesBuilder(copy: false);
    for (final entry in _parsePdol(pdol)) {
      final tagHex = bytesToHexUpper(entry.tag);
      if (entry.length == 0) continue;
      if (tagHex == '9F37') {
        out.add(Uint8List.fromList(
          List<int>.generate(entry.length, (_) => _random.nextInt(256)),
        ));
        continue;
      }
      final preset = _pdolDefaults[tagHex];
      out.add(preset == null
          ? Uint8List(entry.length)
          : _fit(hexToBytes(preset), entry.length));
    }
    return out.takeBytes();
  }

  static Uint8List _fit(Uint8List preset, int length) {
    if (preset.length == length) return preset;
    final out = Uint8List(length);
    out.setRange(0, min(preset.length, length), preset);
    return out;
  }

  /// PDOL entries are `tag` + one-byte length, without values.
  static List<_PdolEntry> _parsePdol(Uint8List pdol) {
    final entries = <_PdolEntry>[];
    var pos = 0;
    while (pos < pdol.length) {
      final tagStart = pos++;
      if ((pdol[tagStart] & 0x1F) == 0x1F) {
        while (pos < pdol.length && (pdol[pos - 1] & 0x80) != 0) {
          pos++;
        }
      }
      if (pos >= pdol.length) break;
      final length = pdol[pos++];
      entries.add(_PdolEntry(
        Uint8List.fromList(pdol.sublist(tagStart, pos - 1)),
        length,
      ));
    }
    return entries;
  }

  // ---------------------------------------------------------------------------
  // AFL / READ RECORD
  // ---------------------------------------------------------------------------

  static Uint8List? _extractAfl(Uint8List gpoResponse) {
    final nodes = _parse(gpoResponse);
    if (nodes.isEmpty) return null;
    final first = nodes.first;
    if (first.tagHex == '80') {
      return first.value.length <= 2 ? Uint8List(0) : first.value.sublist(2);
    }
    return _first(_find(nodes, '94'))?.value;
  }

  Future<_PanSource?> _scanAfl(Uint8List afl) async {
    for (var offset = 0; offset + 4 <= afl.length; offset += 4) {
      final sfiByte = afl[offset];
      final firstRecord = afl[offset + 1];
      final lastRecord = afl[offset + 2];
      if (sfiByte == 0 || lastRecord == 0) continue;

      final sfi = sfiByte >> 3;
      if (sfi == 0) continue;
      final p2 = (sfi << 3) | 0x04;
      for (var record = firstRecord; record <= lastRecord; record++) {
        onProgress?.call('READ RECORD $record');
        final response = await _readRecord(record, p2);
        if (_sw(response) != 0x9000) break;
        final pan = _panFromRecord(response);
        if (pan != null) return pan;
      }
    }
    return null;
  }

  static _PanSource? _panFromRecord(Uint8List response) => _panFromNodes(_parse(response));

  static _PanSource? _panFromNodes(List<TlvNode> nodes) {
    final panNode = _first(_find(nodes, '5A'));
    if (panNode != null) {
      final pan = _cleanPan(_nibbles(panNode.value));
      if (pan != null) return _PanSource(pan, '5A');
    }

    final track2Node = _first(_find(nodes, '57'));
    if (track2Node != null) {
      final track2 = _nibbles(track2Node.value);
      final separator = track2.indexOf('D');
      if (separator > 0) {
        final pan = _cleanPan(track2.substring(0, separator));
        if (pan != null) return _PanSource(pan, '57');
      }
    }
    return null;
  }

  static String _nibbles(Uint8List value) {
    final out = StringBuffer();
    for (final byte in value) {
      out
        ..write((byte >> 4).toRadixString(16))
        ..write((byte & 0x0f).toRadixString(16));
    }
    return out.toString().toUpperCase();
  }

  /// Strips right-hand `F` padding and rejects anything that is not a
  /// plausible decimal PAN.
  static String? _cleanPan(String digits) {
    var out = digits;
    while (out.endsWith('F')) {
      out = out.substring(0, out.length - 1);
    }
    if (out.length < 8 || out.length > 19 || !RegExp(r'^\d+$').hasMatch(out)) {
      return null;
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // APDU helpers
  // ---------------------------------------------------------------------------

  Future<Uint8List> _select(Uint8List name) {
    if (name.isEmpty || name.length > 0xFF) {
      throw const EmvCardException('Invalid application identifier');
    }
    return _send!(Uint8List.fromList([
      0x00, 0xA4, 0x04, 0x00, name.length, //
      ...name, 0x00,
    ]));
  }

  Future<Uint8List> _readRecord(int record, int p2) =>
      _send!(Uint8List.fromList([0x00, 0xB2, record, p2, 0x00]));

  static int _sw(Uint8List response) =>
      response.length < 2 ? -1 : ((response[response.length - 2] << 8) | response[response.length - 1]);

  static List<TlvNode> _parse(Uint8List response) {
    if (response.length <= 2) return const [];
    return parseTlv(Uint8List.fromList(response.sublist(0, response.length - 2))).nodes;
  }

  static Iterable<TlvNode> _find(List<TlvNode> nodes, String tag) =>
      findTlvTag(nodes, tag);

  static TlvNode? _first(Iterable<TlvNode> nodes) {
    for (final node in nodes) {
      return node;
    }
    return null;
  }

  static Iterable<Uint8List> _tagValues(Uint8List response, String tag) =>
      _find(_parse(response), tag).map((node) => node.value);

  static Uint8List? _tagValue(Uint8List response, String tag) =>
      _first(_find(_parse(response), tag))?.value;

  /// Encodes one BER-TLV object with a short-form tag and BER length.
  static Uint8List _wrapTag(int tag, Uint8List data) {
    final out = BytesBuilder(copy: false)..addByte(tag);
    if (data.length < 0x80) {
      out.addByte(data.length);
    } else if (data.length <= 0xFF) {
      out.addByte(0x81);
      out.addByte(data.length);
    } else {
      out.addByte(0x82);
      out.addByte((data.length >> 8) & 0xFF);
      out.addByte(data.length & 0xFF);
    }
    out.add(data);
    return out.takeBytes();
  }
}

class _PdolEntry {
  const _PdolEntry(this.tag, this.length);
  final Uint8List tag;
  final int length;
}

class _PanSource {
  const _PanSource(this.pan, this.sourceTag);
  final String pan;
  final String sourceTag;
}
