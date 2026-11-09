import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/strings.dart';
import '../../services/ble_scanner.dart';
import '../../services/device_session.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  String? _connectingId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BleScanner>().init();
    });
  }

  Future<void> _scan() async {
    final scanner = context.read<BleScanner>();
    if (scanner.scanning) {
      await scanner.stop();
    } else {
      await scanner.start();
    }
  }

  Future<void> _connect(BleScanEntry entry) async {
    if (_connectingId != null) return;
    setState(() => _connectingId = entry.id);
    final session = context.read<DeviceSession>();
    final ok = await session.connectBle(entry);
    if (!mounted) return;
    setState(() => _connectingId = null);
    if (!ok && session.lastError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(session.lastError!)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scanner = context.watch<BleScanner>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final connecting = _connectingId != null;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.surface,
              scheme.primaryContainer.withValues(alpha: 0.35),
              scheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
                children: [
                  _Hero(scheme: scheme),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.tr('connectDevice'),
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      if (scanner.scanning)
                        TextButton.icon(
                          onPressed: _scan,
                          icon: const Icon(Icons.stop_circle_outlined),
                          label: Text(context.tr('stopScan')),
                        )
                      else
                        FilledButton.tonalIcon(
                          onPressed: _scan,
                          icon: const Icon(Icons.bluetooth_searching),
                          label: Text(context.tr('connect')),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (scanner.error != null) _ErrorBanner(message: _scannerError(context, scanner.error!)),
                  if (scanner.scanning)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 12),
                          Text(context.tr('scanning'), style: theme.textTheme.bodyMedium),
                        ],
                      ),
                    ),
                  if (scanner.devices.isEmpty && !scanner.scanning)
                    _EmptyDevices(onScan: _scan)
                  else
                    ...scanner.devices.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _DeviceTile(
                          entry: entry,
                          busy: _connectingId == entry.id,
                          disabled: connecting,
                          onTap: () => _connect(entry),
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline, color: scheme.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.tr('requirements'),
                                  style: theme.textTheme.titleSmall,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  context.tr('requirementsHint'),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Center(
                    child: Text(
                      'Chameleon Ultra · BLE NUS · binary protocol v2',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _scannerError(BuildContext context, String error) {
    if (error == 'bluetooth_off') return context.tr('bluetoothOffHint');
    if (error.toLowerCase().contains('permission')) return context.tr('permissionDenied');
    return error;
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.scheme});
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Container(
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [scheme.primary, scheme.tertiary],
            ),
            boxShadow: [
              BoxShadow(
                color: scheme.primary.withValues(alpha: 0.3),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Icon(Icons.sensors, size: 46, color: scheme.onPrimary),
        ),
        const SizedBox(height: 18),
        Text(
          context.tr('appName'),
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          context.tr('appTagline'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.entry,
    required this.busy,
    required this.disabled,
    required this.onTap,
  });

  final BleScanEntry entry;
  final bool busy;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        onTap: disabled ? null : onTap,
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(Icons.memory, color: scheme.onPrimaryContainer),
        ),
        title: Text(entry.name.isEmpty ? 'Chameleon Ultra' : entry.name),
        subtitle: Text('${entry.id}  ·  ${entry.rssi} dBm'),
        trailing: busy
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
      ),
    );
  }
}

class _EmptyDevices extends StatelessWidget {
  const _EmptyDevices({required this.onScan});
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.bluetooth_disabled, size: 34, color: scheme.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(context.tr('noDevices'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              context.tr('noDevicesHint'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onScan,
              icon: const Icon(Icons.bluetooth_searching),
              label: Text(context.tr('scan')),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
