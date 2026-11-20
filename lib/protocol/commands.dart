/// Protocol command IDs. Values come from the official Chameleon Ultra
/// firmware (`data_cmd.h` / protocol wiki).
class Cmd {
  static const int getAppVersion = 1000;
  static const int changeDeviceMode = 1001;
  static const int getDeviceMode = 1002;
  static const int setActiveSlot = 1003;
  static const int setSlotTagType = 1004;
  static const int setSlotDataDefault = 1005;
  static const int setSlotEnable = 1006;
  static const int setSlotTagNick = 1007;
  static const int getSlotTagNick = 1008;
  static const int slotDataConfigSave = 1009;
  static const int enterBootloader = 1010;
  static const int getDeviceChipId = 1011;
  static const int getDeviceAddress = 1012;
  static const int saveSettings = 1013;
  static const int resetSettings = 1014;
  static const int setAnimationMode = 1015;
  static const int getAnimationMode = 1016;
  static const int getGitVersion = 1017;
  static const int getActiveSlot = 1018;
  static const int getSlotInfo = 1019;
  static const int wipeFds = 1020;
  static const int deleteSlotTagNick = 1021;
  static const int getEnabledSlots = 1023;
  static const int deleteSlotSenseType = 1024;
  static const int getBatteryInfo = 1025;
  static const int getButtonPressConfig = 1026;
  static const int setButtonPressConfig = 1027;
  static const int getLongButtonPressConfig = 1028;
  static const int setLongButtonPressConfig = 1029;
  static const int setBlePairingKey = 1030;
  static const int getBlePairingKey = 1031;
  static const int deleteAllBleBonds = 1032;
  static const int getDeviceModel = 1033;
  static const int getDeviceSettings = 1034;
  static const int getDeviceCapabilities = 1035;
  static const int getBlePairingEnable = 1036;
  static const int setBlePairingEnable = 1037;
  static const int getAllSlotNicks = 1038;
  static const int getSleepTimeout = 1039;
  static const int setSleepTimeout = 1040;
  static const int getLongPressThreshold = 1041;
  static const int setLongPressThreshold = 1042;
  static const int getBatteryInfoEx = 1043;

  static const int hf14aScan = 2000;
  static const int mf1DetectSupport = 2001;
  static const int mf1DetectPrng = 2002;
  static const int mf1StaticNestedAcquire = 2003;
  static const int mf1DarksideAcquire = 2004;
  static const int mf1DetectNtDist = 2005;
  static const int mf1NestedAcquire = 2006;
  static const int mf1AuthOneKeyBlock = 2007;
  static const int mf1ReadOneBlock = 2008;
  static const int mf1WriteOneBlock = 2009;
  static const int hf14aRaw = 2010;
  static const int mf1ManipulateValueBlock = 2011;
  static const int mf1CheckKeysOfSectors = 2012;
  static const int mf1HardNestedAcquire = 2013;
  static const int mf1EncNestedAcquire = 2014;
  static const int mf1CheckKeysOnBlock = 2015;
  static const int hf14aScanKeep = 2016;
  static const int hf14aAuthTrace = 2017;
  static const int mf0UlcAuth = 2018;
  static const int mf0UlcRead = 2019;
  static const int hf14aSniff = 2020;
  static const int mf0UlcWrite = 2021;
  static const int mf0UlcSetKey = 2022;
  static const int hf14aGetConfig = 2200;
  static const int hf14aSetConfig = 2201;

  static const int em410xScan = 3000;
  static const int em410xWriteToT55xx = 3001;
  static const int hidproxScan = 3002;
  static const int hidproxWriteToT55xx = 3003;
  static const int vikingScan = 3004;
  static const int vikingWriteToT55xx = 3005;
  static const int em410xElectraWriteToT55xx = 3006;
  static const int adcGenericRead = 3009;
  static const int ioproxScan = 3010;
  static const int ioproxWriteToT55xx = 3011;
  static const int ioproxDecodeRaw = 3012;
  static const int ioproxComposeId = 3013;
  static const int pacScan = 3014;
  static const int pacWriteToT55xx = 3015;
  static const int lfT55xxWrite = 3016;
  static const int idteckWriteToT55xx = 3018;
  static const int jablotronScan = 3019;
  static const int jablotronWriteToT55xx = 3020;
  static const int pyramidScan = 3021;
  static const int em4x05Scan = 3030;
  static const int lfSniff = 3031;
  static const int em4x05ReadSniff = 3032;

  static const int mf1WriteEmuBlockData = 4000;
  static const int hf14aSetAntiCollData = 4001;
  static const int mf1SetDetectionEnable = 4004;
  static const int mf1GetDetectionCount = 4005;
  static const int mf1GetDetectionLog = 4006;
  static const int mf1GetDetectionEnable = 4007;
  static const int mf1ReadEmuBlockData = 4008;
  static const int mf1GetEmulatorConfig = 4009;
  static const int mf1GetGen1aMode = 4010;
  static const int mf1SetGen1aMode = 4011;
  static const int mf1GetGen2Mode = 4012;
  static const int mf1SetGen2Mode = 4013;
  static const int mf1GetBlockAntiCollMode = 4014;
  static const int mf1SetBlockAntiCollMode = 4015;
  static const int mf1GetWriteMode = 4016;
  static const int mf1SetWriteMode = 4017;
  static const int hf14aGetAntiCollData = 4018;
  static const int mf0NtagGetUidMagicMode = 4019;
  static const int mf0NtagSetUidMagicMode = 4020;
  static const int mf0NtagReadEmuPageData = 4021;
  static const int mf0NtagWriteEmuPageData = 4022;
  static const int mf0NtagGetVersionData = 4023;
  static const int mf0NtagSetVersionData = 4024;
  static const int mf0NtagGetSignatureData = 4025;
  static const int mf0NtagSetSignatureData = 4026;
  static const int mf0NtagGetCounterData = 4027;
  static const int mf0NtagSetCounterData = 4028;
  static const int mf0NtagResetAuthCnt = 4029;
  static const int mf0NtagGetPageCount = 4030;
  static const int mf0NtagGetWriteMode = 4031;
  static const int mf0NtagSetWriteMode = 4032;
  static const int mf0NtagSetDetectionEnable = 4033;
  static const int mf0NtagGetDetectionCount = 4034;
  static const int mf0NtagGetDetectionLog = 4035;
  static const int mf0NtagGetDetectionEnable = 4036;
  static const int mf0NtagGetEmulatorConfig = 4037;
  static const int mf1SetFieldOffDoReset = 4038;
  static const int mf1GetFieldOffDoReset = 4039;
  static const int mf1GetPrngType = 4040;
  static const int mf1SetPrngType = 4041;

  static const int em410xSetEmuId = 5000;
  static const int em410xGetEmuId = 5001;
  static const int hidproxSetEmuId = 5002;
  static const int hidproxGetEmuId = 5003;
  static const int vikingSetEmuId = 5004;
  static const int vikingGetEmuId = 5005;
  static const int pacSetEmuId = 5006;
  static const int pacGetEmuId = 5007;
  static const int ioproxSetEmuId = 5008;
  static const int ioproxGetEmuId = 5009;
  static const int jablotronSetEmuId = 5010;
  static const int jablotronGetEmuId = 5011;
  static const int idteckSetEmuId = 5012;
  static const int idteckGetEmuId = 5013;

  // ISO14443-4 / APDU
  static const int hf14a4ApduRecv = 6000;
  static const int hf14a4ApduSend = 6001;
  static const int hf14a4SetAntiColl = 6002;
  static const int hf14a4StaticResponse = 6003;
  static const int hf14a4ReaderApdu = 6004;
  static const int hf14a4EmvScan = 6005;
}

/// Firmware status codes.
class Status {
  static const int hfTagOk = 0x00;
  static const int hfTagNo = 0x01;
  static const int hfErrStat = 0x02;
  static const int hfErrCrc = 0x03;
  static const int hfCollision = 0x04;
  static const int hfErrBcc = 0x05;
  static const int mfErrAuth = 0x06;
  static const int hfErrParity = 0x07;
  static const int hfErrAts = 0x08;

  static const int lfTagOk = 0x40;
  static const int lfTagNoFound = 0x41;

  static const int parErr = 0x60;
  static const int deviceModeError = 0x66;
  static const int invalidCmd = 0x67;
  static const int success = 0x68;
  static const int notImplemented = 0x69;
  static const int flashWriteFail = 0x70;
  static const int flashReadFail = 0x71;
  static const int invalidSlotType = 0x72;

  static const Set<int> successStatuses = {
    success,
    hfTagOk,
    lfTagOk,
  };

  static String describe(int status) {
    switch (status) {
      case hfTagOk:
        return 'HF tag operation succeeded';
      case hfTagNo:
        return 'No HF tag in field';
      case hfErrStat:
        return 'HF tag status error';
      case hfErrCrc:
        return 'HF tag CRC error';
      case hfCollision:
        return 'HF tag collision';
      case hfErrBcc:
        return 'HF tag BCC error';
      case mfErrAuth:
        return 'MIFARE authentication failed';
      case hfErrParity:
        return 'HF tag parity error';
      case hfErrAts:
        return 'HF tag ATS error';
      case lfTagOk:
        return 'LF tag operation succeeded';
      case lfTagNoFound:
        return 'No LF tag found';
      case parErr:
        return 'Invalid parameters';
      case deviceModeError:
        return 'Wrong device mode (reader/emulator)';
      case invalidCmd:
        return 'Command not supported by firmware';
      case success:
        return 'Success';
      case notImplemented:
        return 'Not implemented by firmware';
      case flashWriteFail:
        return 'Flash write failed';
      case flashReadFail:
        return 'Flash read failed';
      case invalidSlotType:
        return 'Invalid tag type in slot';
      default:
        return 'Unknown status 0x${status.toRadixString(16)}';
    }
  }
}

class ChameleonException implements Exception {
  final String message;
  final int? status;

  ChameleonException(this.message, {this.status});

  @override
  String toString() => message;
}
