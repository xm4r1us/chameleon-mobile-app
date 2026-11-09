import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/strings.dart';
import '../../models/dump.dart';
import '../../services/device_session.dart';
import '../../services/dump_store.dart';
import '../widgets.dart';
import 'dump_detail_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.onNavigate});
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<DeviceSession>();
    final store = context.watch<DumpStore>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final recent = store.dumps.take(4).toList();

    return RefreshIndicator(
      onRefresh: () async {
        await session.guard(context.tr('refresh'), session.refreshAll);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _DeviceHero(session: session),
          const SizedBox(height: 18),
          SectionHeader(context.tr('quickActions')),
          Row(
            children: [
              Expanded(
                child: _QuickAction(
                  icon: Icons.nfc,
                  title: context.tr('readCard'),
                  color: scheme.primary,
                  onTap: () => onNavigate(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _QuickAction(
                  icon: Icons.grid_view,
                  title: context.tr('manageSlots'),
                  color: scheme.tertiary,
                  onTap: () => onNavigate(1),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _QuickAction(
                  icon: Icons.folder_copy,
                  title: context.tr('savedDumps'),
                  color: scheme.secondary,
                  onTap: () => onNavigate(3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Card(
            child: SwitchListTile(
              value: session.readerMode,
              onChanged: session.isBusy
                  ? null
                  : (value) async {
                      await session.guard(
                        value ? context.tr('modeReader') : context.tr('modeEmulator'),
                        () => session.setReaderMode(value),
                      );
                    },
              secondary: Icon(
                session.readerMode ? Icons.sensors : Icons.nfc,
                color: scheme.primary,
              ),
              title: Text(
                session.readerMode ? context.tr('readerMode') : context.tr('emulatorMode'),
              ),
              subtitle: Text(
                session.readerMode ? context.tr('modeHint') : context.tr('switchMode'),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SectionHeader(
            context.tr('recentDumps'),
            trailing: TextButton(
              onPressed: () => onNavigate(3),
              child: Text(context.tr('library')),
            ),
          ),
          if (recent.isEmpty)
            Card(
              child: EmptyState(
                icon: Icons.folder_open_outlined,
                title: context.tr('noDumpsYet'),
                compact: true,
                action: FilledButton.tonal(
                  onPressed: () => onNavigate(2),
                  child: Text(context.tr('readCard')),
                ),
              ),
            )
          else
            ...recent.map((dump) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _DumpTile(dump: dump),
                )),
          const SizedBox(height: 20),
          SectionHeader(context.tr('deviceInfo')),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  InfoRow(
                    label: context.tr('model'),
                    value: session.version?.modelName ?? '-',
                  ),
                  InfoRow(
                    label: context.tr('firmware'),
                    value: session.version?.version ?? '-',
                  ),
                  InfoRow(
                    label: context.tr('firmwareGit'),
                    value: session.version?.gitVersion ?? '-',
                    mono: true,
                  ),
                  InfoRow(
                    label: context.tr('chipId'),
                    value: session.chipId ?? '-',
                    mono: true,
                    copyable: session.chipId != null,
                  ),
                  InfoRow(
                    label: context.tr('bleAddress'),
                    value: session.bleAddress ?? '-',
                    mono: true,
                    copyable: session.bleAddress != null,
                  ),
                  InfoRow(
                    label: context.tr('capabilities'),
                    value: '${session.capabilities.length}',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: session.isBusy
                      ? null
                      : () => session.guard(context.tr('refresh'), session.refreshAll),
                  icon: const Icon(Icons.refresh),
                  label: Text(context.tr('refresh')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => session.disconnect(),
                  icon: const Icon(Icons.link_off),
                  label: Text(context.tr('disconnect')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeviceHero extends StatelessWidget {
  const _DeviceHero({required this.session});
  final DeviceSession session;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final battery = session.battery;
    final active = session.activeSlot;
    final percent = battery?.percentage ?? 0;
    final batteryColor = percent <= 15
        ? scheme.error
        : percent <= 35
            ? const Color(0xFFB26A00)
            : scheme.primary;
    final theme = Theme.of(context);

    return GradientCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.memory, color: scheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.version?.modelName ?? context.tr('welcome'),
                      style: theme.textTheme.titleLarge,
                    ),
                    Row(
                      children: [
                        Icon(Icons.circle, size: 8, color: scheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          context.tr('connected'),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              StatusPill(
                '${battery?.percentage ?? 0}%',
                color: batteryColor,
                icon: percent > 90 ? Icons.battery_full : Icons.battery_5_bar,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _HeroStat(
                  label: context.tr('activeSlot'),
                  value: active == null ? '-' : '${active.number}',
                  detail: active?.title ?? context.tr('emptySlot'),
                ),
              ),
              Container(
                width: 1,
                height: 38,
                color: scheme.onPrimaryContainer.withValues(alpha: 0.15),
              ),
              Expanded(
                child: _HeroStat(
                  label: context.tr('voltage'),
                  value: battery?.voltage ?? '-',
                  detail: battery == null ? '-' : '${battery.percentage}%',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value, required this.detail});
  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
          )),
          const SizedBox(height: 2),
          Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DumpTile extends StatelessWidget {
  const _DumpTile({required this.dump});
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
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: scheme.onSecondaryContainer, size: 20),
        ),
        title: Text(dump.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${dump.tagType.name} · ${dump.sizeLabel}'),
        trailing: Text(
          '${dump.createdAt.day}.${dump.createdAt.month}',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ),
    );
  }
}
