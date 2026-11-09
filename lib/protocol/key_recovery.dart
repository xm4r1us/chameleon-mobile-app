import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'byte_utils.dart';

/// FFI bridge to the native MIFARE Classic recovery routines.
///
/// The solvers are compiled from the Chameleon Ultra / Proxmark crapto1
/// sources into `librecovery.so` by the Android CMake build.
class KeyRecovery {
  static DynamicLibrary? _lib;
  static bool _tried = false;

  static bool get available => _lib != null;

  static bool init() {
    if (_tried) return _lib != null;
    _tried = true;
    try {
      _lib = DynamicLibrary.open('librecovery.so');
    } catch (_) {
      _lib = null;
    }
    return _lib != null;
  }

  /// Used by host tests to load a locally compiled dylib.
  static void loadForTest(String path) {
    _lib = DynamicLibrary.open(path);
    _tried = true;
  }

  static DynamicLibrary get _library {
    if (_lib == null && !init()) {
      throw UnsupportedError('Native recovery library is not available');
    }
    return _lib!;
  }

  static int? mfkey32v2({
    required int uid,
    required int nt0,
    required int nr0Enc,
    required int ar0Enc,
    required int nt1,
    required int nr1Enc,
    required int ar1Enc,
  }) {
    final fn = _library.lookupFunction<
        Int32 Function(Uint32, Uint32, Uint32, Uint32, Uint32, Uint32, Uint32, Pointer<Uint64>),
        int Function(int, int, int, int, int, int, int, Pointer<Uint64>)>('cli_mfkey32v2');
    final out = malloc<Uint64>();
    try {
      final ok = fn(uid, nt0, nr0Enc, ar0Enc, nt1, nr1Enc, ar1Enc, out);
      return ok == 1 ? out.value : null;
    } finally {
      malloc.free(out);
    }
  }

  static int? mfkey64({
    required int uid,
    required int nt,
    required int nrEnc,
    required int arEnc,
    required int atEnc,
  }) {
    final fn = _library.lookupFunction<
        Int32 Function(Uint32, Uint32, Uint32, Uint32, Uint32, Pointer<Uint64>),
        int Function(int, int, int, int, int, Pointer<Uint64>)>('cli_mfkey64');
    final out = malloc<Uint64>();
    try {
      final ok = fn(uid, nt, nrEnc, arEnc, atEnc, out);
      return ok == 1 ? out.value : null;
    } finally {
      malloc.free(out);
    }
  }

  static List<int> nested({
    required int uid,
    required int distance,
    required List<int> nt,
    required List<int> ntEnc,
    required List<int> parity,
    int maxKeys = 64,
  }) {
    if (nt.isEmpty) return const [];
    final fn = _library.lookupFunction<
        Int32 Function(Uint32, Uint32, Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint32>, Int32,
            Pointer<Uint64>, Int32),
        int Function(int, int, Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint32>, int,
            Pointer<Uint64>, int)>('cli_nested');
    final nts = malloc<Uint32>(nt.length);
    final encs = malloc<Uint32>(ntEnc.length);
    final pars = malloc<Uint32>(parity.length);
    final out = malloc<Uint64>(maxKeys);
    try {
      for (var i = 0; i < nt.length; i++) {
        nts[i] = nt[i] & 0xffffffff;
        encs[i] = ntEnc[i] & 0xffffffff;
        pars[i] = parity[i] & 0xffffffff;
      }
      final count = fn(uid, distance, nts, encs, pars, nt.length, out, maxKeys);
      return [for (var i = 0; i < count; i++) out[i]];
    } finally {
      malloc.free(nts);
      malloc.free(encs);
      malloc.free(pars);
      malloc.free(out);
    }
  }

  static List<int> staticNested({
    required int uid,
    required int targetKeyType,
    required List<int> nt,
    required List<int> ntEnc,
    int maxKeys = 64,
  }) {
    if (nt.isEmpty) return const [];
    final fn = _library.lookupFunction<
        Int32 Function(Uint32, Uint32, Pointer<Uint32>, Pointer<Uint32>, Int32, Pointer<Uint64>, Int32),
        int Function(int, int, Pointer<Uint32>, Pointer<Uint32>, int, Pointer<Uint64>, int)>(
      'cli_static_nested',
    );
    final nts = malloc<Uint32>(nt.length);
    final encs = malloc<Uint32>(ntEnc.length);
    final out = malloc<Uint64>(maxKeys);
    try {
      for (var i = 0; i < nt.length; i++) {
        nts[i] = nt[i] & 0xffffffff;
        encs[i] = ntEnc[i] & 0xffffffff;
      }
      final count = fn(uid, targetKeyType, nts, encs, nt.length, out, maxKeys);
      return [for (var i = 0; i < count; i++) out[i]];
    } finally {
      malloc.free(nts);
      malloc.free(encs);
      malloc.free(out);
    }
  }

  static List<int> darkside({
    required int uid,
    required List<int> nt1,
    required List<int> ks1,
    required List<int> par,
    required List<int> nr,
    required List<int> ar,
    int maxKeys = 64,
  }) {
    if (nt1.isEmpty) return const [];
    final fn = _library.lookupFunction<
        Int32 Function(Uint32, Pointer<Uint32>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint32>,
            Pointer<Uint32>, Int32, Pointer<Uint64>, Int32),
        int Function(int, Pointer<Uint32>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint32>,
            Pointer<Uint32>, int, Pointer<Uint64>, int)>('cli_darkside');
    final nts = malloc<Uint32>(nt1.length);
    final kss = malloc<Uint64>(ks1.length);
    final pars = malloc<Uint64>(par.length);
    final nrs = malloc<Uint32>(nr.length);
    final ars = malloc<Uint32>(ar.length);
    final out = malloc<Uint64>(maxKeys);
    try {
      for (var i = 0; i < nt1.length; i++) {
        nts[i] = nt1[i] & 0xffffffff;
        kss[i] = ks1[i] & 0xffffffffffffffff;
        pars[i] = par[i] & 0xffffffffffffffff;
        nrs[i] = nr[i] & 0xffffffff;
        ars[i] = ar[i] & 0xffffffff;
      }
      final count = fn(uid, nts, kss, pars, nrs, ars, nt1.length, out, maxKeys);
      return [for (var i = 0; i < count; i++) out[i]];
    } finally {
      malloc.free(nts);
      malloc.free(kss);
      malloc.free(pars);
      malloc.free(nrs);
      malloc.free(ars);
      malloc.free(out);
    }
  }

  /// 48-bit key integer (as printed by crapto1) to the 6 bytes used on air.
  static Uint8List keyFromInt(int value) => Uint8List.fromList([
        (value >> 40) & 0xff,
        (value >> 32) & 0xff,
        (value >> 24) & 0xff,
        (value >> 16) & 0xff,
        (value >> 8) & 0xff,
        value & 0xff,
      ]);

  static String keyHex(int value) => bytesToHexUpper(keyFromInt(value));
}
