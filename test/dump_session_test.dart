import 'dart:convert';
import 'dart:typed_data';

import 'package:chameleon_cli/models/dump.dart';
import 'package:chameleon_cli/protocol/byte_utils.dart';
import 'package:chameleon_cli/protocol/tag_types.dart';
import 'package:chameleon_cli/services/device_session.dart';

import 'support/fake_transport.dart';
import 'package:chameleon_cli/services/dump_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Dump codec', () {
    Uint8List classicDump() {
      final data = Uint8List(1024);
      for (var sector = 0; sector < 16; sector++) {
        final trailer = sector * 4 + 3;
        data.setRange(trailer * 16, trailer * 16 + 6, List<int>.filled(6, 0xff));
        data.setRange(trailer * 16 + 6, trailer * 16 + 9, [0xff, 0x07, 0x80]);
        data.setRange(trailer * 16 + 10, trailer * 16 + 16, List<int>.filled(6, 0xff));
      }
      return data;
    }

    test('imports a 1K binary dump', () {
      final record = DumpCodec.decodeFile('card.bin', classicDump());
      expect(record, isNotNull);
      expect(record!.kind, DumpKind.mf1);
      expect(record.tagTypeId, TagTypes.mifare1024.id);
      expect(record.data.length, 1024);
    });

    test('imports and re-exports .eml', () {
      final bytes = Uint8List.fromList(
        utf8.encode(
          [for (var i = 0; i < 1024; i += 16) bytesToHex(classicDump().sublist(i, i + 16))].join('\n'),
        ),
      );
      final record = DumpCodec.decodeFile('card.eml', bytes);
      expect(record?.kind, DumpKind.mf1);
      final eml = DumpCodec.encodeEml(record!);
      final reimported = DumpCodec.decodeFile('again.eml', Uint8List.fromList(utf8.encode(eml)));
      expect(reimported?.data, record.data);
    });

    test('MFU .eml comments are ignored and version is preserved separately', () {
      final pages = Uint8List(45 * 4);
      pages[0] = 0xde;
      final record = DumpRecord(
        id: 'x',
        name: 'ntag',
        kind: DumpKind.mfu,
        tagTypeId: TagTypes.ntag213.id,
        data: pages,
        createdAt: DateTime(2026),
        version: Uint8List.fromList([0, 4, 4, 2, 1, 0, 0x0f, 3]),
      );
      final eml = DumpCodec.encodeEml(record);
      expect(eml, contains('# Version: 0004040201000f03'));
      final reimported = DumpCodec.decodeFile('ntag.eml', Uint8List.fromList(utf8.encode(eml)));
      expect(reimported?.data.length, pages.length);
      expect(reimported?.data[0], 0xde);
    });

    test('JSON round-trips keys and metadata', () {
      final record = DumpRecord(
        id: 'id-1',
        name: 'keycard',
        kind: DumpKind.mf1,
        tagTypeId: TagTypes.mifare1024.id,
        data: classicDump(),
        createdAt: DateTime(2026, 1, 2),
        keys: Mf1Keys(
          keyA: {0: Uint8List.fromList([0xff, 0xff, 0xff, 0xff, 0xff, 0xff])},
          keyB: {3: Uint8List.fromList([0x01, 0x02, 0x03, 0x04, 0x05, 0x06])},
        ),
      );
      final decoded = DumpRecord.fromJson(jsonDecode(DumpCodec.encodeJson(record)) as Map<String, dynamic>);
      expect(decoded.name, 'keycard');
      expect(decoded.data, record.data);
      expect(decoded.keys.keyA[0], [0xff, 0xff, 0xff, 0xff, 0xff, 0xff]);
      expect(decoded.keys.keyB[3], [1, 2, 3, 4, 5, 6]);
    });

    test('key dictionary parses comments and duplicates', () {
      final text = 'FFFFFFFFFFFF\n# comment\nA0A1A2A3A4A5\nffffffffffff\nnot-a-key\n';
      final keys = DumpCodec.parseKeyDictionary(text);
      expect(keys, hasLength(2));
      expect(keys.map(bytesToHexUpper), containsAll(['FFFFFFFFFFFF', 'A0A1A2A3A4A5']));
    });
  });

  group('DeviceSession with fake device', () {
    late DeviceSession session;

    setUp(() async {
      session = DeviceSession();
      final ok = await session.connectTransport(FakeTransport());
      expect(ok, isTrue);
    });

    tearDown(() => session.dispose());

    test('reads, re-loads and verifies a Classic dump', () async {
      final dump = await session.readMf1Dump(
        type: TagTypes.mifare1024,
        keys: [Uint8List.fromList(List<int>.filled(6, 0xff))],
        name: 'test',
      );
      expect(dump.data.length, 1024);
      expect(dump.keys.keyA, hasLength(16));
      expect(dump.keys.keyB, hasLength(16));
      expect(dump.data.sublist(16, 24), 'CHAMELEO'.codeUnits);
      expect(dump.data.sublist(0, 4), [0xde, 0xad, 0xbe, 0xef]);

      final slot = session.activeSlot!;
      await session.writeMf1DumpToSlot(dump, firmwareSlot: slot.index);
      final emulated = await session.readMf1EmulatorDump(name: 'emu');
      expect(emulated.data.sublist(0, 1024), dump.data);
    });

    test('reads a 4K dump with the extended sector layout', () async {
      final dump = await session.readMf1Dump(
        type: TagTypes.mifare4096,
        keys: [Uint8List.fromList(List<int>.filled(6, 0xff))],
        name: '4k',
      );
      expect(dump.data.length, 4096);
      expect(dump.keys.keyA, hasLength(40));
      expect(dump.keys.keyB, hasLength(40));
      // Sector 32 starts at block 128 and its trailer is block 143.
      expect(dump.data.sublist(143 * 16, 143 * 16 + 6), List<int>.filled(6, 0xff));
    });

    test('reads an NTAG dump and loads it into the slot', () async {
      final dump = await session.readMfuDump(
        type: TagTypes.ntag213,
        name: 'ntag',
      );
      expect(dump.data.length, 45 * 4);
      expect(dump.version, isNotNull);
      final slot = session.activeSlot!;
      await session.writeMfuDumpToSlot(dump, firmwareSlot: slot.index);
      final emulated = await session.readMfuEmulatorDump(name: 'emu');
      expect(emulated.data.length, 45 * 4);
      expect(emulated.data.sublist(0, 16), dump.data.sublist(0, 16));
    });

    test('scans and emulates an EM410x id', () async {
      final tag = await session.scanLf(TagTypes.em410x);
      expect(tag, isNotNull);
      expect(tag!.raw, hasLength(5));
      final slot = 2;
      await session.writeLfToSlot(tag, firmwareSlot: slot - 1);
      final id = await session.readLfEmulatorId(TagTypes.em410x);
      expect(id, tag.raw);
    });

    test('configures and verifies slot metadata', () async {
      await session.configureSlot(
        firmwareSlot: 3,
        type: TagTypes.mifare4096,
        nick: 'test',
        activate: true,
        initialize: true,
      );
      final slot = session.slots[3];
      expect(slot.hfType.id, TagTypes.mifare4096.id);
      expect(slot.hfNick, 'test');
      expect(slot.active, isTrue);
    });
  });
}
