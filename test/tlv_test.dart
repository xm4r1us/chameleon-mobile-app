import 'package:chameleon_cli/protocol/byte_utils.dart';
import 'package:chameleon_cli/protocol/tlv.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BER-TLV', () {
    test('parses a constructed tag and its child', () {
      final result = parseTlv(hexToBytes('6F098407A0000000031010'));
      expect(result.error, isNull);
      expect(result.nodes, hasLength(1));
      final root = result.nodes.single;
      expect(root.tagHex, '6F');
      expect(root.constructed, isTrue);
      expect(root.children, hasLength(1));
      expect(root.children.single.tagHex, '84');
      expect(bytesToHexUpper(root.children.single.value), 'A0000000031010');
    });

    test('parses multiple primitive objects and long lengths', () {
      final result = parseTlv(hexToBytes('5A0212345F200101'));
      expect(result.error, isNull);
      expect(result.nodes.map((n) => n.tagHex), ['5A', '5F20']);
      expect(result.nodes.last.value, [1]);

      final long = parseTlv(hexToBytes('5A81051234567890'));
      expect(long.error, isNull);
      expect(long.nodes.single.value, [0x12, 0x34, 0x56, 0x78, 0x90]);
    });

    test('reports truncated data instead of throwing', () {
      final result = parseTlv(hexToBytes('6F098407A0'));
      expect(result.error, isNotNull);
      expect(result.nodes, isEmpty);
    });

    test('describes common status words', () {
      expect(swDescription(0x9000), 'OK');
      expect(swDescription(0x6A82), contains('not found'));
      expect(swDescription(0x6D00), contains('Instruction'));
    });
  });
}
