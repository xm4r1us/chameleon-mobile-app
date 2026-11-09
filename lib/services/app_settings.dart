import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings extends ChangeNotifier {
  static const _themeKey = 'theme_mode';
  static const _languageKey = 'language_code';

  ThemeMode _themeMode = ThemeMode.system;
  String _languageCode = 'system';
  bool _loaded = false;

  ThemeMode get themeMode => _themeMode;
  String get languageCode => _languageCode;
  bool get loaded => _loaded;

  Locale? get locale {
    if (_languageCode == 'system') return null;
    return Locale(_languageCode);
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final theme = prefs.getString(_themeKey);
    _themeMode = switch (theme) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    _languageCode = prefs.getString(_languageKey) ?? 'system';
    _loaded = true;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode.name);
  }

  Future<void> setLanguage(String code) async {
    _languageCode = code;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, code);
  }
}
