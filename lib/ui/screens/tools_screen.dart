import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/strings.dart';
import '../../services/device_session.dart';
import 'console_screen.dart';
import 'dictionary_screen.dart';
import 'key_checker_screen.dart';
import 'lf_emulator_screen.dart';
import 'mf1_block_screen.dart';
import 'mf1_emulator_screen.dart';
import 'mf1_recovery_screen.dart';
import 'mfu_emulator_screen.dart';

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<DeviceSession>();
    final tools = <_Tool>[
      _Tool(
        icon: Icons.credit_card,
        title: context.tr('mf1Emulator'),
        subtitle: context.tr('mf1EmuDesc'),
        screen: const Mf1EmulatorScreen(),
        requiresDevice: true,
      ),
      _Tool(
        icon: Icons.view_module_outlined,
        title: context.tr('mf1BlockTools'),
        subtitle: context.tr('mf1BlockDesc'),
        screen: const Mf1BlockScreen(),
        requiresDevice: true,
      ),
      _Tool(
        icon: Icons.style,
        title: context.tr('mfuEmulator'),
        subtitle: context.tr('mfuEmuDesc'),
        screen: const MfuEmulatorScreen(),
        requiresDevice: true,
      ),
      _Tool(
        icon: Icons.radio,
        title: context.tr('lfEmulator'),
        subtitle: context.tr('lfEmuDesc'),
        screen: const LfEmulatorScreen(),
        requiresDevice: true,
      ),
      _Tool(
        icon: Icons.vpn_key,
        title: context.tr('keyRecovery'),
        subtitle: context.tr('keyRecoveryDesc'),
        screen: const Mf1RecoveryScreen(),
        requiresDevice: true,
      ),
      _Tool(
        icon: Icons.key,
        title: context.tr('keyChecker'),
        subtitle: context.tr('keyCheckerDesc'),
        screen: const KeyCheckerScreen(),
        requiresDevice: true,
      ),
      _Tool(
        icon: Icons.menu_book,
        title: context.tr('dictionary'),
        subtitle: context.tr('dictionaryDesc'),
        screen: const DictionaryScreen(),
      ),
      _Tool(
        icon: Icons.terminal,
        title: context.tr('rawConsole'),
        subtitle: context.tr('rawConsoleDesc'),
        screen: const ConsoleScreen(),
        requiresDevice: true,
      ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        Text(
          context.tr('tools'),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          '${session.version?.modelName ?? context.tr('notConnected')} · '
          '${session.version?.version ?? '-'}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        for (final tool in tools)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: ListTile(
                enabled: !tool.requiresDevice || session.isConnected,
                onTap: !tool.requiresDevice || session.isConnected
                    ? () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => tool.screen),
                        )
                    : null,
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(tool.icon, color: Theme.of(context).colorScheme.onPrimaryContainer),
                ),
                title: Text(tool.title),
                subtitle: Text(tool.subtitle),
                trailing: const Icon(Icons.chevron_right),
              ),
            ),
          ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    context.tr('toolsInfo'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Tool {
  const _Tool({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.screen,
    this.requiresDevice = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget screen;
  final bool requiresDevice;
}
