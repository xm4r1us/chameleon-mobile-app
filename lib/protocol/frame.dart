import 'dart:typed_data';

/// Chameleon Ultra serial/BLE frame.
///
/// SOF | LRC1 | CMD(2) | STATUS(2) | LEN(2) | LRC2 | DATA(LEN) | LRC3
///
/// All multi-byte values are big endian. LRC is the two's complement of the
/// 8-bit sum of the covered bytes.
class ChameleonFrame {
  static const int sof = 0x11;
  static const int maxDataLength = 512;

  final int command;
  final int status;
  final Uint8List data;

  const ChameleonFrame(this.command, this.status, this.data);

  Uint8List encode() {
    if (data.length > maxDataLength) {
      throw ArgumentError.value(data.length, 'data.length', 'Frame payload too large');
    }
    final out = Uint8List(10 + data.length);
    out[0] = sof;
    out[1] = lrc([sof]);
    out[2] = (command >> 8) & 0xff;
    out[3] = command & 0xff;
    out[4] = (status >> 8) & 0xff;
    out[5] = status & 0xff;
    out[6] = (data.length >> 8) & 0xff;
    out[7] = data.length & 0xff;
    out[8] = lrc(out.sublist(2, 8));
    out.setRange(9, 9 + data.length, data);
    out[9 + data.length] = lrc(out.sublist(0, 9 + data.length));
    return out;
  }

  static int lrc(Iterable<int> bytes) {
    var sum = 0;
    for (final b in bytes) {
      sum = (sum + (b & 0xff)) & 0xff;
    }
    return (0x100 - sum) & 0xff;
  }

  @override
  String toString() =>
      'Frame(cmd=$command, status=0x${status.toRadixString(16).padLeft(2, '0')}, '
      'len=${data.length}, data=${hex(data)})';

  static String hex(Iterable<int> bytes, {String separator = ''}) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(separator);
}

/// Incremental frame decoder. Accepts arbitrary chunks (BLE notifications,
/// serial reads) and returns every complete, checksum-valid frame.
class FrameDecoder {
  final List<int> _buffer = <int>[];

  List<ChameleonFrame> add(List<int> chunk) {
    _buffer.addAll(chunk);
    final frames = <ChameleonFrame>[];

    while (true) {
      // Resynchronise on SOF.
      var start = _buffer.indexOf(ChameleonFrame.sof);
      if (start < 0) {
        _buffer.clear();
        break;
      }
      if (start > 0) {
        _buffer.removeRange(0, start);
      }
      if (_buffer.length < 2) break;
      if (_buffer[1] != ChameleonFrame.lrc([ChameleonFrame.sof])) {
        _buffer.removeAt(0);
        continue;
      }
      if (_buffer.length < 9) break;
      if (_buffer[8] != ChameleonFrame.lrc(_buffer.sublist(2, 8))) {
        _buffer.removeAt(0);
        continue;
      }

      final command = (_buffer[2] << 8) | _buffer[3];
      final status = (_buffer[4] << 8) | _buffer[5];
      final length = (_buffer[6] << 8) | _buffer[7];
      if (length > ChameleonFrame.maxDataLength) {
        _buffer.removeAt(0);
        continue;
      }

      final total = 10 + length;
      if (_buffer.length < total) break;

      final body = Uint8List.fromList(_buffer.sublist(0, total - 1));
      if (_buffer[total - 1] != ChameleonFrame.lrc(body)) {
        _buffer.removeAt(0);
        continue;
      }

      frames.add(ChameleonFrame(
        command,
        status,
        Uint8List.fromList(_buffer.sublist(9, 9 + length)),
      ));
      _buffer.removeRange(0, total);
    }

    return frames;
  }

  void reset() => _buffer.clear();
}
