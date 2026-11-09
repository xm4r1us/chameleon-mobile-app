import 'dart:typed_data';

import '../protocol/byte_utils.dart';
import '../protocol/tag_types.dart';

class DeviceVersion {
  DeviceVersion({
    required this.major,
    required this.minor,
    this.gitVersion,
    this.model,
  });

  final int major;
  final int minor;
  final String? gitVersion;
  final int? model; // 0 Ultra, 1 Lite

  String get version => '$major.$minor';
  String get modelName => model == 1 ? 'Chameleon Lite' : 'Chameleon Ultra';

  bool get supportsFieldOffReset => major > 2 || (major == 2 && minor >= 0);
}

class BatteryInfo {
  const BatteryInfo(this.voltageMv, this.percentage);
  final int voltageMv;
  final int percentage;

  String get voltage => '${(voltageMv / 1000).toStringAsFixed(2)} V';
}

class SlotInfo {
  SlotInfo({
    required this.index,
    required this.hfType,
    required this.lfType,
    required this.hfEnabled,
    required this.lfEnabled,
    this.hfNick = '',
    this.lfNick = '',
    this.active = false,
  });

  final int index; // 0..7 firmware index
  final TagType hfType;
  final TagType lfType;
  final bool hfEnabled;
  final bool lfEnabled;
  final String hfNick;
  final String lfNick;
  final bool active;

  int get number => index + 1;

  bool get hasHf => hfType.id != 0;
  bool get hasLf => lfType.id != 0;

  String get title {
    if (hasHf) return hfNick.isNotEmpty ? hfNick : hfType.name;
    if (hasLf) return lfNick.isNotEmpty ? lfNick : lfType.name;
    return 'Empty slot';
  }

  SlotInfo copyWith({
    TagType? hfType,
    TagType? lfType,
    bool? hfEnabled,
    bool? lfEnabled,
    String? hfNick,
    String? lfNick,
    bool? active,
  }) =>
      SlotInfo(
        index: index,
        hfType: hfType ?? this.hfType,
        lfType: lfType ?? this.lfType,
        hfEnabled: hfEnabled ?? this.hfEnabled,
        lfEnabled: lfEnabled ?? this.lfEnabled,
        hfNick: hfNick ?? this.hfNick,
        lfNick: lfNick ?? this.lfNick,
        active: active ?? this.active,
      );
}

class AntiCollData {
  AntiCollData({
    required this.uid,
    required this.atqa,
    required this.sak,
    required this.ats,
  });

  final Uint8List uid;
  final Uint8List atqa;
  final int sak;
  final Uint8List ats;

  String get uidHex => bytesToHexUpper(uid);
  String get atqaHex => bytesToHexUpper(atqa);
  String get sakHex => sak.toRadixString(16).padLeft(2, '0').toUpperCase();
  String get atsHex => bytesToHexUpper(ats);

  static AntiCollData? parse(Uint8List data, [int offset = 0]) {
    if (data.length < offset + 5) return null;
    var pos = offset;
    final uidLen = data[pos++];
    if (uidLen == 0 || pos + uidLen + 4 > data.length) return null;
    final uid = Uint8List.fromList(data.sublist(pos, pos + uidLen));
    pos += uidLen;
    final atqa = Uint8List.fromList(data.sublist(pos, pos + 2));
    pos += 2;
    final sak = data[pos++];
    final atsLen = data[pos++];
    if (pos + atsLen > data.length) return null;
    final ats = Uint8List.fromList(data.sublist(pos, pos + atsLen));
    return AntiCollData(uid: uid, atqa: atqa, sak: sak, ats: ats);
  }

  Uint8List encode() {
    final out = BytesBuilder();
    out.addByte(uid.length);
    out.add(uid);
    out.add(atqa);
    out.addByte(sak);
    out.addByte(ats.length);
    out.add(ats);
    return out.toBytes();
  }
}

class HfScanResult {
  HfScanResult({
    required this.coll,
    this.isClassic = false,
    this.prngLevel,
  });

  final AntiCollData coll;
  final bool isClassic;
  final int? prngLevel; // 0 static, 1 weak, 2 hard

  String get prngName => switch (prngLevel) {
        0 => 'Static nonce',
        1 => 'Weak PRNG',
        2 => 'Hard PRNG',
        _ => 'Unknown',
      };

  TagType? get guessedType {
    final bySak = TagTypes.guessClassicFromSak(coll.sak);
    if (bySak != null) return bySak;
    if (coll.sak == 0x00 && (coll.atqa[0] == 0x44 || coll.atqa[1] == 0x44)) {
      return TagTypes.ntag213;
    }
    return null;
  }
}

class LfScanResult {
  LfScanResult({
    required this.type,
    required this.raw,
    required this.summary,
    this.fields = const {},
  });

  final TagType type;
  final Uint8List raw;
  final String summary;
  final Map<String, String> fields;

  String get rawHex => bytesToHexUpper(raw);
}

class Mf1EmulatorConfig {
  Mf1EmulatorConfig({
    required this.detection,
    required this.gen1a,
    required this.gen2,
    required this.blockAntiColl,
    required this.writeMode,
    this.fieldOffReset = false,
    this.prngType = 1,
  });

  final bool detection;
  final bool gen1a;
  final bool gen2;
  final bool blockAntiColl;
  final int writeMode;
  final bool fieldOffReset;
  final int prngType;
}

class Mf1DetectionRecord {
  Mf1DetectionRecord({
    required this.block,
    required this.keyType,
    required this.isNested,
    required this.uid,
    required this.nt,
    required this.nr,
    required this.ar,
  });

  final int block;
  final String keyType; // A/B
  final bool isNested;
  final Uint8List uid;
  final Uint8List nt;
  final Uint8List nr;
  final Uint8List ar;

  int get uidInt => u32(uid);
  int get ntInt => u32(nt);
  int get nrInt => u32(nr);
  int get arInt => u32(ar);
}

class Mf1NestedNonce {
  const Mf1NestedNonce(this.nt, this.ntEnc, this.par);
  final int nt;
  final int ntEnc;
  final int par;
}

class Mf1NestedData {
  const Mf1NestedData({
    required this.uid,
    this.distance,
    required this.nonces,
  });

  final int uid;
  final int? distance;
  final List<Mf1NestedNonce> nonces;
}

class Mf1StaticNestedData {
  const Mf1StaticNestedData({required this.uid, required this.nonces});
  final int uid;
  final List<Mf1NestedNonce> nonces;
}

class Mf1DarksideData {
  const Mf1DarksideData({
    required this.status,
    required this.uid,
    required this.nt1,
    required this.par,
    required this.ks1,
    required this.nr,
    required this.ar,
  });

  final int status;
  final int uid;
  final int nt1;
  final int par;
  final int ks1;
  final int nr;
  final int ar;

  bool get ok => status == 0;
}

class MfuConfig {
  MfuConfig({
    required this.uidMagic,
    required this.writeMode,
    this.detection = false,
    this.version = const [],
    this.signature = const [],
  });

  final bool uidMagic;
  final int writeMode;
  final bool detection;
  final List<int> version;
  final List<int> signature;
}

class DeviceSettings {
  DeviceSettings({
    required this.animationMode,
    required this.buttonPressA,
    required this.buttonPressB,
    required this.longPressA,
    required this.longPressB,
    required this.blePairingEnabled,
    required this.blePairingKey,
    required this.sleepTimeout,
    required this.longPressThreshold,
  });

  final int animationMode;
  final int buttonPressA;
  final int buttonPressB;
  final int longPressA;
  final int longPressB;
  final bool blePairingEnabled;
  final String blePairingKey;
  final int sleepTimeout;
  final int longPressThreshold;
}
