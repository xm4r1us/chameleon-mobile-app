import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/strings.dart';
import '../../models/device_models.dart';
import '../../protocol/byte_utils.dart';
import '../../protocol/tag_types.dart';
import '../../services/device_session.dart';
import '../../services/key_store.dart';
import '../widgets.dart';

class KeyCheckerScreen extends StatefulWidget {
  const KeyCheckerScreen({super.key});

  @override
  State<KeyCheckerScreen> createState() => _KeyCheckerScreenState();
}

class _KeyCheckerScreenState extends State<KeyCheckerScreen> {
  TagType _type = TagTypes.mifare1024;
  HfScanResult? _tag;
  Map<int, Uint8List> _found = {};
  bool _running = false;

  @override
  Widget build(BuildContext context) {
    final keys = context.watch<KeyStore>();
    final foundCount = _found.length;
    final positions = MifareClassic.sectorCountForType(_type) * 2;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('keyChecker'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<TagType>(
                    initialValue: _type,
                    decoration: InputDecoration(labelText: context.tr('dumpType')),
                    items: TagTypes.mifareClassic
                        .map((t) => DropdownMenuItem(value: t, child: Text(t.name)))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _type = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.tr('keyCount', {'count': keys.effectiveKeys.length}),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _running ? null : _scan,
                          icon: const Icon(Icons.nfc),
                          label: Text(context.tr('scanHf')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _running ? null : () => _check(keys),
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
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SectionHeader(
            context.tr('foundKeys', {'found': foundCount, 'total': positions}),
            trailing: foundCount == 0
                ? null
                : Text(
                    '${(foundCount / positions * 100).round()}%',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
          ),
          if (_found.isEmpty)
            Card(
              child: EmptyState(
                icon: Icons.key_off,
                title: context.tr('checkKeys'),
                subtitle: context.tr('dictionaryDesc'),
                compact: true,
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (var sector = 0; sector < MifareClassic.sectorCountForType(_type); sector++)
                    ListTile(
                      dense: true,
                      title: Text('${context.tr('sector')} $sector'),
                      subtitle: Text(
                        'A: ${_format(_found[sector * 2])}\nB: ${_format(_found[sector * 2 + 1])}',
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                ],
              ),
            ),
          if (foundCount > 0) ...[
            const SizedBox(height: 14),
            FilledButton.tonalIcon(
              onPressed: _running
                  ? null
                  : () async {
                      await keys.addKeys(_found.values);
                      if (context.mounted) {
                        showSnack(
                          context,
                          context.tr('keyCount', {'count': _found.values.length}),
                        );
                      }
                    },
              icon: const Icon(Icons.playlist_add),
              label: Text(context.tr('addKey')),
            ),
          ],
        ],
      ),
    );
  }

  String _format(Uint8List? key) => key == null ? '—' : bytesToHexUpper(key);

  Future<void> _scan() async {
    final session = context.read<DeviceSession>();
    final tag = await session.guard(context.tr('scanHf'), session.scanHf);
    if (tag == null) return;
    if (!tag.isClassic) {
      if (mounted) showSnack(context, context.tr('notClassicTag'), error: true);
      return;
    }
    setState(() {
      _tag = tag;
      if (tag.guessedType?.isMifareClassic == true) _type = tag.guessedType!;
    });
  }

  Future<void> _check(KeyStore keyStore) async {
    final session = context.read<DeviceSession>();
    setState(() {
      _running = true;
      _found = {};
    });
    final keys = await session.guard(
      context.tr('checkingKeys'),
      () => session.findMf1Keys(
        type: _type,
        keys: keyStore.effectiveKeys,
        onProgress: (attempted, found) => session.reportProgress(
          '${context.tr('checkingKeys')} $found/${MifareClassic.sectorCountForType(_type) * 2}',
          attempted == 0 ? null : found / (MifareClassic.sectorCountForType(_type) * 2),
        ),
      ),
    );
    if (mounted) {
      setState(() {
        _running = false;
        _found = keys ?? {};
      });
    }
  }
}
