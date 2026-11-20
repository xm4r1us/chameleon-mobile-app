import 'dart:typed_data';

import 'package:chameleon_cli/protocol/byte_utils.dart';
import 'package:chameleon_cli/protocol/emv_card.dart';
import 'package:flutter_test/flutter_test.dart';

const _ppseSelect = '00A404000E325041592E5359532E444446303100';
const _pseSelect = '00A404000E315041592E5359532E444446303100';

String _ok(String hex) => '${hex}9000';

String _selectAid(String aid) =>
    '00A4040007${aid.toUpperCase()}00';

/// Packs a transcript exactly like firmware command 6005 does.
Uint8List _scanPayload(List<List<String>> pairs) {
  final b = BytesBuilder();
  b.add([0x02, 0x11, 0x22]); // UID
  b.add([0x04, 0x00]); // ATQA
  b.addByte(0x00); // SAK
  b.addByte(0x00); // ATS length
  b.addByte(pairs.length);
  for (final pair in pairs) {
    final command = hexToBytes(pair[0]);
    final response = hexToBytes(pair[1]);
    b.addByte(command.length);
    b.add(command);
    b.addByte(response.length & 0xFF);
    b.addByte((response.length >> 8) & 0xFF);
    b.add(response);
  }
  return b.takeBytes();
}

class _Card {
  _Card(this.handler);

  final Future<Uint8List> Function(String requestHex) handler;
  final List<String> sent = [];

  Future<Uint8List> send(Uint8List apdu) {
    final hex = bytesToHexUpper(apdu);
    sent.add(hex);
    return handler(hex);
  }
}

Future<Uint8List> _bytes(String hex) async => hexToBytes(hex);

/// A card whose PPSE directory advertises one Visa AID and whose records
/// carry the PAN in tag `5A`.
_Card _ppseCard() => _Card((hex) async {
      if (hex == _ppseSelect) {
        return _bytes(_ok(
          '6F23840E325041592E5359532E4444463031A511BF0C0E610C'
          '4F07A0000000031010870101',
        ));
      }
      if (hex == _selectAid('A0000000031010')) {
        return _bytes(_ok(
          '6F198407A0000000031010A50E9F380B9F66049F02069F37049505',
        ));
      }
      if (hex.startsWith('80A80000')) {
        return _bytes(_ok('770A82021980940408010100'));
      }
      if (hex == '00B2010C00') {
        return _bytes(_ok('70145A0841111111111111115F24032512315F200100'));
      }
      return _bytes('6A82');
    });

void main() {
  group('EmvCardReader', () {
    test('reads the PAN through PPSE with a PDOL-driven GPO', () async {
      final card = _ppseCard();
      final reader = EmvCardReader(send: card.send);

      final result = await reader.readPan();

      expect(result.pan, '4111111111111111');
      expect(result.aid, 'A0000000031010');
      expect(result.sourceTag, '5A');
      expect(result.candidates, ['A0000000031010']);

      // PPSE, SELECT AID, GPO, READ RECORD.
      expect(card.sent, hasLength(4));
      final gpo = card.sent[2];
      expect(gpo.startsWith('80A8000015'), isTrue, reason: gpo);
      expect(gpo.endsWith('00'), isTrue);
      expect(gpo.substring(10, 12), '83');
      expect(gpo.substring(12, 14), '13');
      expect(gpo.substring(14, 22), '36004000'); // TTQ
      expect(gpo.substring(22, 34), '000000000100'); // amount
      expect(gpo.substring(42, 52), '0000000000'); // 95 terminal data
      expect(card.sent[3], '00B2010C00');
    });

    test('falls back to PSE and reads tag 57 track 2 data', () async {
      var aidSelected = false;
      final card = _Card((hex) async {
        if (hex == _pseSelect) {
          return _bytes(_ok(
            '6F13840E315041592E5359532E4444463031880101',
          ));
        }
        if (hex == '00B2010C00' && !aidSelected) {
          // PSE record 1 advertises the AID.
          return _bytes(_ok('700C4F07A0000000031010500100'));
        }
        if (hex == '00B2020C00') {
          return _bytes('6A83');
        }
        if (hex == _selectAid('A0000000031010')) {
          aidSelected = true;
          return _bytes(_ok('6F098407A0000000031010'));
        }
        if (hex == '80A8000002830000') {
          return _bytes(_ok('8006198008010100'));
        }
        if (hex == '00B2010C00') {
          return _bytes(_ok('701357114111111111111111D2512201123456789F'));
        }
        return _bytes('6A82');
      });

      final result = await EmvCardReader(send: card.send).readPan();

      expect(result.pan, '4111111111111111');
      expect(result.sourceTag, '57');
      expect(result.aid, 'A0000000031010');
    });

    test('probes the fallback AID list when both directories are absent', () async {
      final card = _Card((hex) async {
        if (hex == _selectAid('A0000000031010')) {
          return _bytes(_ok('6F098407A0000000031010'));
        }
        if (hex == '80A8000002830000') {
          return _bytes(_ok('8006198008010100'));
        }
        if (hex == '00B2010C00') {
          return _bytes(_ok('70145A0841111111111111115F24032512315F200100'));
        }
        return _bytes('6A82');
      });

      final result = await EmvCardReader(send: card.send).readPan();

      expect(result.pan, '4111111111111111');
      // PPSE, PSE, the seven known AIDs and the processing select.
      expect(card.sent[2], _selectAid('A0000000031010'));
      expect(
        card.sent.where((command) => command.startsWith('00A40400')).length,
        10,
      );
    });

    test('strips right-hand F padding from tag 5A', () async {
      final card = _Card((hex) async {
        if (hex == _ppseSelect) {
          return _bytes(_ok(
            '6F23840E325041592E5359532E4444463031A511BF0C0E610C'
            '4F07A0000000031010870101',
          ));
        }
        if (hex == _selectAid('A0000000031010')) {
          return _bytes(_ok('6F198407A0000000031010A50E9F380B9F66049F02069F37049505'));
        }
        if (hex.startsWith('80A80000')) {
          return _bytes(_ok('770A82021980940408010100'));
        }
        if (hex == '00B2010C00') {
          return _bytes(_ok('700C5A0A4111111111111111111F'));
        }
        return _bytes('6A82');
      });

      final result = await EmvCardReader(send: card.send).readPan();

      expect(result.pan, '4111111111111111111');
    });

    test('reads the PAN from a firmware EMV transcript', () async {
      final payload = _scanPayload([
        [
          _ppseSelect,
          _ok('6F23840E325041592E5359532E4444463031A511BF0C0E610C'
              '4F07A0000000031010870101'),
        ],
        [
          _selectAid('A0000000031010'),
          _ok('6F198407A0000000031010A50E9F380B9F66049F02069F37049505'),
        ],
        ['80A8000002830000', _ok('770A82021980940408010100')],
        ['00B2010C00', _ok('70145A0841111111111111115F24032512315F200100')],
      ]);

      final result = await EmvCardReader(scan: () async => parseEmvScan(payload)).readPan();

      expect(result.pan, '4111111111111111');
      expect(result.aid, 'A0000000031010');
      expect(result.sourceTag, '5A');
      expect(result.candidates, ['A0000000031010']);
    });

    test('rejects a truncated firmware transcript', () {
      expect(
        () => parseEmvScan(hexToBytes('02112204000000')),
        throwsA(isA<EmvCardException>()),
      );
    });

    test('throws when no application can be started', () async {
      final card = _Card((_) async => _bytes('6A82'));

      await expectLater(
        EmvCardReader(send: card.send).readPan(),
        throwsA(isA<EmvCardException>()),
      );
    });
  });
}
