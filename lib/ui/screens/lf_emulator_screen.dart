import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/strings.dart';
import '../../models/dump.dart';
import '../../protocol/byte_utils.dart';
import '../../protocol/tag_types.dart';
import '../../services/device_session.dart';
import '../../services/dump_store.dart';
import '../widgets.dart';

class LfEmulatorScreen extends StatefulWidget {
  const LfEmulatorScreen({super.key});

  @override
  State<LfEmulatorScreen> createState() => _LfEmulatorScreenState();
}

class _LfEmulatorScreenState extends State<LfEmulatorScreen> {
  Uint8List? _id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final session = context.read<DeviceSession>();
    final slot = session.activeSlot;
    if (slot == null || !slot.hasLf) return;
    final id = await session.guard(
      context.tr('lfEmulator'),
      () => session.readLfEmulatorId(slot.lfType),
    );
    if (mounted) setState(() => _id = id);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<DeviceSession>();
    final slot = session.activeSlot;
    if (slot == null || !slot.hasLf) {
      return Scaffold(
        appBar: AppBar(title: Text(context.tr('lfEmulator'))),
        body: EmptyState(
          icon: Icons.radio,
          title: context.tr('slotTypeMismatch'),
          subtitle: context.tr('initSlotFirst'),
          action: FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('slots')),
          ),
        ),
      );
    }

    final id = _id;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('lfEmulator')),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
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
                  Text('${context.tr('slot')} ${slot.number} · ${slot.lfType.name}',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  InfoRow(
                    label: context.tr('id'),
                    value: id == null ? '-' : bytesToHexUpper(id),
                    mono: true,
                    copyable: id != null,
                  ),
                  InfoRow(
                    label: context.tr('type'),
                    value: slot.lfType.name,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _manualId(session, slot.lfType),
                          icon: const Icon(Icons.edit),
                          label: Text(context.tr('edit')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () => _loadDump(session),
                          icon: const Icon(Icons.upload),
                          label: Text(context.tr('loadDump')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.tr('lfLong'), style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Text(
                    'The emulated ID is served by the active slot. Use Slots to change the '
                    '125 kHz tag type, and save the slot configuration after editing.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _manualId(DeviceSession session, TagType type) async {
    final value = await promptText(
      context,
      title: context.tr('id'),
      initial: _id == null ? '' : bytesToHexUpper(_id!),
      hint: '1234567890',
      maxLength: 40,
    );
    if (value == null || value.isEmpty) return;
    try {
      final bytes = hexToBytes(value);
      await session.guard(
        context.tr('lfEmulator'),
        () async {
          await session.setLfEmulatorId(type, bytes);
        },
      );
      await _load();
      if (mounted) showSnack(context, context.tr('emulatorIdUpdated'));
    } on FormatException catch (error) {
      if (mounted) showSnack(context, error.message, error: true);
    }
  }

  Future<void> _loadDump(DeviceSession session) async {
    final store = context.read<DumpStore>();
    final dumps = store.dumps.where((d) => d.isLf).toList();
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
      () => session.writeLfDumpToSlot(dump, firmwareSlot: slot.index),
    );
    if (count != null) {
      await _load();
      if (mounted) {
        showSnack(context, context.tr('loadedToSlot', {'slot': slot.number}));
      }
    }
  }
}
