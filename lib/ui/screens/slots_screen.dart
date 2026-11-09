import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/strings.dart';
import '../../models/device_models.dart';
import '../../protocol/tag_types.dart';
import '../../services/device_session.dart';
import '../widgets.dart';

class SlotsScreen extends StatelessWidget {
  const SlotsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<DeviceSession>();
    final slots = session.slots;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                context.tr('slots'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            TextButton.icon(
              onPressed: session.isBusy
                  ? null
                  : () async {
                      await session.guard(context.tr('saveToFlash'), session.saveSlots);
                      if (context.mounted) showSnack(context, context.tr('flashSaved'));
                    },
              icon: const Icon(Icons.save_outlined),
              label: Text(context.tr('saveToFlash')),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${context.tr('hfLong')}  ·  ${context.tr('lfLong')}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        for (final slot in slots)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SlotCard(slot: slot),
          ),
      ],
    );
  }
}

class _SlotCard extends StatelessWidget {
  const _SlotCard({required this.slot});
  final SlotInfo slot;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Card(
      color: slot.active ? scheme.primaryContainer.withValues(alpha: 0.55) : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _showActions(context, slot),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: slot.active ? scheme.primary : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${slot.number}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: slot.active ? scheme.onPrimary : scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            slot.title,
                            style: theme.textTheme.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (slot.active)
                          StatusPill(context.tr('active'), icon: Icons.play_arrow),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (slot.hasHf)
                          StatusPill(
                            'HF · ${slot.hfType.name}',
                            color: slot.hfEnabled ? scheme.primary : scheme.outline,
                            icon: slot.hfEnabled ? Icons.check_circle : Icons.pause_circle,
                          ),
                        if (slot.hasLf)
                          StatusPill(
                            'LF · ${slot.lfType.name}',
                            color: slot.lfEnabled ? scheme.tertiary : scheme.outline,
                            icon: slot.lfEnabled ? Icons.check_circle : Icons.pause_circle,
                          ),
                        if (!slot.hasHf && !slot.hasLf)
                          Text(
                            context.tr('emptySlot'),
                            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                    if (slot.hfNick.isNotEmpty || slot.lfNick.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        [slot.hfNick, slot.lfNick].where((s) => s.isNotEmpty).join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  void _showActions(BuildContext context, SlotInfo slot) {
    final session = context.read<DeviceSession>();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  context.tr('slotActions', {'slot': slot.number}),
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
              ),
              if (!slot.active)
                ListTile(
                  leading: const Icon(Icons.play_arrow),
                  title: Text(context.tr('setActive')),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await session.guard(
                      context.tr('setActive'),
                      () => session.setActiveSlot(slot.index),
                    );
                  },
                ),
              ListTile(
                leading: const Icon(Icons.memory),
                title: Text(slot.hasHf ? '${context.tr('setType')} · HF' : '${context.tr('setType')} · HF'),
                subtitle: Text(slot.hasHf ? slot.hfType.name : context.tr('noType')),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await _setType(context, session, slot, TagSense.hf);
                },
              ),
              ListTile(
                leading: const Icon(Icons.radio),
                title: Text('${context.tr('setType')} · LF'),
                subtitle: Text(slot.hasLf ? slot.lfType.name : context.tr('noType')),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await _setType(context, session, slot, TagSense.lf);
                },
              ),
              if (slot.hasHf)
                SwitchListTile(
                  secondary: const Icon(Icons.memory),
                  title: Text('${context.tr('enable')} · HF'),
                  value: slot.hfEnabled,
                  onChanged: (value) async {
                    Navigator.pop(sheetContext);
                    await session.guard(
                      value ? context.tr('enable') : context.tr('disable'),
                      () => session.enableSlot(slot.index, TagSense.hf, value),
                    );
                  },
                ),
              if (slot.hasLf)
                SwitchListTile(
                  secondary: const Icon(Icons.radio),
                  title: Text('${context.tr('enable')} · LF'),
                  value: slot.lfEnabled,
                  onChanged: (value) async {
                    Navigator.pop(sheetContext);
                    await session.guard(
                      value ? context.tr('enable') : context.tr('disable'),
                      () => session.enableSlot(slot.index, TagSense.lf, value),
                    );
                  },
                ),
              if (slot.hasHf)
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: Text('${context.tr('rename')} · HF'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final nick = await promptText(
                      context,
                      title: '${context.tr('rename')} · HF',
                      initial: slot.hfNick,
                      hint: context.tr('nicknameHint'),
                      maxLength: 32,
                    );
                    if (nick != null) {
                      await session.guard(
                        context.tr('rename'),
                        () => session.renameSlot(slot.index, TagSense.hf, nick),
                      );
                    }
                  },
                ),
              if (slot.hasLf)
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: Text('${context.tr('rename')} · LF'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final nick = await promptText(
                      context,
                      title: '${context.tr('rename')} · LF',
                      initial: slot.lfNick,
                      hint: context.tr('nicknameHint'),
                      maxLength: 32,
                    );
                    if (nick != null) {
                      await session.guard(
                        context.tr('rename'),
                        () => session.renameSlot(slot.index, TagSense.lf, nick),
                      );
                    }
                  },
                ),
              if (slot.hasHf)
                ListTile(
                  leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                  title: Text('${context.tr('deleteSense')} · HF'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final ok = await confirm(
                      context,
                      title: context.tr('deleteSense'),
                      message: context.tr('deleteSenseConfirm', {
                        'sense': 'HF',
                        'slot': slot.number,
                      }),
                      destructive: true,
                      confirmLabel: context.tr('delete'),
                    );
                    if (ok) {
                      await session.guard(
                        context.tr('delete'),
                        () => session.removeSlotSense(slot.index, TagSense.hf),
                      );
                    }
                  },
                ),
              if (slot.hasLf)
                ListTile(
                  leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                  title: Text('${context.tr('deleteSense')} · LF'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final ok = await confirm(
                      context,
                      title: context.tr('deleteSense'),
                      message: context.tr('deleteSenseConfirm', {
                        'sense': 'LF',
                        'slot': slot.number,
                      }),
                      destructive: true,
                      confirmLabel: context.tr('delete'),
                    );
                    if (ok) {
                      await session.guard(
                        context.tr('delete'),
                        () => session.removeSlotSense(slot.index, TagSense.lf),
                      );
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _setType(
    BuildContext context,
    DeviceSession session,
    SlotInfo slot,
    TagSense sense,
  ) async {
    final selection = await showTagTypePicker(context, sense: sense);
    if (selection == null) return;
    final ok = await confirm(
      context,
      title: context.tr('setType'),
      message: context.tr('initConfirm'),
    );
    if (!ok) return;
    await session.guard(
      context.tr('setType'),
      () => session.configureSlot(
        firmwareSlot: slot.index,
        type: selection,
        activate: false,
        enable: true,
        initialize: true,
      ),
    );
    if (context.mounted) {
      showSnack(context, context.tr('slotEmulated', {'slot': slot.number, 'type': selection.name}));
    }
  }
}

Future<TagType?> showTagTypePicker(BuildContext context, {required TagSense sense}) {
  return showModalBottomSheet<TagType>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _TagTypePicker(initialSense: sense),
  );
}

class _TagTypePicker extends StatefulWidget {
  const _TagTypePicker({required this.initialSense});
  final TagSense initialSense;

  @override
  State<_TagTypePicker> createState() => _TagTypePickerState();
}

class _TagTypePickerState extends State<_TagTypePicker> {
  late TagSense _sense = widget.initialSense;
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final types = (switch (_sense) {
      TagSense.hf => TagTypes.hf,
      TagSense.lf => TagTypes.lf,
    })
        .where((type) => type.name.toLowerCase().contains(_search.toLowerCase()))
        .toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('typePicker'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                SegmentedButton<TagSense>(
                  segments: [
                    ButtonSegment(value: TagSense.hf, label: Text(context.tr('hf'))),
                    ButtonSegment(value: TagSense.lf, label: Text(context.tr('lf'))),
                  ],
                  selected: {_sense},
                  onSelectionChanged: (value) => setState(() => _sense = value.first),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: context.tr('searchTypes'),
              ),
              onChanged: (value) => setState(() => _search = value),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: types.length,
              itemBuilder: (context, index) {
                final type = types[index];
                return ListTile(
                  leading: Icon(
                    type.sense == TagSense.hf ? Icons.memory : Icons.radio,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(type.name),
                  subtitle: Text('ID ${type.id} · ${type.sense.frequency}'),
                  onTap: () => Navigator.pop(context, type),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
