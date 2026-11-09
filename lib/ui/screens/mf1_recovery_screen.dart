import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/strings.dart';
import '../../models/device_models.dart';
import '../../protocol/byte_utils.dart';
import '../../protocol/key_recovery.dart';
import '../../protocol/tag_types.dart';
import '../../services/device_session.dart';
import '../../services/dump_store.dart';
import '../../services/key_store.dart';
import '../../theme.dart';
import '../widgets.dart';
import 'dump_detail_screen.dart';

class Mf1RecoveryScreen extends StatefulWidget {
  const Mf1RecoveryScreen({super.key});

  @override
  State<Mf1RecoveryScreen> createState() => _Mf1RecoveryScreenState();
}

class _Mf1RecoveryScreenState extends State<Mf1RecoveryScreen> {
  TagType _type = TagTypes.mifare1024;
  HfScanResult? _tag;
  Map<int, Uint8List> _found = {};
  bool _busy = false;

  int get _sectors => MifareClassic.sectorCountForType(_type);

  @override
  Widget build(BuildContext context) {
    final keyStore = context.watch<KeyStore>();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('keyRecovery'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('recoveryHint'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        KeyRecovery.available ? Icons.verified : Icons.error_outline,
                        size: 16,
                        color: KeyRecovery.available ? scheme.primary : scheme.error,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          context.tr(KeyRecovery.available ? 'nativeReady' : 'nativeUnavailable'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      TextButton(
                        onPressed: _selfTest,
                        child: Text(context.tr('selfTest')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _scan,
                          icon: const Icon(Icons.nfc),
                          label: Text(context.tr('scanHfShort')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _busy ? null : () => _dictionaryCheck(keyStore),
                          icon: const Icon(Icons.key),
                          label: Text(context.tr('checkKeys')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_tag != null) ...[
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    InfoRow(label: context.tr('uid'), value: _tag!.coll.uidHex, mono: true),
                    InfoRow(label: context.tr('sak'), value: _tag!.coll.sakHex, mono: true),
                    InfoRow(label: context.tr('prngLevel'), value: _tag!.prngName),
                    DropdownButtonFormField<TagType>(
                      initialValue: _type,
                      decoration: InputDecoration(labelText: context.tr('dumpType')),
                      items: TagTypes.mifareClassic
                          .map((t) => DropdownMenuItem(value: t, child: Text(t.name)))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _type = value;
                            _found = {};
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SectionHeader(
            context.tr('keysSection'),
            trailing: Text('${_found.length}/${_sectors * 2}'),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _darkside,
                          icon: const Icon(Icons.flash_on),
                          label: Text(context.tr('attackDarkside')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _found.isEmpty || _busy ? null : _nested,
                          icon: const Icon(Icons.account_tree_outlined),
                          label: Text(context.tr('attackNested')),
                        ),
                      ),
                    ],
                  ),
                  if (_found.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        context.tr('noKnownKey'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (_found.isEmpty)
            Card(
              child: EmptyState(
                icon: Icons.key_off,
                title: context.tr('noKeysRecovered'),
                compact: true,
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (var sector = 0; sector < _sectors; sector++)
                    ListTile(
                      dense: true,
                      title: Text('${context.tr('sector')} $sector'),
                      subtitle: Text(
                        'A: ${_fmt(_found[sector * 2])}\nB: ${_fmt(_found[sector * 2 + 1])}',
                        style: AppTheme.mono.copyWith(fontSize: 11.5),
                      ),
                    ),
                ],
              ),
            ),
          if (_found.isNotEmpty) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : () => _readDump(keyStore),
                icon: const Icon(Icons.download),
                label: Text(context.tr('readDump')),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        await keyStore.addKeys(_found.values);
                        if (mounted) {
                          showSnack(context, context.tr('keyCount', {'count': _found.length}));
                        }
                      },
                icon: const Icon(Icons.playlist_add),
                label: Text(context.tr('addKey')),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _fmt(Uint8List? key) => key == null ? '—' : bytesToHexUpper(key);

  void _selfTest() {
    final key = KeyRecovery.available
        ? KeyRecovery.mfkey32v2(
            uid: 0xdeadbeef,
            nt0: 0x11223344,
            nr0Enc: 0x55667788,
            ar0Enc: 0x972738f9,
            nt1: 0x99aabbcc,
            nr1Enc: 0xddeeff00,
            ar1Enc: 0xb87327a9,
          )
        : null;
    final ok = key != null && KeyRecovery.keyHex(key) == 'A0A1A2A3A4A5';
    showSnack(
      context,
      context.tr(ok ? 'selfTestOk' : 'selfTestFail'),
      error: !ok,
    );
  }

  Future<void> _scan() async {
    final session = context.read<DeviceSession>();
    setState(() => _busy = true);
    final tag = await session.guard(context.tr('scanHf'), session.scanHf);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _tag = tag;
      if (tag?.guessedType?.isMifareClassic == true) _type = tag!.guessedType!;
    });
    if (tag != null && !tag.isClassic) {
      showSnack(context, context.tr('notClassicTag'), error: true);
    }
  }

  Future<void> _dictionaryCheck(KeyStore keyStore) async {
    final session = context.read<DeviceSession>();
    setState(() => _busy = true);
    final found = await session.guard(
      context.tr('checkingKeys'),
      () => session.findMf1Keys(
        type: _type,
        keys: keyStore.effectiveKeys,
        onProgress: (attempted, count) => session.reportProgress(
          '${context.tr('checkingKeys')} $count/${_sectors * 2}',
          attempted == 0 ? null : count / (_sectors * 2),
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _found = found ?? {};
    });
  }

  Future<void> _darkside() async {
    final session = context.read<DeviceSession>();
    setState(() => _busy = true);
    final key = await session.guard(
      context.tr('attackDarkside'),
      () => session.recoverMf1Darkside(
        block: MifareClassic.trailerBlockOfSector(0),
        keyType: MifareClassic.keyA,
        maxAttempts: 8,
        onProgress: session.reportProgress,
      ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (key == null) {
      showSnack(context, context.tr('recoveryFailed'), error: true);
      return;
    }
    setState(() => _found[0] = key);
    showSnack(context, context.tr('recoveredKeyFor', {
      'key': bytesToHexUpper(key),
      'sector': 0,
    }));
  }

  Future<void> _nested() async {
    final session = context.read<DeviceSession>();
    final positions = _found.keys.toList()..sort();
    var source = positions.first;
    var targetSector = 1;
    var targetKeyType = MifareClassic.keyA;

    final result = await showDialog<(int, int, int)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.tr('attackNested')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: source,
                decoration: const InputDecoration(labelText: 'Known key'),
                items: positions
                    .map((position) => DropdownMenuItem(
                          value: position,
                          child: Text(
                            'S${position ~/ 2} ${position.isEven ? 'A' : 'B'} · '
                            '${bytesToHexUpper(_found[position]!)}',
                          ),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setDialogState(() => source = value);
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                initialValue: targetSector,
                decoration: const InputDecoration(labelText: 'Target sector'),
                items: [
                  for (var i = 0; i < _sectors; i++)
                    DropdownMenuItem(value: i, child: Text('${context.tr('sector')} $i')),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => targetSector = value);
                },
              ),
              const SizedBox(height: 10),
              SegmentedButton<int>(
                segments: [
                  ButtonSegment(value: MifareClassic.keyA, label: Text(context.tr('keyA'))),
                  ButtonSegment(value: MifareClassic.keyB, label: Text(context.tr('keyB'))),
                ],
                selected: {targetKeyType},
                onSelectionChanged: (value) => setDialogState(() => targetKeyType = value.first),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.tr('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, (source, targetSector, targetKeyType)),
              child: Text(context.tr('attackNested')),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    final knownPosition = result.$1;
    final knownKey = _found[knownPosition];
    if (knownKey == null) return;
    final knownSector = knownPosition ~/ 2;
    final knownType = knownPosition.isEven ? MifareClassic.keyA : MifareClassic.keyB;

    setState(() => _busy = true);
    final key = await session.guard(
      context.tr('attackNested'),
      () => session.recoverMf1Nested(
        knownBlock: MifareClassic.trailerBlockOfSector(knownSector),
        knownKeyType: knownType,
        knownKey: knownKey,
        targetBlock: MifareClassic.trailerBlockOfSector(result.$2),
        targetKeyType: result.$3,
        onProgress: session.reportProgress,
      ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (key == null) {
      showSnack(context, context.tr('recoveryFailed'), error: true);
      return;
    }
    final position = result.$2 * 2 + (result.$3 == MifareClassic.keyB ? 1 : 0);
    setState(() => _found[position] = key);
    showSnack(context, context.tr('recoveredKeyFor', {
      'key': bytesToHexUpper(key),
      'sector': result.$2,
    }));
  }

  Future<void> _readDump(KeyStore keyStore) async {
    final session = context.read<DeviceSession>();
    final store = context.read<DumpStore>();
    setState(() => _busy = true);
    final dump = await session.guard(
      context.tr('readInProgress'),
      () => session.readMf1Dump(
        type: _type,
        keys: [..._found.values, ...keyStore.effectiveKeys],
        name: '${_type.name} ${DateTime.now().toIso8601String().substring(0, 10)}',
        onProgress: session.reportProgress,
      ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (dump == null) return;
    await store.add(dump);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DumpDetailScreen(dumpId: dump.id)),
    );
  }
}
