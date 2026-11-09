import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/strings.dart';
import '../../services/device_session.dart';
import '../../theme.dart';
import '../widgets.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  bool _showFrames = true;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<DeviceSession>();
    final logs = session.logs.reversed
        .where((entry) => _showFrames || (!entry.isTx && !entry.message.startsWith('RX ')))
        .toList();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('logs')),
        actions: [
          IconButton(
            tooltip: context.tr('clearLogs'),
            onPressed: session.clearLogs,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          SwitchListTile(
            value: _showFrames,
            onChanged: (value) => setState(() => _showFrames = value),
            title: const Text('Protocol frames'),
            subtitle: const Text('TX/RX hex dump'),
            secondary: const Icon(Icons.swap_vert),
          ),
          const Divider(height: 1),
          Expanded(
            child: logs.isEmpty
                ? EmptyState(
                    icon: Icons.terminal_outlined,
                    title: context.tr('logs'),
                    subtitle: 'TX/RX frames and errors appear here.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final entry = logs[index];
                      final color = entry.isError
                          ? scheme.error
                          : entry.isTx
                              ? scheme.tertiary
                              : scheme.onSurface;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.at.toIso8601String().substring(11, 19),
                              style: AppTheme.mono.copyWith(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SelectableText(
                                entry.message,
                                style: AppTheme.mono.copyWith(fontSize: 12, color: color),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
