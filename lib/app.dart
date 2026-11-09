import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'services/app_settings.dart';
import 'services/device_session.dart';
import 'theme.dart';
import 'ui/screens/connect_screen.dart';
import 'ui/shell.dart';

class ChameleonApp extends StatefulWidget {
  const ChameleonApp({super.key});

  @override
  State<ChameleonApp> createState() => _ChameleonAppState();
}

class _ChameleonAppState extends State<ChameleonApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    context.read<DeviceSession>().addListener(_onSession);
  }

  @override
  void dispose() {
    context.read<DeviceSession>().removeListener(_onSession);
    super.dispose();
  }

  void _onSession() {
    final session = context.read<DeviceSession>();
    if (!session.isConnected) {
      _navigatorKey.currentState?.popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final session = context.watch<DeviceSession>();
    return MaterialApp(
      title: 'Chameleon CLI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.themeMode,
      locale: settings.locale,
      supportedLocales: const [Locale('en'), Locale('tr')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      navigatorKey: _navigatorKey,
      builder: (context, child) {
        final theme = Theme.of(context);
        final dark = theme.brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: theme.colorScheme.surface,
            statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            systemNavigationBarColor: theme.colorScheme.surface,
            systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: SafeArea(
        child: session.isConnected ? const MainShell() : const ConnectScreen(),
      ),
    );
  }
}
