import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/strings.dart';
import '../../models/dump.dart';
import '../../protocol/byte_utils.dart';
import '../../protocol/tag_types.dart';
import '../../services/device_session.dart';
import '../../services/dump_codec.dart';
import '../../services/dump_store.dart';
import '../../theme.dart';
import '../widgets.dart';

class DumpDetailScreen extends StatefulWidget {
  const DumpDetailScreen({super.key, required this.dumpId});
  final String dumpId;

  @override
  State<DumpDetailScreen> createState() => _DumpDetailScreenState();
}

class _DumpDetailScreenState extends State<DumpDetailScreen> {
  bool _showKeys = false;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DumpStore>();
    final dump = store.byId(widget.dumpId);
    if (dump == null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(icon: Icons.delete_outline, title: context.tr('noResults')),
      );
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(dump.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: context.tr('renameDump'),
            onPressed: () => _rename(context, store, dump),
            icon: const Icon(Icons.drive_file_rename_outline),
          ),
          IconButton(
            tooltip: context.tr('duplicate'),
            onPressed: () async {
              final copy = await store.duplicate(dump);
              if (context.mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => DumpDetailScreen(dumpId: copy.id)),
                );
              }
            },
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: context.tr('share'),
            onPressed: () => _share(context, dump),
            icon: const Icon(Icons.ios_share),
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'delete') {
                final ok = await confirm(
                  context,
                  title: context.tr('deleteDump'),
                  message: context.tr('deleteDumpConfirm', {'name': dump.displayName}),
                  destructive: true,
                  confirmLabel: context.tr('delete'),
                );
                if (ok) {
                  await store.delete(dump.id);
                  if (context.mounted) Navigator.pop(context);
                }
              } else if (value == 'export') {
                await _export(context, dump);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'export', child: Text(context.tr('export'))),
              PopupMenuItem(value: 'delete', child: Text(context.tr('delete'))),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          dump.tagType.name,
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      StatusPill(dump.kind.name.toUpperCase(), icon: Icons.data_object),
                    ],
                  ),
                  const SizedBox(height: 10),
                  InfoRow(label: context.tr('size'), value: dump.sizeLabel),
                  InfoRow(
                    label: context.tr('created'),
                    value: dump.createdAt.toIso8601String().substring(0, 16).replaceFirst('T', ' '),
                  ),
                  InfoRow(label: context.tr('source'), value: dump.source),
                  if (dump.note.isNotEmpty) InfoRow(label: context.tr('note'), value: dump.note),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _loadToSlot(context, dump),
                          icon: const Icon(Icons.play_arrow),
                          label: Text(context.tr('loadToSlot')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _writeToTag(context, dump),
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
                          onPressed: () => _export(context, dump),
                          icon: const Icon(Icons.save_alt),
                          label: Text(context.tr('export')),
                        ),
                      ),
                      Expanded(
                        child: TextButton.icon(
                          onPressed: () => _share(context, dump),
                          icon: const Icon(Icons.ios_share),
                          label: Text(context.tr('share')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (dump.isMf1) ...[
            const SizedBox(height: 14),
            Card(
              child: ExpansionTile(
                initiallyExpanded: _showKeys,
                onExpansionChanged: (value) => setState(() => _showKeys = value),
                leading: Icon(Icons.key, color: scheme.primary),
                title: Text(context.tr('keysSection')),
                subtitle: Text(
                  context.tr('keyCount', {'count': dump.keys.keyA.length + dump.keys.keyB.length}),
                ),
                children: _keyRows(context, store, dump),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SectionHeader(
            context.tr('hexViewer'),
            trailing: Text(
              '${dump.data.length} ${context.tr('bytes')}',
              style: theme.textTheme.labelSmall,
            ),
          ),
          if (dump.isLf)
            HexBlock(dump.data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' '))
          else if (dump.isMf1)
            ..._mf1Rows(context, store, dump)
          else if (dump.isMfu)
            ..._mfuRows(context, store, dump)
          else
            ..._rawRows(context, store, dump),
        ],
      ),
    );
  }

  List<Widget> _keyRows(BuildContext context, DumpStore store, DumpRecord dump) {
    final sectors = MifareClassic.sectorCountForType(dump.tagType);
    return [
      for (var sector = 0; sector < sectors; sector++)
        Builder(
          builder: (context) {
            final a = dump.keys.keyA[sector];
            final b = dump.keys.keyB[sector];
            return ListTile(
              dense: true,
              title: Text('${context.tr('sector')} $sector'),
              subtitle: Wrap(
                spacing: 12,
                children: [
                  Text('A: ${a == null ? '—' : bytesToHexUpper(a)}'),
                  Text('B: ${b == null ? '—' : bytesToHexUpper(b)}'),
                ],
              ),
              trailing: IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: () => _editKey(context, store, dump, sector),
              ),
            );
          },
        ),
    ];
  }

  Future<void> _editKey(BuildContext context, DumpStore store, DumpRecord dump, int sector) async {
    final currentA = dump.keys.keyA[sector];
    final currentB = dump.keys.keyB[sector];
    final type = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('${context.tr('sector')} $sector'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'A'),
            child: Text('${context.tr('keyA')}: ${currentA == null ? '—' : bytesToHexUpper(currentA)}'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'B'),
            child: Text('${context.tr('keyB')}: ${currentB == null ? '—' : bytesToHexUpper(currentB)}'),
          ),
        ],
      ),
    );
    if (type == null || !context.mounted) return;
    final current = type == 'A' ? currentA : currentB;
    final value = await promptText(
      context,
      title: '${context.tr('key')} $type · ${context.tr('sector')} $sector',
      initial: current == null ? '' : bytesToHexUpper(current),
      hint: 'FFFFFFFFFFFF',
      maxLength: 14,
      validator: (value) {
        final clean = value.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
        if (clean.isEmpty) return null;
        if (clean.length != 12) return context.tr('invalidHex').replaceAll('32', '12');
        return null;
      },
    );
    if (value == null || !context.mounted) return;
    final clean = value.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (clean.isEmpty) {
      if (type == 'A') {
        dump.keys.keyA.remove(sector);
      } else {
        dump.keys.keyB.remove(sector);
      }
    } else {
      if (clean.length != 12) return;
      if (type == 'A') {
        dump.keys.keyA[sector] = hexToBytes(clean);
      } else {
        dump.keys.keyB[sector] = hexToBytes(clean);
      }
    }
    await store.update(dump);
    if (mounted) setState(() {});
  }

  List<Widget> _mf1Rows(BuildContext context, DumpStore store, DumpRecord dump) {
    final blocks = dump.data.length ~/ 16;
    return [
      for (var block = 0; block < blocks; block++)
        _DataRow(
          index: block,
          label: '${context.tr('block')} $block · ${context.tr('sector')} '
              '${MifareClassic.sectorForBlock(block)}'
              '${MifareClassic.isTrailerBlock(block) ? ' · ${context.tr('sectorTrailer')}' : ''}',
          data: dump.data.sublist(block * 16, block * 16 + 16),
          onTap: () => _editBlock(context, store, dump, block),
        ),
    ];
  }

  List<Widget> _mfuRows(BuildContext context, DumpStore store, DumpRecord dump) {
    final pages = dump.data.length ~/ 4;
    return [
      for (var page = 0; page < pages; page++)
        _DataRow(
          index: page,
          label: '${context.tr('page')} $page',
          data: dump.data.sublist(page * 4, page * 4 + 4),
          onTap: () => _editPage(context, store, dump, page),
        ),
    ];
  }

  List<Widget> _rawRows(BuildContext context, DumpStore store, DumpRecord dump) {
    final rows = <Widget>[];
    for (var offset = 0; offset < dump.data.length; offset += 16) {
      final end = (offset + 16 < dump.data.length) ? offset + 16 : dump.data.length;
      rows.add(
        _DataRow(
          index: offset ~/ 16,
          label: '0x${offset.toRadixString(16).padLeft(4, '0')}',
          data: dump.data.sublist(offset, end),
        ),
      );
    }
    return rows;
  }

  Future<void> _editBlock(
    BuildContext context,
    DumpStore store,
    DumpRecord dump,
    int block,
  ) async {
    final value = await promptText(
      context,
      title: context.tr('editBlock', {'block': block}),
      initial: bytesToHexUpper(dump.data.sublist(block * 16, block * 16 + 16)),
      hint: context.tr('blockData'),
      maxLength: 32,
      validator: (value) {
        final clean = value.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
        return clean.length == 32 ? null : context.tr('invalidHex');
      },
    );
    if (value == null) return;
    final clean = value.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (clean.length != 32) return;
    dump.data.setRange(block * 16, block * 16 + 16, hexToBytes(clean));
    await store.update(dump);
    if (mounted) setState(() {});
  }

  Future<void> _editPage(
    BuildContext context,
    DumpStore store,
    DumpRecord dump,
    int page,
  ) async {
    final value = await promptText(
      context,
      title: '${context.tr('page')} $page',
      initial: bytesToHexUpper(dump.data.sublist(page * 4, page * 4 + 4)),
      hint: '00000000',
      maxLength: 8,
      validator: (value) {
        final clean = value.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
        return clean.length == 8 ? null : context.tr('invalidHex').replaceAll('32', '8');
      },
    );
    if (value == null) return;
    final clean = value.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (clean.length != 8) return;
    dump.data.setRange(page * 4, page * 4 + 4, hexToBytes(clean));
    await store.update(dump);
    if (mounted) setState(() {});
  }

  Future<void> _rename(BuildContext context, DumpStore store, DumpRecord dump) async {
    final value = await promptText(
      context,
      title: context.tr('renameDump'),
      initial: dump.name,
      maxLength: 64,
    );
    if (value == null || value.isEmpty) return;
    dump.name = value;
    await store.update(dump);
    if (mounted) setState(() {});
  }

  Future<void> _loadToSlot(BuildContext context, DumpRecord dump) async {
    final session = context.read<DeviceSession>();
    if (!dump.isMf1 && !dump.isMfu && !dump.isLf) {
      showSnack(context, context.tr('unsupported'), error: true);
      return;
    }
    final slot = await pickSlot(
      context,
      slotNumbers: [for (var i = 1; i <= 8; i++) i],
      title: context.tr('selectSlot'),
      subtitle: context.tr('selectSlotHint'),
      selected: session.activeSlot?.number,
    );
    if (slot == null || !context.mounted) return;
    final ok = await confirm(
      context,
      title: context.tr('loadToSlot'),
      message: context.tr('initConfirm'),
    );
    if (!ok) return;
    final count = await session.guard(
      context.tr('writingEmulator'),
      () => dump.isMf1
          ? session.writeMf1DumpToSlot(dump, firmwareSlot: slot - 1)
          : dump.isMfu
              ? session.writeMfuDumpToSlot(dump, firmwareSlot: slot - 1)
              : session.writeLfDumpToSlot(dump, firmwareSlot: slot - 1),
    );
    if (count != null && context.mounted) {
      showSnack(context, context.tr('loadedToSlot', {'slot': slot}));
    }
  }

  Future<void> _writeToTag(BuildContext context, DumpRecord dump) async {
    final session = context.read<DeviceSession>();
    if (!dump.isMf1 && !dump.isMfu && !dump.isLf) {
      showSnack(context, context.tr('unsupported'), error: true);
      return;
    }
    final ok = await confirm(
      context,
      title: context.tr('writeToTag'),
      message: dump.isLf
          ? context.tr('writeT55Confirm', {'id': dump.data.length > 8 ? dump.displayName : dump.data.map((b) => b.toRadixString(16).padLeft(2, '0')).join()})
          : context.tr('initConfirm'),
      destructive: true,
    );
    if (!ok) return;
    final count = await session.guard(
      context.tr('writeToTag'),
      () => dump.isMf1
          ? session.writeMf1DumpToTag(dump)
          : dump.isMfu
              ? session.writeMfuDumpToTag(dump)
              : session.writeLfToT55(dump.tagType, dump.data).then((_) => dump.data.length),
    );
    if (count != null && context.mounted) {
      showSnack(context, context.tr('bytesWritten', {'count': count}));
    }
  }

  Future<void> _export(BuildContext context, DumpRecord dump) async {
    final format = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.tr('exportDump')),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'bin'),
            child: Text(context.tr('exportBin')),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'eml'),
            child: Text(context.tr('exportEml')),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'json'),
            child: Text(context.tr('exportJson')),
          ),
        ],
      ),
    );
    if (format == null) return;
    final bytes = DumpCodec.exportBytes(
      dump,
      asEml: format == 'eml',
      asJson: format == 'json',
    );
    final name = _safeName(dump.displayName);
    final extension = switch (format) {
      'eml' => 'eml',
      'json' => 'json',
      _ => dump.isMfu || dump.isLf ? 'bin' : 'bin',
    };
    try {
      final uri = await FilePicker.saveFile(
        fileName: '$name.$extension',
        bytes: bytes,
        dialogTitle: context.tr('exportDump'),
      );
      if (uri != null && context.mounted) {
        showSnack(context, context.tr('copied'));
      }
    } catch (error) {
      if (context.mounted) showSnack(context, '$error', error: true);
    }
  }

  Future<void> _share(BuildContext context, DumpRecord dump) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${_safeName(dump.displayName)}.json');
      await file.writeAsString(DumpCodec.encodeJson(dump));
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          subject: dump.displayName,
        ),
      );
    } catch (error) {
      if (context.mounted) showSnack(context, '$error', error: true);
    }
  }

  static String _safeName(String name) {
    final clean = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    return clean.isEmpty ? 'dump' : clean;
  }
}

class _DataRow extends StatelessWidget {
  const _DataRow({
    required this.index,
    required this.label,
    required this.data,
    this.onTap,
  });

  final int index;
  final String label;
  final Uint8List data;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 112,
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ),
            Expanded(
              child: Text(
                bytesToHexUpper(data, separator: ' '),
                style: AppTheme.mono.copyWith(fontSize: 12.5),
              ),
            ),
            if (onTap != null)
              Icon(Icons.edit_outlined, size: 15, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
