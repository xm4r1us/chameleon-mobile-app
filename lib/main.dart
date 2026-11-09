import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'protocol/key_recovery.dart';
import 'services/app_settings.dart';
import 'services/ble_scanner.dart';
import 'services/device_session.dart';
import 'services/dump_store.dart';
import 'services/key_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  KeyRecovery.init();
  final settings = AppSettings();
  final dumps = DumpStore();
  final keys = KeyStore();
  await Future.wait([settings.load(), dumps.load(), keys.load()]);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: dumps),
        ChangeNotifierProvider.value(value: keys),
        ChangeNotifierProvider(create: (_) => DeviceSession()),
        ChangeNotifierProvider(create: (_) => BleScanner()),
      ],
      child: const ChameleonApp(),
    ),
  );
}
