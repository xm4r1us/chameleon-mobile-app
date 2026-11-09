import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/strings.dart';
import '../../models/device_models.dart';
import '../../services/device_session.dart';
import '../widgets.dart';

class DeviceSettingsScreen extends StatefulWidget {
  const DeviceSettingsScreen({super.key});

  @override
  State<DeviceSettingsScreen> createState() => _DeviceSettingsScreenState();
}

class _DeviceSettingsScreenState extends State<DeviceSettingsScreen> {
  DeviceSettings? _settings;
  bool _loading = true;
  String? _error;
  late TextEditingController _bleKey;
  double _sleep = 15;
  double _threshold = 800;

  @override
  void initState() {
    super.initState();
    _bleKey = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _bleKey.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final session = context.read<DeviceSession>();
    setState(() {
      _loading = true;
      _error = null;
    });
    final settings = await session.guard(
      context.tr('deviceSettings'),
      () => session.client!.getDeviceSettings(),
    );
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _loading = false;
      if (settings != null) {
        _bleKey.text = settings.blePairingKey;
        _sleep = settings.sleepTimeout.toDouble();
        _threshold = settings.longPressThreshold.toDouble().clamp(100, 3000);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<DeviceSession>();
    final settings = _settings;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('deviceSettings')),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : settings == null
              ? EmptyState(
                  icon: Icons.error_outline,
                  title: _error ?? context.tr('unsupported'),
                  action: FilledButton(
                    onPressed: _load,
                    child: Text(context.tr('retry')),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    SectionHeader(context.tr('animation')),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: _SettingDropdown(
                          value: settings.animationMode,
                          items: {
                            0: context.tr('animationFull'),
                            1: context.tr('animationMinimal'),
                            3: context.tr('animationSymmetric'),
                            2: context.tr('animationNone'),
                          },
                          onChanged: (value) => setState(
                            () => _settings = _copy(animation: value),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    SectionHeader(context.tr('buttonConfig')),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _buttonRow('A', context.tr('shortPress'), settings.buttonPressA,
                                (value) => setState(() => _settings = _copy(buttonA: value))),
                            const SizedBox(height: 10),
                            _buttonRow('B', context.tr('shortPress'), settings.buttonPressB,
                                (value) => setState(() => _settings = _copy(buttonB: value))),
                            const SizedBox(height: 10),
                            _buttonRow('A', context.tr('longPress'), settings.longPressA,
                                (value) => setState(() => _settings = _copy(longA: value))),
                            const SizedBox(height: 10),
                            _buttonRow('B', context.tr('longPress'), settings.longPressB,
                                (value) => setState(() => _settings = _copy(longB: value))),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    SectionHeader(context.tr('blePairing')),
                    Card(
                      child: Column(
                        children: [
                          SwitchListTile(
                            value: settings.blePairingEnabled,
                            onChanged: (value) => setState(
                              () => _settings = _copy(bleEnabled: value),
                            ),
                            title: Text(context.tr('blePairing')),
                            secondary: const Icon(Icons.bluetooth),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: TextField(
                              controller: _bleKey,
                              maxLength: 6,
                              decoration: InputDecoration(
                                labelText: context.tr('blePairingKey'),
                                counterText: '',
                              ),
                              onChanged: (value) => setState(
                                () => _settings = _copy(bleKey: value),
                              ),
                            ),
                          ),
                          ListTile(
                            leading: const Icon(Icons.link_off),
                            title: Text(context.tr('clearBonds')),
                            onTap: () async {
                              final ok = await confirm(
                                context,
                                title: context.tr('clearBonds'),
                                message: context.tr('clearBondsConfirm'),
                                destructive: true,
                              );
                              if (!ok) return;
                              await session.guard(
                                context.tr('clearBonds'),
                                () => session.client!.deleteAllBleBonds(),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    SectionHeader(context.tr('sleepTimeout')),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(context.tr('sleepTimeout'))),
                                Text('${_sleep.round()} s'),
                              ],
                            ),
                            Slider(
                              value: _sleep,
                              min: 0,
                              max: 120,
                              divisions: 120,
                              label: '${_sleep.round()} s',
                              onChanged: (value) => setState(() => _sleep = value),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(child: Text(context.tr('longPressThreshold'))),
                                Text('${_threshold.round()} ms'),
                              ],
                            ),
                            Slider(
                              value: _threshold.clamp(100, 3000),
                              min: 100,
                              max: 3000,
                              divisions: 58,
                              label: '${_threshold.round()} ms',
                              onChanged: (value) => setState(() => _threshold = value),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: session.isBusy ? null : () => _save(session),
                      icon: const Icon(Icons.save_outlined),
                      label: Text(context.tr('saveSettings')),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: session.isBusy ? null : () => _reset(session),
                      icon: const Icon(Icons.restart_alt),
                      label: Text(context.tr('resetSettings')),
                    ),
                    const SizedBox(height: 22),
                    SectionHeader(context.tr('factoryReset')),
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.35),
                      child: Column(
                        children: [
                          ListTile(
                            leading: Icon(Icons.warning_amber, color: Theme.of(context).colorScheme.error),
                            title: Text(context.tr('factoryReset')),
                            subtitle: Text(context.tr('factoryResetConfirm')),
                            onTap: () => _factoryReset(session),
                          ),
                          ListTile(
                            leading: const Icon(Icons.system_update_alt),
                            title: Text(context.tr('enterDfu')),
                            subtitle: Text(context.tr('dfuConfirm')),
                            onTap: () => _enterDfu(session),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buttonRow(
    String button,
    String press,
    int value,
    ValueChanged<int> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 92,
          child: Text('${context.tr(button == 'A' ? 'buttonA' : 'buttonB')}\n$press'),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SettingDropdown(
            value: value,
            items: {
              0: context.tr('functionNone'),
              1: context.tr('functionNextSlot'),
              2: context.tr('functionPrevSlot'),
              3: context.tr('functionClone'),
              4: context.tr('functionBattery'),
              5: context.tr('functionFieldGen'),
            },
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  DeviceSettings _copy({
    int? animation,
    int? buttonA,
    int? buttonB,
    int? longA,
    int? longB,
    bool? bleEnabled,
    String? bleKey,
  }) {
    final current = _settings!;
    return DeviceSettings(
      animationMode: animation ?? current.animationMode,
      buttonPressA: buttonA ?? current.buttonPressA,
      buttonPressB: buttonB ?? current.buttonPressB,
      longPressA: longA ?? current.longPressA,
      longPressB: longB ?? current.longPressB,
      blePairingEnabled: bleEnabled ?? current.blePairingEnabled,
      blePairingKey: bleKey ?? current.blePairingKey,
      sleepTimeout: _sleep.round(),
      longPressThreshold: _threshold.round(),
    );
  }

  Future<void> _save(DeviceSession session) async {
    final settings = _settings;
    if (settings == null) return;
    if (_bleKey.text.length != 6) {
      showSnack(context, 'BLE pairing key must be 6 characters', error: true);
      return;
    }
    final ok = await session.guard<bool>(context.tr('saveSettings'), () async {
      final client = session.client!;
      await client.setAnimationMode(settings.animationMode);
      await client.setButtonPress(0x41, settings.buttonPressA);
      await client.setButtonPress(0x42, settings.buttonPressB);
      await client.setButtonPress(0x41, settings.longPressA, long: true);
      await client.setButtonPress(0x42, settings.longPressB, long: true);
      await client.setBlePairingEnabled(settings.blePairingEnabled);
      await client.setBlePairingKey(_bleKey.text);
      await client.setSleepTimeout(_sleep.round());
      await client.setLongPressThreshold(_threshold.round());
      await client.saveSettings();
      return true;
    });
    if (ok == true && context.mounted) {
      showSnack(context, context.tr('settingsSaved'));
    }
  }

  Future<void> _reset(DeviceSession session) async {
    final ok = await confirm(
      context,
      title: context.tr('resetSettings'),
      message: context.tr('resetSettingsConfirm'),
      destructive: true,
    );
    if (!ok) return;
    final done = await session.guard<bool>(context.tr('resetSettings'), () async {
      await session.client!.resetSettings();
      return true;
    });
    if (done == true) {
      if (context.mounted) showSnack(context, context.tr('settingsReset'));
      await _load();
    }
  }

  Future<void> _factoryReset(DeviceSession session) async {
    final ok = await confirm(
      context,
      title: context.tr('factoryReset'),
      message: context.tr('factoryResetConfirm'),
      destructive: true,
      confirmLabel: context.tr('factoryReset'),
    );
    if (!ok) return;
    final done = await session.guard<bool>(context.tr('factoryReset'), () async {
      await session.client!.factoryReset();
      return true;
    });
    if (done == true) {
      if (context.mounted) showSnack(context, context.tr('factoryResetDone'));
      await session.disconnect();
    }
  }

  Future<void> _enterDfu(DeviceSession session) async {
    final ok = await confirm(
      context,
      title: context.tr('enterDfu'),
      message: context.tr('dfuConfirm'),
      destructive: true,
    );
    if (!ok) return;
    await session.guard<void>(context.tr('enterDfu'), () async {
      await session.client!.enterBootloader();
    });
    await session.disconnect();
  }
}

class _SettingDropdown extends StatelessWidget {
  const _SettingDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final int value;
  final Map<int, String> items;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          isExpanded: true,
          value: items.containsKey(value) ? value : items.keys.first,
          items: items.entries
              .map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value)))
              .toList(),
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
        ),
      ),
    );
  }
}
