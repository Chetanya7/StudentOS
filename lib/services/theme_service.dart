import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService {
  static final ThemeService _instance = ThemeService._internal();
  
  factory ThemeService() {
    return _instance;
  }
  
  ThemeService._internal();

  static const String _keyThemeMode = 'theme_mode';
  
  final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString(_keyThemeMode) ?? 'system';
    
    themeNotifier.value = _stringToThemeMode(savedMode);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeNotifier.value = mode;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyThemeMode, _themeModeToString(mode));
  }

  ThemeMode _stringToThemeMode(String value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  void toggleTheme() {
    final current = themeNotifier.value;
    final next = current == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    setThemeMode(next);
  }
}
