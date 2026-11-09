import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../services/device_session.dart';
import '../ui/screens/dashboard_screen.dart';
import '../ui/screens/library_screen.dart';
import '../ui/screens/logs_screen.dart';
import '../ui/screens/reader_screen.dart';
import '../ui/screens/settings_screen.dart';
import '../ui/screens/slots_screen.dart';
import '../ui/screens/tools_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  String? _lastError;


  @override
  void initState() {
    super.initState();
    final session = context.read<DeviceSession>();
    _lastError = session.lastError;
    session.addListener(_onSession);
  }

  @override
  void dispose() {
    context.read<DeviceSession>().removeListener(_onSession);
    super.dispose();
  }

  void _onSession() {
    final session = context.read<DeviceSession>();
    if (!mounted) return;
    if (!session.isConnected) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      return;
    }
    if (session.lastError != null && session.lastError != _lastError) {
      _lastError = session.lastError;
      final message = session.lastError!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(message),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
            ),
          );
      });
    } else if (session.lastError == null) {
      _lastError = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<DeviceSession>();
    final theme = Theme.of(context);
    final titles = [
      context.tr('home'),
      context.tr('slots'),
      context.tr('read'),
      context.tr('library'),
      context.tr('tools'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titles[_index]),
            Text(
              session.version?.modelName ?? context.tr('connected'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: context.tr('deviceLogs'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LogsScreen()),
            ),
            icon: const Icon(Icons.terminal_outlined),
          ),
          IconButton(
            tooltip: context.tr('settings'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'refresh') {
                await session.guard(context.tr('refresh'), session.refreshAll);
              } else if (value == 'disconnect') {
                await session.disconnect();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'refresh', child: Text(context.tr('refresh'))),
              PopupMenuItem(value: 'disconnect', child: Text(context.tr('disconnect'))),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (session.isBusy)
            LinearProgressIndicator(
              minHeight: 2,
              value: session.progress,
            ),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: [
                DashboardScreen(onNavigate: (index) => setState(() => _index = index)),
                const SlotsScreen(),
                const ReaderScreen(),
                const LibraryScreen(),
                const ToolsScreen(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.dashboard_outlined),
            selectedIcon: const Icon(Icons.dashboard),
            label: context.tr('home'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.grid_view_outlined),
            selectedIcon: const Icon(Icons.grid_view),
            label: context.tr('slots'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.nfc_outlined),
            selectedIcon: const Icon(Icons.nfc),
            label: context.tr('read'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.folder_copy_outlined),
            selectedIcon: const Icon(Icons.folder_copy),
            label: context.tr('library'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.construction_outlined),
            selectedIcon: const Icon(Icons.construction),
            label: context.tr('tools'),
          ),
        ],
      ),
    );
  }
}
