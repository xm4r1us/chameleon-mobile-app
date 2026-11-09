import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/strings.dart';
import '../../models/device_models.dart';
import '../../models/dump.dart';
import '../../protocol/byte_utils.dart';
import '../../protocol/commands.dart';
import '../../services/device_session.dart';
import '../../services/key_store.dart';
import '../../services/dump_store.dart';
import '../../theme.dart';
import '../widgets.dart';

class Mf1EmulatorScreen extends StatefulWidget {
  const Mf1EmulatorScreen({super.key});

  @override
  State<Mf1EmulatorScreen> createState() => _Mf1EmulatorScreenState();
}

class _Mf1EmulatorScreenState extends State<Mf1EmulatorScreen> {
  Mf1EmulatorConfig? _config;
  Uint8List? _memory;
  int _detectionCount = 0;
  List<Mf1DetectionRecord> _log = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadConfig());
  }

  Future<void> _loadConfig() async {
    final session = context.read<DeviceSession>();
    final slot = session.activeSlot;
    if (slot == null || !slot.hfType.isMifareClassic) return;
    setState(() => _busy = true);
    final config = await session.guard(
      context.tr('emuConfig'),
      () => session.client!.mf1GetEmuConfig(),
    );
    final count = await session.guard(
      context.tr('detectionLog'),
      () => session.client!.mf1DetectionCount(),
    );
    if (!mounted) return;
    setState(() {
      _config = config;
      _detectionCount = count ?? 0;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<DeviceSession>();
    final slot = session.activeSlot;
    final scheme = Theme.of(context).colorScheme;
    if (slot == null || !slot.hfType.isMifareClassic) {
      return Scaffold(
        appBar: AppBar(title: Text(context.tr('mf1Emulator'))),
        body: EmptyState(
          icon: Icons.credit_card_off,
          title: context.tr('slotTypeMismatch'),
          subtitle: context.tr('initSlotFirst'),
          action: FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('slots')),
          ),
        ),
      );
    }

    final config = _config;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('mf1Emulator')),
        actions: [
          IconButton(
            onPressed: _busy ? null : _loadConfig,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${context.tr('slot')} ${slot.number} · ${slot.hfType.name}',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    '${slot.hfType.mf1Blocks} ${context.tr('blocks')} · ${slot.hfEnabled ? context.tr('enabled') : context.tr('disabled')}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SectionHeader(context.tr('emuConfig')),
          if (config == null)
            const Card(child: Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())))
          else ...[
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    value: config.detection,
                    onChanged: (value) => _toggle(
                      value ? context.tr('loggingEnabled') : context.tr('loggingDisabled'),
                      () async {
                        await session.client!.mf1SetDetection(value);
                        await session.client!.saveSlot();
                      },
                      () => _config = Mf1EmulatorConfig(
                        detection: value,
                        gen1a: config.gen1a,
                        gen2: config.gen2,
                        blockAntiColl: config.blockAntiColl,
                        writeMode: config.writeMode,
                        fieldOffReset: config.fieldOffReset,
                        prngType: config.prngType,
                      ),
                    ),
                    title: Text(context.tr('detection')),
                    subtitle: Text(context.tr('detectionLog')),
                    secondary: const Icon(Icons.analytics_outlined),
                  ),
                  SwitchListTile(
                    value: config.gen1a,
                    onChanged: (value) => _setOption(
                      Cmd.mf1SetGen1aMode,
                      value,
                      () => _config = Mf1EmulatorConfig(
                        detection: config.detection,
                        gen1a: value,
                        gen2: config.gen2,
                        blockAntiColl: config.blockAntiColl,
                        writeMode: config.writeMode,
                        fieldOffReset: config.fieldOffReset,
                        prngType: config.prngType,
                      ),
                    ),
                    title: Text(context.tr('gen1a')),
                    secondary: const Icon(Icons.lock_open),
                  ),
                  SwitchListTile(
                    value: config.gen2,
                    onChanged: (value) => _setOption(
                      Cmd.mf1SetGen2Mode,
                      value,
                      () => _config = Mf1EmulatorConfig(
                        detection: config.detection,
                        gen1a: config.gen1a,
                        gen2: value,
                        blockAntiColl: config.blockAntiColl,
                        writeMode: config.writeMode,
                        fieldOffReset: config.fieldOffReset,
                        prngType: config.prngType,
                      ),
                    ),
                    title: Text(context.tr('gen2')),
                    secondary: const Icon(Icons.lock_person_outlined),
                  ),
                  SwitchListTile(
                    value: config.blockAntiColl,
                    onChanged: (value) => _setOption(
                      Cmd.mf1SetBlockAntiCollMode,
                      value,
                      () => _config = Mf1EmulatorConfig(
                        detection: config.detection,
                        gen1a: config.gen1a,
                        gen2: config.gen2,
                        blockAntiColl: value,
                        writeMode: config.writeMode,
                        fieldOffReset: config.fieldOffReset,
                        prngType: config.prngType,
                      ),
                    ),
                    title: Text(context.tr('blockAntiColl')),
                    subtitle: const Text('UID / ATQA / SAK from block 0'),
                    secondary: const Icon(Icons.tag),
                  ),
                  SwitchListTile(
                    value: config.fieldOffReset,
                    onChanged: (value) => _toggle(
                      context.tr('emuConfig'),
                      () async {
                        await session.client!.mf1SetFieldOffReset(value);
                        await session.client!.saveSlot();
                      },
                      () => _config = Mf1EmulatorConfig(
                        detection: config.detection,
                        gen1a: config.gen1a,
                        gen2: config.gen2,
                        blockAntiColl: config.blockAntiColl,
                        writeMode: config.writeMode,
                        fieldOffReset: value,
                        prngType: config.prngType,
                      ),
                    ),
                    title: Text(context.tr('fieldOffReset')),
                    secondary: const Icon(Icons.restart_alt),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: config.writeMode,
                            decoration: InputDecoration(labelText: context.tr('writeMode')),
                            items: {
                              0: context.tr('writeModeNormal'),
                              1: context.tr('writeModeDenied'),
                              2: context.tr('writeModeDeceive'),
                              3: context.tr('writeModeShadow'),
                            }
                                .entries
                                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                                .toList(),
                            onChanged: (value) async {
                              if (value == null) return;
                              await _toggle(
                                context.tr('writeMode'),
                                () async {
                                  await session.client!.mf1SetWriteMode(value);
                                  await session.client!.saveSlot();
                                },
                                () => _config = Mf1EmulatorConfig(
                                  detection: config.detection,
                                  gen1a: config.gen1a,
                                  gen2: config.gen2,
                                  blockAntiColl: config.blockAntiColl,
                                  writeMode: value,
                                  fieldOffReset: config.fieldOffReset,
                                  prngType: config.prngType,
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: config.prngType,
                            decoration: InputDecoration(labelText: context.tr('prngType')),
                            items: const [
                              DropdownMenuItem(value: 0, child: Text('Static')),
                              DropdownMenuItem(value: 1, child: Text('Weak')),
                              DropdownMenuItem(value: 2, child: Text('Hard')),
                            ],
                            onChanged: (value) async {
                              if (value == null) return;
                              await _toggle(
                                context.tr('prngType'),
                                () async {
                                  await session.client!.mf1SetPrngType(value);
                                  await session.client!.saveSlot();
                                },
                                () => _config = Mf1EmulatorConfig(
                                  detection: config.detection,
                                  gen1a: config.gen1a,
                                  gen2: config.gen2,
                                  blockAntiColl: config.blockAntiColl,
                                  writeMode: config.writeMode,
                                  fieldOffReset: config.fieldOffReset,
                                  prngType: value,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          SectionHeader(context.tr('emulatorMemory')),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : () => _readMemory(session),
                          icon: const Icon(Icons.download),
                          label: Text(context.tr('dumpFromEmulator')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _busy ? null : () => _loadDump(session),
                          icon: const Icon(Icons.upload),
                          label: Text(context.tr('loadDump')),
                        ),
                      ),
                    ],
                  ),
                  if (_memory != null) ...[
                    const SizedBox(height: 12),
                    HexBlock(
                      bytesToHexUpper(_memory!.sublist(0, _memory!.length.clamp(0, 256)), separator: ' '),
                      label: '${_memory!.length} ${context.tr('bytes')}',
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () async {
                          final record = await _saveMemory(session);
                          if (record != null && context.mounted) {
                            showSnack(context, context.tr('emulatorDumpSaved'));
                          }
                        },
                        icon: const Icon(Icons.save_alt),
                        label: Text(context.tr('saveEmulatorDump')),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          SectionHeader(
            context.tr('detectionLog'),
            trailing: Text('${context.tr('keyCount', {'count': _detectionCount})}'),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : () => _readLog(session),
                          icon: const Icon(Icons.list_alt),
                          label: Text(context.tr('readDetectionLog')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _log.isEmpty
                              ? null
                              : () => _recoverKeys(context, session),
                          icon: const Icon(Icons.key),
                          label: Text(context.tr('decryptLog')),
                        ),
                      ),
                    ],
                  ),
                  if (_log.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        context.tr('noLogs'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    )
                  else
                    ..._log.take(20).map(
                          (record) => Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'B${record.block} · ${record.keyType} · UID ${bytesToHexUpper(record.uid)} '
                              '· NT ${bytesToHexUpper(record.nt)}',
                              style: AppTheme.mono.copyWith(fontSize: 11),
                            ),
                          ),
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggle(String label, Future<void> Function() action, VoidCallback optimistic) async {
    final session = context.read<DeviceSession>();
    setState(optimistic);
    final ok = await session.guard<bool>(label, () async {
      await action();
      return true;
    });
    if (ok != true && mounted) {
      await _loadConfig();
    }
  }

  Future<void> _setOption(int command, bool value, VoidCallback optimistic) async {
    await _toggle(
      context.tr('emuConfig'),
      () async {
        final session = context.read<DeviceSession>();
        await session.client!.mf1SetEmuOption(command, value);
        await session.client!.saveSlot();
      },
      optimistic,
    );
  }

  Future<void> _readMemory(DeviceSession session) async {
    final dump = await session.guard(
      context.tr('readingEmulator'),
      () => session.readMf1EmulatorDump(name: 'MF1 emulator ${DateTime.now().toIso8601String().substring(0, 10)}'),
    );
    if (dump != null && mounted) {
      setState(() => _memory = dump.data);
    }
  }

  Future<DumpRecord?> _saveMemory(DeviceSession session) async {
    final dump = await session.guard(
      context.tr('readingEmulator'),
      () => session.readMf1EmulatorDump(name: 'MF1 emulator ${DateTime.now().toIso8601String().substring(0, 10)}'),
    );
    if (dump == null) return null;
    final store = context.read<DumpStore>();
    await store.add(dump);
    return dump;
  }

  Future<void> _loadDump(DeviceSession session) async {
    final store = context.read<DumpStore>();
    final dumps = store.dumps.where((d) => d.isMf1).toList();
    if (dumps.isEmpty) {
      showSnack(context, context.tr('noDumpsYet'));
      return;
    }
    final dump = await showModalBottomSheet<DumpRecord>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(context.tr('chooseDump'), style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final dump in dumps)
              ListTile(
                title: Text(dump.displayName),
                subtitle: Text('${dump.tagType.name} · ${dump.sizeLabel}'),
                onTap: () => Navigator.pop(context, dump),
              ),
          ],
        ),
      ),
    );
    if (dump == null) return;
    final slot = session.activeSlot;
    if (slot == null) return;
    final ok = await confirm(
      context,
      title: context.tr('loadDump'),
      message: context.tr('initConfirm'),
    );
    if (!ok) return;
    final count = await session.guard(
      context.tr('writingEmulator'),
      () => session.writeMf1DumpToSlot(dump, firmwareSlot: slot.index),
    );
    if (count != null && mounted) {
      await _readMemory(session);
      showSnack(context, context.tr('loadedToSlot', {'slot': slot.number}));
    }
  }

  Future<void> _readLog(DeviceSession session) async {
    final log = await session.guard(
      context.tr('readDetectionLog'),
      () async {
        final client = session.client!;
        final count = await client.mf1DetectionCount();
        final records = <Mf1DetectionRecord>[];
        var index = 0;
        while (index < count) {
          final chunk = await client.mf1DetectionLog(index: index);
          if (chunk.isEmpty) break;
          records.addAll(chunk);
          index += chunk.length;
        }
        return (count, records);
      },
    );
    if (log != null && mounted) {
      setState(() {
        _detectionCount = log.$1;
        _log = log.$2;
      });
    }
  }

  Future<void> _recoverKeys(BuildContext context, DeviceSession session) async {
    if (_log.isEmpty) return;
    final keys = await session.guard(
      context.tr('decryptLog'),
      () => session.recoverKeysFromDetectionLog(
        _log,
        onProgress: session.reportProgress,
      ),
    );
    if (!mounted) return;
    if (keys == null || keys.isEmpty) {
      showSnack(context, context.tr('recoveryFailed'), error: true);
      return;
    }
    final keyStore = context.read<KeyStore>();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('recoveredKeys')),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final key in keys)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(bytesToHexUpper(key), style: AppTheme.mono),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('close')),
          ),
          FilledButton(
            onPressed: () async {
              await keyStore.addKeys(keys);
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(context.tr('addKey')),
          ),
        ],
      ),
    );
  }
}
