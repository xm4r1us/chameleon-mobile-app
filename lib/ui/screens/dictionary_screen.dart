import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/strings.dart';
import '../../services/key_store.dart';
import '../widgets.dart';

class DictionaryScreen extends StatelessWidget {
  const DictionaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<KeyStore>();
    final user = store.userKeys.toList()..sort();
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('dictionary')),
        actions: [
          IconButton(
            tooltip: context.tr('importDictionary'),
            onPressed: () => _import(context, store),
            icon: const Icon(Icons.file_open_outlined),
          ),
          IconButton(
            tooltip: context.tr('exportDictionary'),
            onPressed: user.isEmpty ? null : () => _export(context, store),
            icon: const Icon(Icons.save_alt),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.key, color: Theme.of(context).colorScheme.onPrimaryContainer),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('keyCount', {'count': store.totalCount}),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${context.tr('bundledKeys')}: ${KeyStore.bundledHex.length} · '
                          '${context.tr('userKeys')}: ${user.length}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => _add(context, store),
                    icon: const Icon(Icons.add),
                    label: Text(context.tr('addKey')),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          SectionHeader(context.tr('userKeys')),
          if (user.isEmpty)
            Card(
              child: EmptyState(
                icon: Icons.key_off,
                title: context.tr('userKeys'),
                subtitle: context.tr('addKey'),
                compact: true,
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (final key in user)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.key, size: 18),
                      title: Text(key, style: const TextStyle(fontFamily: 'monospace')),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => store.removeKey(key),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 18),
          SectionHeader(context.tr('bundledKeys')),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final key in KeyStore.bundledHex.toSet())
                    Chip(
                      label: Text(key, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _add(BuildContext context, KeyStore store) async {
    final value = await promptText(
      context,
      title: context.tr('addKey'),
      hint: 'FFFFFFFFFFFF',
      maxLength: 12,
      validator: (value) {
        final clean = value.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
        return clean.length == 12 ? null : '12 hex digits required';
      },
    );
    if (value == null) return;
    try {
      await store.addKey(value);
      if (context.mounted) showSnack(context, context.tr('keyAdded'));
    } on FormatException catch (error) {
      if (context.mounted) showSnack(context, error.message, error: true);
    }
  }

  Future<void> _import(BuildContext context, KeyStore store) async {
    try {
      final files = await FilePicker.pickFiles();
      if (files.isEmpty) return;
      final bytes = await files.first.readAsBytes();
      final count = await store.importDictionary(utf8.decode(bytes, allowMalformed: true));
      if (context.mounted) {
        showSnack(context, context.tr('keyCount', {'count': count}));
      }
    } catch (error) {
      if (context.mounted) showSnack(context, '$error', error: true);
    }
  }

  Future<void> _export(BuildContext context, KeyStore store) async {
    final bytes = Uint8List.fromList(utf8.encode(store.exportDictionary()));
    try {
      await FilePicker.saveFile(
        fileName: 'mifare-keys.dic',
        bytes: bytes,
        dialogTitle: context.tr('exportDictionary'),
      );
    } catch (error) {
      if (context.mounted) showSnack(context, '$error', error: true);
    }
  }
}
