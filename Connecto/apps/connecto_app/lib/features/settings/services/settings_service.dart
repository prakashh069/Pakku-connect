import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService extends ChangeNotifier {
  SharedPreferences? _prefs;

  // Defaults
  ThemeMode _themeMode = ThemeMode.system;
  bool _launchAtStartup = false;
  bool _startMinimized = false;
  bool _autoOpenFolder = true;

  // Getters
  ThemeMode get themeMode => _themeMode;
  bool get launchAtStartup => _launchAtStartup;
  bool get startMinimized => _startMinimized;
  bool get autoOpenFolder => _autoOpenFolder;

  SettingsService() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _prefs = await SharedPreferences.getInstance();
    
    final themeIndex = _prefs?.getInt('theme_mode') ?? ThemeMode.system.index;
    _themeMode = ThemeMode.values[themeIndex];
    
    _launchAtStartup = _prefs?.getBool('launch_at_startup') ?? false;
    _startMinimized = _prefs?.getBool('start_minimized') ?? false;
    _autoOpenFolder = _prefs?.getBool('auto_open_folder') ?? true;
    
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    await _prefs?.setInt('theme_mode', mode.index);
    notifyListeners();
  }

  Future<void> setLaunchAtStartup(bool value) async {
    if (_launchAtStartup == value) return;
    _launchAtStartup = value;
    await _prefs?.setBool('launch_at_startup', value);
    notifyListeners();
  }

  Future<void> setStartMinimized(bool value) async {
    if (_startMinimized == value) return;
    _startMinimized = value;
    await _prefs?.setBool('start_minimized', value);
    notifyListeners();
  }

  Future<void> setAutoOpenFolder(bool value) async {
    if (_autoOpenFolder == value) return;
    _autoOpenFolder = value;
    await _prefs?.setBool('auto_open_folder', value);
    notifyListeners();
  }
}
