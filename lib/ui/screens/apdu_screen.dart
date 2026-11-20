import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/strings.dart';
import '../../protocol/byte_utils.dart';
import '../../protocol/commands.dart';
import '../../protocol/emv_card.dart';
import '../../protocol/tlv.dart';
import '../../services/device_session.dart';
import '../../theme.dart';
import '../widgets.dart';

class ApduScreen extends StatefulWidget {
  const ApduScreen({super.key});

  @override
  State<ApduScreen> createState() => _ApduScreenState();
}

class _ApduScreenState extends State<ApduScreen> {
  final _apdu = TextEditingController();
  final List<_ApduExchange> _history = [];
  Uint8List? _response;
  String? _error;
  bool _busy = false;
  EmvPanResult? _cardResult;
  String? _cardError;
  String? _cardStep;
  bool _cardBusy = false;

  static const _presets = <String, String>{
    'Select MF': '00 A4 00 00 02 3F 00',
    'Select by name': '00 A4 04 00 00',
    'Read binary': '00 B0 00 00 00',
    'Get challenge': '00 84 00 00 08',
    'Get data': '80 CA 00 00 00',
  };

  @override
  void dispose() {
    _apdu.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<DeviceSession>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final response = _response;
    final body = response != null && response.length >= 2
        ? Uint8List.fromList(response.sublist(0, response.length - 2))
        : response;
    final sw = response != null && response.length >= 2
        ? ((response[response.length - 2] << 8) | response[response.length - 1])
        : null;
    final tlv = body == null || body.isEmpty ? null : parseTlv(body);
    final supportsApdu = session.capabilities.isEmpty ||
        session.capabilities.contains(Cmd.hf14a4ReaderApdu);

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('apduLab'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Card(
            color: scheme.tertiaryContainer.withValues(alpha: 0.4),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: scheme.onTertiaryContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('apduScope'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onTertiaryContainer,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          context.tr('apduContactlessHint'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onTertiaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!supportsApdu) ...[
            const SizedBox(height: 10),
            _WarningBanner(message: context.tr('apduFirmwareHint')),
          ],
          if (session.capabilities.isNotEmpty &&
              !session.capabilities.contains(Cmd.hf14a4EmvScan)) ...[
            const SizedBox(height: 10),
            _WarningBanner(message: context.tr('apduScanFirmwareHint')),
          ],
          if (!session.readerMode) ...[
            const SizedBox(height: 10),
            _ReaderBanner(
              onSwitch: session.isBusy
                  ? null
                  : () => session.guard(
                        context.tr('modeReader'),
                        () => session.setReaderMode(true),
                      ),
            ),
          ],
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.credit_card, color: scheme.primary, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.tr('apduReadCard'),
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.tr('apduReadCardDesc'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed:
                          _cardBusy || _busy || !session.isConnected ? null : _readCard,
                      icon: _cardBusy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.nfc),
                      label: Text(context.tr('apduReadCard')),
                    ),
                  ),
                  if (_cardBusy) ...[
                    const SizedBox(height: 10),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 6),
                    Text(
                      _cardStep == null
                          ? context.tr('apduReadingCard')
                          : '${context.tr('apduReadingCard')} · $_cardStep',
                      style: AppTheme.mono.copyWith(fontSize: 11.5),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_cardError != null) ...[
            const SizedBox(height: 10),
            _WarningBanner(message: _cardError!),
          ],
          if (_cardResult != null) ...[
            const SizedBox(height: 10),
            _CardResultCard(
              result: _cardResult!,
              onCopy: () async {
                await Clipboard.setData(ClipboardData(text: _cardResult!.pan));
                if (mounted) showSnack(context, context.tr('copied'));
              },
            ),
          ],
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _apdu,
                    minLines: 2,
                    maxLines: 5,
                    style: AppTheme.mono,
                    decoration: InputDecoration(
                      labelText: context.tr('apduCommand'),
                      hintText: context.tr('apduHexHint'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    context.tr('apduPresets'),
                    style: theme.textTheme.labelMedium,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final entry in _presets.entries)
                        ActionChip(
                          label: Text(entry.key),
                          onPressed: () => setState(() => _apdu.text = entry.value),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy || _cardBusy || !session.isConnected ? null : _send,
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                      label: Text(context.tr('apduSend')),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _WarningBanner(message: _error!),
          ],
          if (response != null) ...[
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.tr('apduResponse'),
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          tooltip: context.tr('copy'),
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: bytesToHexUpper(response, separator: ' ')),
                            );
                            if (mounted) showSnack(context, context.tr('copied'));
                          },
                          icon: const Icon(Icons.copy_rounded, size: 18),
                        ),
                      ],
                    ),
                    if (sw != null) ...[
                      const SizedBox(height: 4),
                      InfoRow(
                        label: context.tr('apduStatus'),
                        value:
                            '${sw.toRadixString(16).padLeft(4, '0').toUpperCase()} · ${swDescription(sw)}',
                        mono: true,
                      ),
                    ],
                    const SizedBox(height: 8),
                    HexBlock(bytesToHexUpper(response, separator: ' '), label: context.tr('apduRaw')),
                    if (body != null && body.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(context.tr('apduTlv'), style: theme.textTheme.titleSmall),
                      const SizedBox(height: 6),
                      if (tlv == null || tlv.nodes.isEmpty)
                        Text(
                          tlv?.error ?? context.tr('apduNoData'),
                          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        )
                      else
                        ..._buildNodes(tlv.nodes),
                    ],
                  ],
                ),
              ),
            ),
          ],
          if (_history.isNotEmpty) ...[
            const SizedBox(height: 18),
            SectionHeader(context.tr('apduHistory')),
            ..._history.reversed.map(
              (exchange) => Card(
                child: ListTile(
                  title: Text(
                    bytesToHexUpper(exchange.request, separator: ' '),
                    style: AppTheme.mono.copyWith(fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    bytesToHexUpper(exchange.response, separator: ' '),
                    style: AppTheme.mono.copyWith(fontSize: 11),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.replay, size: 18),
                    onPressed: () => setState(
                      () => _apdu.text = bytesToHexUpper(exchange.request, separator: ' '),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildNodes(List<TlvNode> nodes, [int level = 0]) {
    final out = <Widget>[];
    for (final node in nodes) {
      final indent = EdgeInsets.only(left: level * 14.0);
      out.add(
        Padding(
          padding: indent,
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    StatusPill(
                      'TAG ${node.tagHex}',
                      color: node.constructed
                          ? Theme.of(context).colorScheme.tertiary
                          : Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'LEN ${node.value.length}',
                      style: AppTheme.mono.copyWith(fontSize: 11),
                    ),
                  ],
                ),
                if (!node.constructed && node.value.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  SelectableText(
                    node.valueHex,
                    style: AppTheme.mono.copyWith(fontSize: 11.5),
                  ),
                  if (_printable(node.value)) ...[
                    const SizedBox(height: 2),
                    Text(
                      '"${String.fromCharCodes(node.value)}"',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      );
      if (node.children.isNotEmpty) out.addAll(_buildNodes(node.children, level + 1));
    }
    return out;
  }

  bool _printable(Uint8List value) =>
      value.isNotEmpty && value.every((b) => b >= 0x20 && b <= 0x7e);

  Future<bool> _ensureReaderMode(DeviceSession session) async {
    if (session.readerMode) return true;
    final switched = await session.guard<bool>(
      context.tr('modeReader'),
      () async {
        await session.setReaderMode(true);
        return true;
      },
    );
    return switched == true;
  }

  Future<void> _readCard() async {
    final session = context.read<DeviceSession>();
    final client = session.client;
    if (client == null) return;

    setState(() {
      _cardBusy = true;
      _cardError = null;
      _cardResult = null;
      _cardStep = null;
    });

    if (!await _ensureReaderMode(session)) {
      if (mounted) {
        setState(() {
          _cardBusy = false;
          _cardError = session.lastError ?? context.tr('error');
        });
      }
      return;
    }

    var notFound = false;
    final onProgress = (String step) {
      if (mounted) setState(() => _cardStep = step);
    };
    final reader = session.capabilities.contains(Cmd.hf14a4EmvScan)
        ? EmvCardReader(
            scan: () async => parseEmvScan(await client.hf14a4EmvScan()),
            onProgress: onProgress,
          )
        : EmvCardReader(
            send: client.hf14a4ReaderApdu,
            onProgress: onProgress,
          );
    final result = await session.guard<EmvPanResult?>(
      context.tr('apduReadCard'),
      () async {
        try {
          return await reader.readPan();
        } on EmvCardException {
          notFound = true;
          return null;
        }
      },
    );
    if (!mounted) return;
    setState(() {
      _cardBusy = false;
      _cardStep = null;
      if (result != null) {
        _cardResult = result;
      } else if (notFound) {
        _cardError = context.tr('apduPanNotFound');
      } else {
        _cardError = session.lastError ?? context.tr('error');
      }
    });
  }

  Future<void> _send() async {
    final session = context.read<DeviceSession>();
    Uint8List apdu;
    try {
      final clean = _apdu.text.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
      if (clean.length < 8 || clean.length.isOdd) {
        throw const FormatException('APDU too short');
      }
      apdu = hexToBytes(clean);
    } on FormatException {
      showSnack(context, context.tr('apduInvalid'), error: true);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    if (!await _ensureReaderMode(session)) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = session.lastError;
        });
      }
      return;
    }
    final response = await session.guard(
      context.tr('apduSend'),
      () => session.client!.hf14a4ReaderApdu(apdu),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (response != null) {
        _error = null;
        _response = response;
        _history.add(_ApduExchange(request: apdu, response: response));
        if (_history.length > 20) _history.removeAt(0);
      } else {
        _error = session.lastError ?? context.tr('error');
      }
    });
  }
}

class _ApduExchange {
  _ApduExchange({required this.request, required this.response});
  final Uint8List request;
  final Uint8List response;
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: scheme.onErrorContainer),
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

class _ReaderBanner extends StatelessWidget {
  const _ReaderBanner({this.onSwitch});
  final VoidCallback? onSwitch;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: scheme.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.tr('apduReaderHint'),
              style: TextStyle(color: scheme.onTertiaryContainer),
            ),
          ),
          TextButton(
            onPressed: onSwitch,
            child: Text(context.tr('switchMode')),
          ),
        ],
      ),
    );
  }
}

class _CardResultCard extends StatelessWidget {
  const _CardResultCard({required this.result, required this.onCopy});

  final EmvPanResult result;
  final VoidCallback onCopy;

  static String _panGroups(String pan) {
    final groups = <String>[];
    for (var i = 0; i < pan.length; i += 4) {
      groups.add(pan.substring(i, i + 4 > pan.length ? pan.length : i + 4));
    }
    return groups.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      color: scheme.primaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(context.tr('apduPan'), style: theme.textTheme.titleMedium),
                ),
                IconButton(
                  tooltip: context.tr('copy'),
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy_rounded, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SelectableText(
              _panGroups(result.pan),
              style: AppTheme.mono.copyWith(
                fontSize: 17,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            InfoRow(label: context.tr('apduPanAid'), value: result.aid, mono: true),
            InfoRow(label: context.tr('apduPanSource'), value: 'TAG ${result.sourceTag}', mono: true),
            InfoRow(
              label: context.tr('apduPanCandidates'),
              value: '${result.candidates.length}',
              mono: true,
            ),
          ],
        ),
      ),
    );
  }
}
