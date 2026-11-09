import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/strings.dart';
import '../../models/dump.dart';
import '../../services/dump_store.dart';
import '../widgets.dart';
import 'dump_detail_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String _query = '';
  DumpKind? _filter;
  bool _importing = false;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DumpStore>();
    final all = store.dumps;
    final filtered = all.where((dump) {
      if (_filter != null && dump.kind != _filter) return false;
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return dump.displayName.toLowerCase().contains(q) ||
          dump.tagType.name.toLowerCase().contains(q) ||
          dump.note.toLowerCase().contains(q);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('library'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: _importing ? null : () => _import(context, store),
                icon: _importing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.file_open_outlined),
                label: Text(context.tr('import')),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: context.tr('searchDumps'),
              isDense: true,
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _FilterChip(
                label: context.tr('filterAll'),
                selected: _filter == null,
                onSelected: () => setState(() => _filter = null),
              ),
              _FilterChip(
                label: context.tr('filterMf1'),
                selected: _filter == DumpKind.mf1,
                onSelected: () => setState(() => _filter = DumpKind.mf1),
              ),
              _FilterChip(
                label: context.tr('filterMfu'),
                selected: _filter == DumpKind.mfu,
                onSelected: () => setState(() => _filter = DumpKind.mfu),
              ),
              _FilterChip(
                label: context.tr('filterLf'),
                selected: _filter == DumpKind.lf,
                onSelected: () => setState(() => _filter = DumpKind.lf),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: filtered.isEmpty
              ? EmptyState(
                  icon: Icons.folder_open_outlined,
                  title: all.isEmpty ? context.tr('noDumpsYet') : context.tr('noResults'),
                  subtitle: all.isEmpty ? context.tr('readCard') : null,
                  action: FilledButton.tonalIcon(
                    onPressed: _importing ? null : () => _import(context, store),
                    icon: const Icon(Icons.file_open_outlined),
                    label: Text(context.tr('importDump')),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _DumpCard(dump: filtered[index]),
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _import(BuildContext context, DumpStore store) async {
    setState(() => _importing = true);
    try {
      final files = await FilePicker.pickFiles();
      if (files.isEmpty) return;
      var imported = 0;
      for (final file in files) {
        try {
          final bytes = await file.readAsBytes();
          await store.importFile(file.name, bytes);
          imported++;
        } catch (error) {
          if (context.mounted) {
            showSnack(context, '${file.name}: $error', error: true);
          }
        }
      }
      if (imported > 0 && context.mounted) {
        showSnack(context, 'Imported $imported dump(s)');
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onSelected});
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
        showCheckmark: false,
      ),
    );
  }
}

class _DumpCard extends StatelessWidget {
  const _DumpCard({required this.dump});
  final DumpRecord dump;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = dump.isMf1
        ? Icons.credit_card
        : dump.isMfu
            ? Icons.style
            : dump.isLf
                ? Icons.radio
                : Icons.data_object;
    return Card(
      child: ListTile(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => DumpDetailScreen(dumpId: dump.id)),
        ),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: scheme.onSecondaryContainer, size: 21),
        ),
        title: Text(dump.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${dump.tagType.name} · ${dump.sizeLabel}'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              dump.createdAt.toIso8601String().substring(0, 10),
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 2),
            Text(
              dump.source,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
