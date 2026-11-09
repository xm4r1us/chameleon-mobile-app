import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/strings.dart';
import '../../protocol/byte_utils.dart';
import '../../protocol/tag_types.dart';
import '../../services/device_session.dart';
import '../../services/key_store.dart';
import '../../theme.dart';
import '../widgets.dart';

class Mf1BlockScreen extends StatefulWidget {
  const Mf1BlockScreen({super.key});

  @override
  State<Mf1BlockScreen> createState() => _Mf1BlockScreenState();
}

class _Mf1BlockScreenState extends State<Mf1BlockScreen> {
  final _block = TextEditingController(text: '0');
  final _key = TextEditingController(text: 'FFFFFFFFFFFF');
  final _data = TextEditingController();
  final _operand = TextEditingController(text: '1');
  final _dstBlock = TextEditingController(text: '0');
  int _keyType = MifareClassic.keyA;
  int _operator = 0xC1;
  Uint8List? _read;
  bool _busy = false;

  @override
  void dispose() {
    _block.dispose();
    _key.dispose();
    _data.dispose();
    _operand.dispose();
    _dstBlock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keys = context.watch<KeyStore>();
    final scheme = Theme.of(context).colorScheme;
    final block = int.tryParse(_block.text) ?? 0;
    final data = _read;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('mf1BlockTools'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _block,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: context.tr('block')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _key,
                          decoration: InputDecoration(
                            labelText: context.tr('key'),
                            hintText: 'FFFFFFFFFFFF',
                          ),
                          style: AppTheme.mono,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<int>(
                    segments: [
                      ButtonSegment(value: MifareClassic.keyA, label: Text(context.tr('keyA'))),
                      ButtonSegment(value: MifareClassic.keyB, label: Text(context.tr('keyB'))),
                    ],
                    selected: {_keyType},
                    onSelectionChanged: (value) => setState(() => _keyType = value.first),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _readBlock,
                          icon: const Icon(Icons.download),
                          label: Text(context.tr('readBlock')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _busy ? null : () => _writeBlock(context),
                          icon: const Icon(Icons.upload),
                          label: Text(context.tr('writeBlock')),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final key in keys.userKeys.take(4))
                        ActionChip(
                          label: Text(key, style: AppTheme.mono.copyWith(fontSize: 11)),
                          onPressed: () => setState(() => _key.text = key),
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.key, size: 14),
                        label: Text(context.tr('dictionary')),
                        onPressed: () => setState(() {
                          if (keys.effectiveKeys.isNotEmpty) {
                            _key.text = bytesToHexUpper(keys.effectiveKeys.first);
                          }
                        }),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (data != null) ...[
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${context.tr('block')} $block',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    HexBlock(bytesToHexUpper(data, separator: ' ')),
                    if (_isValueBlock(block, data)) ...[
                      const SizedBox(height: 8),
                      InfoRow(
                        label: context.tr('valueBlock'),
                        value: '${_valueOf(data)}',
                        mono: true,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          SectionHeader(context.tr('valueBlock')),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _operand,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Operand'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _dstBlock,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: context.tr('block')),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<int>(
                    segments: [
                      ButtonSegment(value: 0xC1, label: Text('Inc')),
                      ButtonSegment(value: 0xC0, label: Text('Dec')),
                      ButtonSegment(value: 0xC2, label: Text('Restore')),
                    ],
                    selected: {_operator},
                    onSelectionChanged: (value) => setState(() => _operator = value.first),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _valueOperation,
                      icon: const Icon(Icons.functions),
                      label: Text(context.tr('apply')),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Block writes use the currently selected key. Value operations follow the '
            'MIFARE Classic increment/decrement/restore semantics.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  bool _isValueBlock(int block, Uint8List data) {
    if (block == 0 || MifareClassic.isTrailerBlock(block) || data.length < 16) return false;
    for (var i = 0; i < 4; i++) {
      if ((data[i] ^ data[i + 4]) != 0xff) return false;
      if (data[i + 8] != data[i]) return false;
    }
    return true;
  }

  int _valueOf(Uint8List data) {
    if (data.length < 4) return 0;
    return signed32(data[0] | (data[1] << 8) | (data[2] << 16) | (data[3] << 24));
  }

  Future<void> _readBlock() async {
    final session = context.read<DeviceSession>();
    final block = int.tryParse(_block.text);
    final key = _parseKey();
    if (block == null || key == null) return;
    setState(() => _busy = true);
    final data = await session.guard(
      context.tr('readBlock'),
      () => session.client!.mf1ReadBlock(block, _keyType, key),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _read = data;
    });
  }

  Future<void> _writeBlock(BuildContext context) async {
    final session = context.read<DeviceSession>();
    final block = int.tryParse(_block.text);
    final key = _parseKey();
    if (block == null || key == null) return;
    final value = await promptText(
      context,
      title: context.tr('writeBlock'),
      initial: _read == null ? '' : bytesToHexUpper(_read!),
      hint: context.tr('blockData'),
      maxLength: 32,
      validator: (value) {
        final clean = value.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
        return clean.length == 32 ? null : context.tr('invalidHex');
      },
    );
    if (value == null || !context.mounted) return;
    final clean = value.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (clean.length != 32) return;
    setState(() => _busy = true);
    final ok = await session.guard(
      context.tr('writeBlock'),
      () => session.client!.mf1WriteBlock(block, _keyType, key, hexToBytes(clean)),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok == true) {
      await _readBlock();
      if (mounted) showSnack(context, context.tr('writtenToTag'));
    }
  }

  Future<void> _valueOperation() async {
    final session = context.read<DeviceSession>();
    final src = int.tryParse(_block.text);
    final dst = int.tryParse(_dstBlock.text);
    final operand = int.tryParse(_operand.text);
    final key = _parseKey();
    if (src == null || dst == null || operand == null || key == null) return;
    setState(() => _busy = true);
    final ok = await session.guard(
      context.tr('valueBlock'),
      () => session.client!.manipulateValueBlock(
        srcBlock: src,
        srcType: _keyType,
        srcKey: key,
        operator: _operator,
        operand: operand,
        dstBlock: dst,
        dstType: _keyType,
        dstKey: key,
      ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok == true) {
      await _readBlock();
      if (mounted) showSnack(context, context.tr('done'));
    }
  }

  Uint8List? _parseKey() {
    try {
      final clean = _key.text.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
      if (clean.length != 12) {
        if (mounted) showSnack(context, 'Key must be 12 hex digits', error: true);
        return null;
      }
      return hexToBytes(clean);
    } on FormatException {
      return null;
    }
  }
}
