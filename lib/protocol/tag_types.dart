import 'dart:typed_data';

enum TagSense {
  lf(1, 'LF', '125 kHz'),
  hf(2, 'HF', '13.56 MHz');

  const TagSense(this.value, this.shortName, this.frequency);
  final int value;
  final String shortName;
  final String frequency;

  static TagSense? fromValue(int value) {
    for (final sense in TagSense.values) {
      if (sense.value == value) return sense;
    }
    return null;
  }
}

class TagType {
  final int id;
  final String name;
  final TagSense sense;
  final int? mf1Blocks;
  final int? mfuPages;

  const TagType(
    this.id,
    this.name,
    this.sense, {
    this.mf1Blocks,
    this.mfuPages,
  });

  bool get isMifareClassic => mf1Blocks != null;
  bool get isUltralight => mfuPages != null;
  bool get isLf => sense == TagSense.lf;

  bool get isKnown => id != 0;

  String get slotLabel => isKnown ? name : 'Empty';

  @override
  String toString() => name;
}

/// Tag specific types (`tag_specific_type_t` in firmware).
class TagTypes {
  static const undefined = TagType(0, 'Empty', TagSense.hf);

  // LF
  static const em410x = TagType(100, 'EM410x', TagSense.lf);
  static const em410x16 = TagType(101, 'EM410x/16', TagSense.lf);
  static const em410x32 = TagType(102, 'EM410x/32', TagSense.lf);
  static const em410x64 = TagType(103, 'EM410x/64', TagSense.lf);
  static const em410xElectra = TagType(104, 'EM410x Electra', TagSense.lf);
  static const pac = TagType(150, 'PAC/Stanley', TagSense.lf);
  static const viking = TagType(170, 'Viking', TagSense.lf);
  static const jablotron = TagType(180, 'Jablotron', TagSense.lf);
  static const hidProx = TagType(200, 'HID Prox', TagSense.lf);
  static const ioProx = TagType(201, 'ioProx', TagSense.lf);
  static const pyramid = TagType(202, 'Pyramid', TagSense.lf);
  static const idteck = TagType(310, 'IDTECK', TagSense.lf);

  // HF, MIFARE Classic
  static const mifareMini = TagType(1000, 'MIFARE Classic Mini', TagSense.hf, mf1Blocks: 20);
  static const mifare1024 = TagType(1001, 'MIFARE Classic 1K', TagSense.hf, mf1Blocks: 64);
  static const mifare2048 = TagType(1002, 'MIFARE Classic 2K', TagSense.hf, mf1Blocks: 128);
  static const mifare4096 = TagType(1003, 'MIFARE Classic 4K', TagSense.hf, mf1Blocks: 256);

  // HF, MIFARE Ultralight / NTAG
  static const ntag213 = TagType(1100, 'NTAG 213', TagSense.hf, mfuPages: 45);
  static const ntag215 = TagType(1101, 'NTAG 215', TagSense.hf, mfuPages: 135);
  static const ntag216 = TagType(1102, 'NTAG 216', TagSense.hf, mfuPages: 231);
  static const mf0icu1 = TagType(1103, 'MIFARE Ultralight', TagSense.hf, mfuPages: 16);
  static const mf0icu2 = TagType(1104, 'MIFARE Ultralight C', TagSense.hf, mfuPages: 48);
  static const mf0ul11 = TagType(1105, 'MIFARE Ultralight EV1 (640 bit)', TagSense.hf, mfuPages: 20);
  static const mf0ul21 = TagType(1106, 'MIFARE Ultralight EV1 (1312 bit)', TagSense.hf, mfuPages: 41);
  static const ntag210 = TagType(1107, 'NTAG 210', TagSense.hf, mfuPages: 20);
  static const ntag212 = TagType(1108, 'NTAG 212', TagSense.hf, mfuPages: 41);

  // HF, ISO14443-4
  static const hf14a4 = TagType(3000, 'ISO14443-4 T=CL', TagSense.hf);
  static const seos = TagType(3001, 'SEOS', TagSense.hf);

  static const List<TagType> all = [
    em410x,
    em410x16,
    em410x32,
    em410x64,
    em410xElectra,
    pac,
    viking,
    jablotron,
    hidProx,
    ioProx,
    pyramid,
    idteck,
    mifareMini,
    mifare1024,
    mifare2048,
    mifare4096,
    ntag213,
    ntag215,
    ntag216,
    mf0icu1,
    mf0icu2,
    mf0ul11,
    mf0ul21,
    ntag210,
    ntag212,
    hf14a4,
    seos,
  ];

  static final Map<int, TagType> _byId = {for (final t in all) t.id: t};

  static TagType byId(int id) => _byId[id] ?? TagType(id, 'Tag type $id', id < 1000 ? TagSense.lf : TagSense.hf);

  static List<TagType> get hf => all.where((t) => t.sense == TagSense.hf).toList();
  static List<TagType> get lf => all.where((t) => t.sense == TagSense.lf).toList();

  static const List<TagType> mifareClassic = [mifareMini, mifare1024, mifare2048, mifare4096];
  static const List<TagType> ultralight = [ntag213, ntag215, ntag216, mf0icu1, mf0icu2, mf0ul11, mf0ul21, ntag210, ntag212];

  /// Guesses the MIFARE Classic variant from SAK / ATQA and dump size.
  static TagType? guessClassicFromSak(int sak) {
    switch (sak) {
      case 0x09:
        return mifareMini;
      case 0x08:
        return mifare1024;
      case 0x18:
        return mifare4096;
      case 0x10:
      case 0x11:
      case 0x19:
        return mifare2048;
      default:
        return null;
    }
  }

  static TagType? fromDumpLength(int bytes) {
    switch (bytes) {
      case 320:
        return mifareMini;
      case 1024:
        return mifare1024;
      case 2048:
        return mifare2048;
      case 4096:
        return mifare4096;
      case 64:
        return mf0icu1;
      case 180:
        return ntag213;
      case 540:
        return ntag215;
      case 924:
        return ntag216;
      case 80:
        return mf0ul11;
      case 164:
        return mf0ul21; // also NTAG 212
      case 192:
        return mf0icu2;
      default:
        return null;
    }
  }
}

/// MIFARE Classic helpers.
class MifareClassic {
  static const int keyA = 0x60;
  static const int keyB = 0x61;

  static int sectorCountForBlocks(int blocks) {
    if (blocks <= 20) return 5;
    if (blocks <= 64) return 16;
    if (blocks <= 128) return 32;
    if (blocks <= 256) return 40;
    return 40;
  }

  static int blocksForSectors(int sectors) => sectors <= 32 ? sectors * 4 : 128 + (sectors - 32) * 16;

  /// Sector index for a block, honouring the 4K layout (32 x 4 blocks + 8 x 16).
  static int sectorForBlock(int block) {
    if (block < 128) return block ~/ 4;
    return 32 + (block - 128) ~/ 16;
  }

  static int firstBlockOfSector(int sector) => sector < 32 ? sector * 4 : 128 + (sector - 32) * 16;

  static int blockCountOfSector(int sector) => sector < 32 ? 4 : 16;

  static int trailerBlockOfSector(int sector) =>
      firstBlockOfSector(sector) + blockCountOfSector(sector) - 1;

  static int sectorCountForType(TagType type) => sectorCountForBlocks(type.mf1Blocks ?? 64);

  static bool isTrailerBlock(int block) => block == trailerBlockOfSector(sectorForBlock(block));

  static Uint8List defaultBlock0() => Uint8List.fromList([
        0xDE, 0xAD, 0xBE, 0xEF,
        0x62, 0x63, 0x64, 0x65,
        0x66, 0x67, 0x68, 0x69,
        0x08, 0x04, 0x00, 0x00,
      ]);
}

/// Converts between firmware (0-based) and UI (1-based) slot numbers.
class SlotNumber {
  static int toFirmware(int uiSlot) {
    if (uiSlot < 1 || uiSlot > 8) throw RangeError.range(uiSlot, 1, 8, 'slot');
    return uiSlot - 1;
  }

  static int toUi(int firmwareSlot) {
    if (firmwareSlot < 0 || firmwareSlot > 7) throw RangeError.range(firmwareSlot, 0, 7, 'slot');
    return firmwareSlot + 1;
  }
}
