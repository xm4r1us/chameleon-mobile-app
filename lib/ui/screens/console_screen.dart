import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/strings.dart';
import '../../protocol/byte_utils.dart';
import '../../protocol/commands.dart';
import '../../protocol/frame.dart';
import '../../services/device_session.dart';
import '../../theme.dart';
import '../widgets.dart';

class ConsoleScreen extends StatefulWidget {
  const ConsoleScreen({super.key});

  @override
  State<ConsoleScreen> createState() => _ConsoleScreenState();
}

class _ConsoleScreenState extends State<ConsoleScreen> {
  final _command = TextEditingController(text: '1000');
  final _data = TextEditingController();
  final List<_Exchange> _history = [];
  bool _busy = false;

  static const _presets = <String, int>{
    'GET_APP_VERSION': 1000,
    'GET_DEVICE_MODE': 1002,
    'GET_SLOT_INFO': 1019,
    'GET_ENABLED_SLOTS': 1023,
    'GET_ACTIVE_SLOT': 1018,
    'GET_BATTERY_INFO': 1025,
    'GET_DEVICE_CHIP_ID': 1011,
    'HF14A_SCAN': 2000,
    'MF1_DETECT_SUPPORT': 2001,
    'MF1_DETECT_PRNG': 2002,
    'MF1_GET_EMULATOR_CONFIG': 4009,
    'MF0_NTAG_GET_PAGE_COUNT': 4030,
    'EM410X_SCAN': 3000,
  };

  @override
  void dispose() {
    _command.dispose();
    _data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<DeviceSession>();
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('rawConsole')),
        actions: [
          IconButton(
            onPressed: () => setState(_history.clear),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.tr('rawConsoleDesc'), style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: _presets.values.contains(int.tryParse(_command.text))
                        ? int.tryParse(_command.text)
                        : null,
                    decoration: const InputDecoration(labelText: 'Preset'),
                    items: _presets.entries
                        .map((entry) => DropdownMenuItem(
                              value: entry.value,
                              child: Text('${entry.key} · ${entry.value}'),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _command.text = '$value';
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _command,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: context.tr('consoleCommand')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _data,
                          decoration: InputDecoration(
                            labelText: context.tr('consoleData'),
                            hintText: '00 01 02',
                          ),
                          style: AppTheme.mono,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy || !session.isConnected ? null : () => _send(session),
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                      label: Text(context.tr('send')),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SectionHeader(context.tr('response')),
          if (_history.isEmpty)
            Card(
              child: EmptyState(
                icon: Icons.terminal,
                title: context.tr('response'),
                compact: true,
              ),
            )
          else
            ..._history.reversed.map(
              (exchange) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ExchangeCard(exchange: exchange),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _send(DeviceSession session) async {
    final command = int.tryParse(_command.text.trim());
    if (command == null || command < 0 || command > 0xffff) {
      showSnack(context, context.tr('invalidCommand'), error: true);
      return;
    }
    Uint8List data;
    try {
      final clean = _data.text.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
      data = clean.isEmpty ? Uint8List(0) : hexToBytes(clean);
    } on FormatException catch (error) {
      showSnack(context, error.message, error: true);
      return;
    }
    setState(() => _busy = true);
    final frame = await session.guard(
      'CMD $command',
      () => session.client!.send(
        command,
        data: data,
        skipStatusCheck: true,
        timeout: const Duration(seconds: 8),
      ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (frame != null) {
      setState(() {
        _history.add(_Exchange(command: command, request: data, frame: frame));
      });
    }
  }
}

class _Exchange {
  _Exchange({required this.command, required this.request, required this.frame});
  final int command;
  final Uint8List request;
  final ChameleonFrame frame;
}

class _ExchangeCard extends StatelessWidget {
  const _ExchangeCard({required this.exchange});
  final _Exchange exchange;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ok = Status.successStatuses.contains(exchange.frame.status);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'CMD ${exchange.command}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                StatusPill(
                  '0x${exchange.frame.status.toRadixString(16).padLeft(2, '0')} · '
                  '${Status.describe(exchange.frame.status)}',
                  color: ok ? scheme.primary : scheme.error,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (exchange.request.isNotEmpty)
              InfoRow(
                label: 'TX',
                value: bytesToHexUpper(exchange.request, separator: ' '),
                mono: true,
              ),
            InfoRow(
              label: 'RX',
              value: exchange.frame.data.isEmpty
                  ? '(empty)'
                  : bytesToHexUpper(exchange.frame.data, separator: ' '),
              mono: true,
            ),
            InfoRow(
              label: 'LEN',
              value: '${exchange.frame.data.length}',
            ),
          ],
        ),
      ),
    );
  }
}
