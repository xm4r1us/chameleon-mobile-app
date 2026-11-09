import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/strings.dart';
import '../../services/app_settings.dart';
import '../../services/device_session.dart';
import '../widgets.dart';
import 'device_settings_screen.dart';
import 'logs_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final session = context.watch<DeviceSession>();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('settings'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SectionHeader(context.tr('theme')),
          Card(
            child: RadioGroup<ThemeMode>(
              groupValue: settings.themeMode,
              onChanged: (value) {
                if (value != null) settings.setThemeMode(value);
              },
              child: Column(
                children: [
                  for (final mode in [ThemeMode.system, ThemeMode.light, ThemeMode.dark])
                    RadioListTile<ThemeMode>(
                      value: mode,
                      title: Text(switch (mode) {
                        ThemeMode.system => context.tr('system'),
                        ThemeMode.light => context.tr('light'),
                        ThemeMode.dark => context.tr('dark'),
                      }),
                      secondary: Icon(switch (mode) {
                        ThemeMode.system => Icons.brightness_auto,
                        ThemeMode.light => Icons.light_mode,
                        ThemeMode.dark => Icons.dark_mode,
                      }),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          SectionHeader(context.tr('language')),
          Card(
            child: RadioGroup<String>(
              groupValue: settings.languageCode,
              onChanged: (value) => settings.setLanguage(value ?? 'system'),
              child: Column(
                children: [
                  RadioListTile<String>(
                    value: 'system',
                    title: Text(context.tr('system')),
                    secondary: const Icon(Icons.translate),
                  ),
                  RadioListTile<String>(
                    value: 'en',
                    title: Text(context.tr('english')),
                    secondary: const Icon(Icons.language),
                  ),
                  RadioListTile<String>(
                    value: 'tr',
                    title: Text(context.tr('turkish')),
                    secondary: const Icon(Icons.language),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          SectionHeader(context.tr('device')),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.tune),
                  title: Text(context.tr('deviceSettings')),
                  subtitle: Text(session.version?.modelName ?? context.tr('notConnected')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: session.isConnected
                      ? () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const DeviceSettingsScreen()),
                          )
                      : null,
                ),
                ListTile(
                  leading: const Icon(Icons.terminal_outlined),
                  title: Text(context.tr('logs')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LogsScreen()),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.refresh),
                  title: Text(context.tr('refresh')),
                  onTap: () => session.guard(context.tr('refresh'), session.refreshAll),
                ),
                ListTile(
                  leading: Icon(Icons.link_off, color: theme.colorScheme.error),
                  title: Text(context.tr('disconnect')),
                  onTap: () => session.disconnect(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SectionHeader(context.tr('about')),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.tr('aboutText'), style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 12),
                  const InfoRow(label: 'Version', value: '1.0.0'),
                  const InfoRow(
                    label: 'Protocol',
                    value: 'Chameleon Ultra binary v2',
                    mono: true,
                  ),
                  const InfoRow(label: 'Transport', value: 'BLE · Nordic UART'),
                  const InfoRow(label: 'License', value: 'GPL-3.0'),
                  const SizedBox(height: 8),
                  Text(
                    'Not affiliated with Proxgrind / RFID Research Group.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
