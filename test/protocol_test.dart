import 'dart:typed_data';

import 'package:chameleon_cli/protocol/byte_utils.dart';
import 'package:chameleon_cli/protocol/client.dart';
import 'package:chameleon_cli/protocol/commands.dart';
import 'support/fake_transport.dart';
import 'package:chameleon_cli/protocol/frame.dart';
import 'package:chameleon_cli/protocol/tag_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Frame', () {
    test('encodes the documented GET_SLOT_INFO frame', () {
      final frame = ChameleonFrame(Cmd.getSlotInfo, 0, Uint8List(0)).encode();
      expect(bytesToHex(frame), '11ef03fb000000000200');
    });

    test('round-trips payload and status', () {
      final data = Uint8List.fromList([1, 2, 3, 4]);
      final frame = ChameleonFrame(Cmd.hf14aRaw, Status.hfTagOk, data);
      final decoded = FrameDecoder().add(frame.encode()).single;
      expect(decoded.command, Cmd.hf14aRaw);
      expect(decoded.status, Status.hfTagOk);
      expect(decoded.data, data);
    });

    test('decoder handles split notifications and junk', () {
      final encoded = ChameleonFrame(Cmd.getAppVersion, Status.success, Uint8List.fromList([2, 1])).encode();
      final decoder = FrameDecoder();
      expect(decoder.add([0x99, 0x88]), isEmpty);
      expect(decoder.add(encoded.sublist(0, 3)), isEmpty);
      final frames = decoder.add(encoded.sublist(3));
      expect(frames, hasLength(1));
      expect(frames.single.data, [2, 1]);
    });

    test('decoder drops a frame with a broken checksum and resyncs', () {
      final broken = ChameleonFrame(Cmd.getAppVersion, Status.success, Uint8List.fromList([2, 1])).encode();
      broken[broken.length - 1] ^= 0xff;
      final good = ChameleonFrame(Cmd.getAppVersion, Status.success, Uint8List.fromList([3, 4])).encode();
      final frames = FrameDecoder().add([...broken, ...good]);
      expect(frames, hasLength(1));
      expect(frames.single.data, [3, 4]);
    });

    test('LRC is the two-complement of the byte sum', () {
      expect(ChameleonFrame.lrc([0x11]), 0xef);
      expect(ChameleonFrame.lrc([0x01, 0x02]), 0xfd);
      expect(ChameleonFrame.lrc([]), 0x00);
    });
  });

  group('Client with fake transport', () {
    late ChameleonClient client;

    setUp(() async {
      final transport = FakeTransport();
      await transport.connect();
      client = ChameleonClient(transport);
      client.open();
    });

    tearDown(() => client.close());

    test('reads version, battery and slots', () async {
      final version = await client.getVersion();
      expect(version.version, '2.1');
      expect(version.gitVersion, 'v2.1.0-test');

      final battery = await client.getBattery();
      expect(battery.percentage, 87);

      final slots = await client.getSlots();
      expect(slots, hasLength(8));
      expect(slots[0].hfType.id, TagTypes.mifare1024.id);
      expect(slots[0].hfEnabled, isTrue);
      expect(slots[0].active, isTrue);
      expect(slots[1].lfType.id, TagTypes.em410x.id);
      expect(slots[0].hfNick, 'Test Classic 1K');
    });

    test('scans a 14A tag', () async {
      final tags = await client.scanHf();
      expect(tags, hasLength(1));
      expect(tags.single.uidHex, 'DEADBEEF');
      expect(tags.single.sakHex, '08');
    });

    test('reads a block with the default key and rejects a wrong key', () async {
      final block = await client.mf1ReadBlock(1, MifareClassic.keyA, Uint8List.fromList([0xff, 0xff, 0xff, 0xff, 0xff, 0xff]));
      expect(block.sublist(0, 8), 'CHAMELEO'.codeUnits);

      expect(
        () => client.mf1ReadBlock(1, MifareClassic.keyA, Uint8List.fromList([0, 0, 0, 0, 0, 0])),
        throwsA(isA<ChameleonException>()),
      );
    });

    test('finds keys for all sectors', () async {
      final result = await client.checkKeysOfSectors(
        mask: Uint8List(10),
        keys: [Uint8List.fromList([0xff, 0xff, 0xff, 0xff, 0xff, 0xff])],
      );
      expect(result.keys, hasLength(80));
      expect(result.keys[0], [0xff, 0xff, 0xff, 0xff, 0xff, 0xff]);
    });
  });

  group('Tag types', () {
    test('classic sector math matches 4K layout', () {
      expect(MifareClassic.sectorForBlock(0), 0);
      expect(MifareClassic.sectorForBlock(127), 31);
      expect(MifareClassic.sectorForBlock(128), 32);
      expect(MifareClassic.sectorForBlock(255), 39);
      expect(MifareClassic.firstBlockOfSector(32), 128);
      expect(MifareClassic.blockCountOfSector(32), 16);
      expect(MifareClassic.trailerBlockOfSector(32), 143);
    });

    test('guesses classic variants from SAK and dump length', () {
      expect(TagTypes.guessClassicFromSak(0x08)?.id, TagTypes.mifare1024.id);
      expect(TagTypes.guessClassicFromSak(0x18)?.id, TagTypes.mifare4096.id);
      expect(TagTypes.guessClassicFromSak(0x09)?.id, TagTypes.mifareMini.id);
      expect(TagTypes.fromDumpLength(1024)?.id, TagTypes.mifare1024.id);
      expect(TagTypes.fromDumpLength(924)?.id, TagTypes.ntag216.id);
    });
  });
}
