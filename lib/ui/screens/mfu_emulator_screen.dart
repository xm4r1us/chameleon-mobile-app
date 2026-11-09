import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/strings.dart';
import '../../models/dump.dart';
import '../../protocol/byte_utils.dart';
import '../../services/device_session.dart';
import '../../services/dump_store.dart';
import '../../theme.dart';
import '../widgets.dart';

class MfuEmulatorScreen extends StatefulWidget {
  const MfuEmulatorScreen({super.key});

  @override
  State<MfuEmulatorScreen> createState() => _MfuEmulatorScreenState();
}

class _MfuEmulatorScreenState extends State<MfuEmulatorScreen> {
  int _pageCount = 0;
  Uint8List? _pages;
  bool _uidMagic = false;
  int _writeMode = 0;
  Uint8List _version = Uint8List(0);
  Uint8List _signature = Uint8List(0);
  final List<int> _counters = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final session = context.read<DeviceSession>();
    final slot = session.activeSlot;
    if (slot == null || !slot.hfType.isUltralight) return;
    setState(() => _busy = true);
    final result = await session.guard(
      context.tr('mfuEmulator'),
      () async {
        final client = session.client!;
        final pages = await client.mfuEmuPageCount();
        final magic = await client.mfuGetUidMagic();
        final mode = await client.mfuGetWriteMode();
        Uint8List version = Uint8List(0);
        Uint8List signature = Uint8List(0);
        try {
          version = await client.mfuGetVersion();
        } catch (_) {}
        try {
          signature = await client.mfuGetSignature();
        } catch (_) {}
        final counters = <int>[];
        for (var i = 0; i < 3; i++) {
          try {
            final value = await client.mfuGetCounter(i);
            counters.add(value.$1);
          } catch (_) {
            break;
          }
        }
        return (pages, magic, mode, version, signature, counters);
      },
    );
    if (!mounted) return;
    if (result != null) {
      setState(() {
        _pageCount = result.$1;
        _uidMagic = result.$2;
        _writeMode = result.$3;
        _version = result.$4;
        _signature = result.$5;
        _counters
          ..clear()
          ..addAll(result.$6);
      });
    }
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<DeviceSession>();
    final slot = session.activeSlot;
    if (slot == null || !slot.hfType.isUltralight) {
      return Scaffold(
        appBar: AppBar(title: Text(context.tr('mfuEmulator'))),
        body: EmptyState(
          icon: Icons.style_outlined,
          title: context.tr('slotTypeMismatch'),
          subtitle: context.tr('initSlotFirst'),
          action: FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('slots')),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('mfuEmulator')),
        actions: [
          IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh)),
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
                  const SizedBox(height: 4),
                  Text(
                    '$_pageCount ${context.tr('page')} · ${slot.hfEnabled ? context.tr('enabled') : context.tr('disabled')}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SectionHeader(context.tr('emuConfig')),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: _uidMagic,
                  onChanged: _busy
                      ? null
                      : (value) async {
                          final ok = await session.guard<bool>(
                            context.tr('uidMagic'),
                            () async {
                              await session.client!.mfuSetUidMagic(value);
                              await session.client!.saveSlot();
                              return true;
                            },
                          );
                          if (ok == true) setState(() => _uidMagic = value);
                        },
                  title: Text(context.tr('uidMagic')),
                  secondary: const Icon(Icons.tag),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: DropdownButtonFormField<int>(
                    initialValue: _writeMode,
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
                    onChanged: _busy
                        ? null
                        : (value) async {
                            if (value == null) return;
                            final ok = await session.guard<bool>(
                              context.tr('writeMode'),
                              () async {
                                await session.client!.mfuSetWriteMode(value);
                                await session.client!.saveSlot();
                                return true;
                              },
                            );
                            if (ok == true) setState(() => _writeMode = value);
                          },
                  ),
                ),
              ],
            ),
          ),
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
                  if (_pages != null) ...[
                    const SizedBox(height: 12),
                    ..._pagePreview(context),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => _saveMemory(session),
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
          SectionHeader(context.tr('version')),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InfoRow(
                    label: context.tr('version'),
                    value: _version.isEmpty ? '-' : bytesToHexUpper(_version),
                    mono: true,
                  ),
                  InfoRow(
                    label: context.tr('signature'),
                    value: _signature.isEmpty ? '-' : bytesToHexUpper(_signature).substring(0, 32),
                    mono: true,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () async {
                                  final count = await session.guard<int>(
                                    context.tr('authCounter'),
                                    () => session.client!.mfuResetAuthCounter(),
                                  );
                                  if (count != null && context.mounted) {
                                    showSnack(context, 'Auth counter reset (old: $count)');
                                  }
                                },
                          icon: const Icon(Icons.restart_alt),
                          label: Text(context.tr('authCounter')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_counters.isNotEmpty) ...[
            const SizedBox(height: 18),
            SectionHeader(context.tr('counter')),
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < _counters.length; i++)
                    ListTile(
                      dense: true,
                      title: Text('${context.tr('counter')} $i'),
                      trailing: Text('${_counters[i]}', style: AppTheme.mono),
                      onTap: _busy ? null : () => _editCounter(session, i),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _pagePreview(BuildContext context) {
    final pages = _pages!;
    final count = pages.length ~/ 4;
    final preview = count > 64 ? 64 : count;
    return [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var page = 0; page < preview; page++)
              Text(
                '#${page.toRadixString(16).padLeft(2, '0')}: '
                '${bytesToHexUpper(pages.sublist(page * 4, page * 4 + 4))}',
                style: AppTheme.mono.copyWith(fontSize: 11.5),
              ),
            if (count > preview)
              Text('… ${count - preview} more', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ];
  }

  Future<void> _editCounter(DeviceSession session, int index) async {
    final value = await promptText(
      context,
      title: '${context.tr('counter')} $index',
      initial: '${_counters[index]}',
      keyboardType: TextInputType.number,
      maxLength: 8,
      validator: (text) {
        final parsed = int.tryParse(text);
        if (parsed == null || parsed < 0 || parsed > 0xffffff) {
          return '0..16777215';
        }
        return null;
      },
    );
    if (value == null) return;
    final parsed = int.tryParse(value);
    if (parsed == null) return;
    final ok = await session.guard<bool>(
      context.tr('counter'),
      () async {
        await session.client!.mfuSetCounter(index, parsed, resetTearing: true);
        return true;
      },
    );
    if (ok == true) await _load();
  }

  Future<void> _readMemory(DeviceSession session) async {
    final dump = await session.guard(
      context.tr('readingEmulator'),
      () => session.readMfuEmulatorDump(
        name: 'MFU emulator ${DateTime.now().toIso8601String().substring(0, 10)}',
      ),
    );
    if (dump != null && mounted) {
      setState(() => _pages = dump.data);
    }
  }

  Future<void> _saveMemory(DeviceSession session) async {
    final dump = await session.guard(
      context.tr('readingEmulator'),
      () => session.readMfuEmulatorDump(
        name: 'MFU emulator ${DateTime.now().toIso8601String().substring(0, 10)}',
      ),
    );
    if (dump == null) return;
    await context.read<DumpStore>().add(dump);
    if (mounted) showSnack(context, context.tr('emulatorDumpSaved'));
  }

  Future<void> _loadDump(DeviceSession session) async {
    final store = context.read<DumpStore>();
    final dumps = store.dumps.where((d) => d.isMfu).toList();
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
      () => session.writeMfuDumpToSlot(dump, firmwareSlot: slot.index),
    );
    if (count != null && mounted) {
      await _readMemory(session);
      showSnack(context, context.tr('loadedToSlot', {'slot': slot.number}));
    }
  }
}
