import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/strings.dart';
import '../../models/device_models.dart';
import '../../models/dump.dart';
import '../../protocol/byte_utils.dart';
import '../../protocol/tag_types.dart';
import '../../services/device_session.dart';
import '../../services/dump_store.dart';
import '../../services/key_store.dart';
import '../widgets.dart';
import 'dump_detail_screen.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  HfScanResult? _hf;
  LfScanResult? _lf;
  TagType _lfProtocol = TagTypes.em410x;
  bool _scanning = false;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<DeviceSession>();
    return Column(
      children: [
        TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: context.tr('hfTab')),
            Tab(text: context.tr('lfTab')),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _buildHf(context, session),
              _buildLf(context, session),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHf(BuildContext context, DeviceSession session) {
    final result = _hf;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
      children: [
        if (!session.readerMode)
          _ModeBanner(
            onSwitch: session.isBusy
                ? null
                : () => session.guard(
                      context.tr('modeReader'),
                      () => session.setReaderMode(true),
                    ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.tr('scanHf'), style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        context.tr('scanHint'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: _scanning
                      ? null
                      : () async {
                          setState(() => _scanning = true);
                          final value = await session.guard(context.tr('scanHf'), session.scanHf);
                          if (mounted) {
                            setState(() {
                              _scanning = false;
                              _hf = value;
                            });
                            if (value == null && session.lastError == null) {
                              showSnack(context, context.tr('noTag'));
                            }
                          }
                        },
                  icon: _scanning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.nfc),
                  label: Text(context.tr('scanHf')),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (result != null) ...[
          _HfResultCard(result: result, session: session, onRead: () => _readHf(context, session, result)),
          const SizedBox(height: 14),
          _HfActions(result: result, session: session, onRead: () => _readHf(context, session, result)),
        ] else
          Card(
            child: EmptyState(
              icon: Icons.wifi_tethering,
              title: context.tr('noTag'),
              subtitle: context.tr('noTagHint'),
              compact: true,
            ),
          ),
      ],
    );
  }

  Future<void> _readHf(BuildContext context, DeviceSession session, HfScanResult result) async {
    final store = context.read<DumpStore>();
    final keys = context.read<KeyStore>();
    if (result.isClassic) {
      final config = await _showMf1ReadDialog(context, result, keys);
      if (config == null) return;
      final record = await session.guard(
        context.tr('readInProgress'),
        () => session.readMf1Dump(
          type: config.type,
          keys: config.keys,
          name: config.name,
          onProgress: session.reportProgress,
        ),
      );
      if (record == null) return;
      await store.add(record);
      if (!context.mounted) return;
      showSnack(context, context.tr('readComplete'));
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DumpDetailScreen(dumpId: record.id)),
      );
      return;
    }

    final config = await _showMf0ReadDialog(context, result);
    if (config == null) return;
    final record = await session.guard(
      context.tr('readInProgress'),
      () => session.readMfuDump(
        type: config.type,
        name: config.name,
        ulcKey: config.ulcKey,
        onProgress: session.reportProgress,
      ),
    );
    if (record == null) return;
    await store.add(record);
    if (!context.mounted) return;
    showSnack(context, context.tr('readComplete'));
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DumpDetailScreen(dumpId: record.id)),
    );
  }

  Widget _buildLf(BuildContext context, DeviceSession session) {
    final result = _lf;
    final store = context.watch<DumpStore>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('selectProtocol'), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                DropdownButtonFormField<TagType>(
                  value: _lfProtocol,
                  decoration: const InputDecoration(),
                  items: TagTypes.lf
                      .map((type) => DropdownMenuItem(value: type, child: Text(type.name)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _lfProtocol = value);
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _scanning
                        ? null
                        : () async {
                            setState(() => _scanning = true);
                            final value = await session.guard(
                              context.tr('scanLf'),
                              () => session.scanLf(_lfProtocol),
                            );
                            if (mounted) {
                              setState(() {
                                _scanning = false;
                                _lf = value;
                              });
                              if (value == null && session.lastError == null) {
                                showSnack(context, context.tr('noTag'));
                              }
                            }
                          },
                    icon: const Icon(Icons.radio),
                    label: Text(context.tr('scanLf')),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (result != null) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(result.summary, style: Theme.of(context).textTheme.titleMedium),
                      ),
                      StatusPill(result.type.name, icon: Icons.check_circle),
                    ],
                  ),
                  const SizedBox(height: 10),
                  for (final entry in result.fields.entries)
                    InfoRow(label: entry.key, value: entry.value, mono: true),
                  const SizedBox(height: 8),
                  HexBlock(result.rawHex, label: context.tr('rawBytes')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () async {
                    final record = _LfDumpFactory.fromScan(result);
                    await store.add(record);
                    if (context.mounted) {
                      showSnack(context, context.tr('lfSaved'));
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => DumpDetailScreen(dumpId: record.id)),
                      );
                    }
                  },
                  icon: const Icon(Icons.save_alt),
                  label: Text(context.tr('saveDump')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () async {
                    final ok = await confirm(
                      context,
                      title: context.tr('writeToT55'),
                      message: context.tr('writeT55Confirm', {'id': result.rawHex}),
                    );
                    if (!ok) return;
                    final done = await session.guard<bool>(
                      context.tr('writeToT55'),
                      () async {
                        await session.writeLfToT55(result.type, result.raw);
                        return true;
                      },
                    );
                    if (done == true && context.mounted) {
                      showSnack(context, context.tr('writtenToTag'));
                    }
                  },
                  icon: const Icon(Icons.memory),
                  label: Text(context.tr('writeToT55')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _emulateLf(context, session, result),
              icon: const Icon(Icons.play_arrow),
              label: Text(context.tr('emulateToSlot')),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _emulateLf(BuildContext context, DeviceSession session, LfScanResult result) async {
    final slot = await pickSlot(
      context,
      slotNumbers: [for (var i = 1; i <= 8; i++) i],
      title: context.tr('selectSlot'),
      subtitle: context.tr('selectSlotHint'),
      selected: session.activeSlot?.number,
    );
    if (slot == null) return;
    final ok = await confirm(
      context,
      title: context.tr('emulate'),
      message: context.tr('initConfirm'),
    );
    if (!ok) return;
    final count = await session.guard(
      context.tr('writingEmulator'),
      () => session.writeLfToSlot(result, firmwareSlot: slot - 1),
    );
    if (count != null && context.mounted) {
      showSnack(context, context.tr('loadedToSlot', {'slot': slot}));
    }
  }

  Future<_Mf1ReadConfig?> _showMf1ReadDialog(
    BuildContext context,
    HfScanResult result,
    KeyStore keyStore,
  ) {
    var type = result.guessedType?.isMifareClassic == true
        ? result.guessedType!
        : TagTypes.mifare1024;
    final nameController = TextEditingController(
      text: '${type.name} ${_stamp()}',
    );
    var useDictionary = true;
    var extraKeys = '';

    return showDialog<_Mf1ReadConfig>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.tr('readDumpTitle')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<TagType>(
                  value: type,
                  decoration: InputDecoration(labelText: context.tr('dumpType')),
                  items: TagTypes.mifareClassic
                      .map((t) => DropdownMenuItem(value: t, child: Text(t.name)))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() {
                      type = value;
                      nameController.text = '${type.name} ${_stamp()}';
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(labelText: context.tr('dumpName')),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: useDictionary,
                  onChanged: (value) => setDialogState(() => useDictionary = value),
                  title: Text(context.tr('useDictionary')),
                  subtitle: Text(
                    context.tr('dictionaryKeys', {'count': keyStore.effectiveKeys.length}),
                  ),
                ),
                TextField(
                  decoration: InputDecoration(
                    labelText: '${context.tr('keys')} (hex, comma separated)',
                    hintText: 'FFFFFFFFFFFF, A0A1A2A3A4A5',
                  ),
                  onChanged: (value) => extraKeys = value,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('cancel'))),
            FilledButton(
              onPressed: () {
                final keys = <Uint8List>[
                  if (useDictionary) ...keyStore.effectiveKeys,
                  ..._parseKeys(extraKeys),
                ];
                Navigator.pop(
                  context,
                  _Mf1ReadConfig(
                    type: type,
                    name: nameController.text.trim().isEmpty
                        ? '${type.name} ${_stamp()}'
                        : nameController.text.trim(),
                    keys: keys,
                  ),
                );
              },
              child: Text(context.tr('readDump')),
            ),
          ],
        ),
      ),
    );
  }

  Future<_Mf0ReadConfig?> _showMf0ReadDialog(BuildContext context, HfScanResult result) {
    var type = result.guessedType?.isUltralight == true ? result.guessedType! : TagTypes.ntag213;
    final nameController = TextEditingController(text: '${type.name} ${_stamp()}');
    final keyController = TextEditingController();

    return showDialog<_Mf0ReadConfig>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.tr('readMfuTitle')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<TagType>(
                  value: type,
                  decoration: InputDecoration(labelText: context.tr('dumpType')),
                  items: TagTypes.ultralight
                      .map((t) => DropdownMenuItem(value: t, child: Text(t.name)))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() {
                      type = value;
                      nameController.text = '${type.name} ${_stamp()}';
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(labelText: context.tr('dumpName')),
                ),
                if (type.id == TagTypes.mf0icu2.id) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: keyController,
                    decoration: const InputDecoration(
                      labelText: 'Ultralight C 3DES key (32 hex)',
                      hintText: '00000000000000000000000000000000',
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('cancel'))),
            FilledButton(
              onPressed: () {
                Uint8List? key;
                if (type.id == TagTypes.mf0icu2.id && keyController.text.trim().isNotEmpty) {
                  try {
                    key = hexToBytes(keyController.text.trim());
                  } catch (_) {
                    return;
                  }
                  if (key.length != 16) return;
                }
                Navigator.pop(
                  context,
                  _Mf0ReadConfig(
                    type: type,
                    name: nameController.text.trim().isEmpty
                        ? '${type.name} ${_stamp()}'
                        : nameController.text.trim(),
                    ulcKey: key,
                  ),
                );
              },
              child: Text(context.tr('readDump')),
            ),
          ],
        ),
      ),
    );
  }

  static String _stamp() {
    final now = DateTime.now();
    return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  }

  static List<Uint8List> _parseKeys(String text) {
    final out = <Uint8List>[];
    for (final part in text.split(RegExp(r'[,;\s]+'))) {
      final clean = part.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
      if (clean.length == 12) out.add(hexToBytes(clean));
    }
    return out;
  }
}

class _ModeBanner extends StatelessWidget {
  const _ModeBanner({this.onSwitch});
  final VoidCallback? onSwitch;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: scheme.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.tr('modeHint'),
              style: TextStyle(color: scheme.onTertiaryContainer),
            ),
          ),
          TextButton(
            onPressed: onSwitch,
            child: Text(context.tr('switchMode')),
          ),
        ],
      ),
    );
  }
}

class _HfResultCard extends StatelessWidget {
  const _HfResultCard({required this.result, required this.session, required this.onRead});
  final HfScanResult result;
  final DeviceSession session;
  final VoidCallback onRead;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    result.isClassic
                        ? (result.guessedType?.name ?? context.tr('mf1Support'))
                        : (result.guessedType?.name ?? context.tr('cardType')),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (result.isClassic)
                  StatusPill(context.tr('mf1Support'), icon: Icons.credit_card)
                else
                  StatusPill(context.tr('tagFound'), icon: Icons.check_circle),
              ],
            ),
            const SizedBox(height: 10),
            InfoRow(label: context.tr('uid'), value: result.coll.uidHex, mono: true, copyable: true),
            InfoRow(label: context.tr('atqa'), value: result.coll.atqaHex, mono: true),
            InfoRow(label: context.tr('sak'), value: result.coll.sakHex, mono: true),
            InfoRow(
              label: context.tr('ats'),
              value: result.coll.ats.isEmpty ? '-' : result.coll.atsHex,
              mono: true,
            ),
            if (result.isClassic)
              InfoRow(label: context.tr('prngLevel'), value: result.prngName),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onRead,
                icon: const Icon(Icons.download),
                label: Text(context.tr('readDump')),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              result.isClassic
                  ? '${MifareClassic.sectorCountForType(result.guessedType ?? TagTypes.mifare1024)} sectors · '
                      '${(result.guessedType ?? TagTypes.mifare1024).mf1Blocks} blocks'
                  : (result.guessedType?.isUltralight == true
                      ? '${result.guessedType!.mfuPages} pages'
                      : ''),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _HfActions extends StatelessWidget {
  const _HfActions({required this.result, required this.session, required this.onRead});
  final HfScanResult result;
  final DeviceSession session;
  final VoidCallback onRead;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DumpStore>();
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final dump = await _pickDump(context, store, kind: result.isClassic ? DumpKind.mf1 : DumpKind.mfu);
                  if (dump == null || !context.mounted) return;
                  final slot = await _pickEmulationSlot(context, session);
                  if (slot == null || !context.mounted) return;
                  final ok = await confirm(
                    context,
                    title: context.tr('emulate'),
                    message: context.tr('initConfirm'),
                  );
                  if (!ok) return;
                  final count = await session.guard(
                    context.tr('writingEmulator'),
                    () => dump.isMf1
                        ? session.writeMf1DumpToSlot(dump, firmwareSlot: slot - 1)
                        : session.writeMfuDumpToSlot(dump, firmwareSlot: slot - 1),
                  );
                  if (count != null && context.mounted) {
                    showSnack(context, context.tr('loadedToSlot', {'slot': slot}));
                  }
                },
                icon: const Icon(Icons.play_arrow),
                label: Text(context.tr('emulate')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final kind = result.isClassic ? DumpKind.mf1 : DumpKind.mfu;
                  final dump = await _pickDump(context, store, kind: kind);
                  if (dump == null || !context.mounted) return;
                  final ok = await confirm(
                    context,
                    title: context.tr('writeToTag'),
                    message: context.tr('initConfirm'),
                    destructive: true,
                  );
                  if (!ok) return;
                  final count = await session.guard(
                    context.tr('writeToTag'),
                    () => dump.isMf1
                        ? session.writeMf1DumpToTag(dump)
                        : session.writeMfuDumpToTag(dump),
                  );
                  if (count != null && context.mounted) {
                    showSnack(context, context.tr('writtenToTag'));
                  }
                },
                icon: const Icon(Icons.upload),
                label: Text(context.tr('writeToTag')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextButton.icon(
                onPressed: () async {
                  final dump = await _pickDump(context, store, kind: result.isClassic ? DumpKind.mf1 : DumpKind.mfu);
                  if (dump != null && context.mounted) {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => DumpDetailScreen(dumpId: dump.id)),
                    );
                  }
                },
                icon: const Icon(Icons.visibility_outlined),
                label: Text(context.tr('inspect')),
              ),
            ),
            Expanded(
              child: TextButton.icon(
                onPressed: onRead,
                icon: const Icon(Icons.refresh),
                label: Text(context.tr('readDump')),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

Future<DumpRecord?> _pickDump(BuildContext context, DumpStore store, {required DumpKind kind}) {
  final candidates = store.dumps.where((d) => d.kind == kind).toList();
  if (candidates.isEmpty) {
    showSnack(context, context.tr('noDumpsYet'));
    return Future.value(null);
  }
  return showModalBottomSheet<DumpRecord>(
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
          for (final dump in candidates)
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(dump.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${dump.tagType.name} · ${dump.sizeLabel}'),
              onTap: () => Navigator.pop(context, dump),
            ),
        ],
      ),
    ),
  );
}

Future<int?> _pickEmulationSlot(BuildContext context, DeviceSession session) {
  return pickSlot(
    context,
    slotNumbers: [for (var i = 1; i <= 8; i++) i],
    title: context.tr('selectSlot'),
    subtitle: context.tr('selectSlotHint'),
    selected: session.activeSlot?.number,
  );
}

class _Mf1ReadConfig {
  _Mf1ReadConfig({required this.type, required this.name, required this.keys});
  final TagType type;
  final String name;
  final List<Uint8List> keys;
}

class _Mf0ReadConfig {
  _Mf0ReadConfig({required this.type, required this.name, this.ulcKey});
  final TagType type;
  final String name;
  final Uint8List? ulcKey;
}

class _LfDumpFactory {
  static DumpRecord fromScan(LfScanResult result) => DumpRecord(
        id: '${DateTime.now().microsecondsSinceEpoch}-${result.raw.length}',
        name: '${result.type.name} ${result.fields.values.join(' ')}'.trim(),
        kind: DumpKind.lf,
        tagTypeId: result.type.id,
        data: result.raw,
        createdAt: DateTime.now(),
        source: 'tag',
        note: result.summary,
      );
}
