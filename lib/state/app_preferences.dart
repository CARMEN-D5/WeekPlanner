import 'package:flutter/material.dart';

/// App-wide presentation preferences. It intentionally lives above
/// MaterialApp so changing the theme never replaces the provider that owns
/// plan data or any open page.
class AppPreferences extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  void setDarkMode(bool value) {
    final next = value ? ThemeMode.dark : ThemeMode.light;
    if (_themeMode == next) return;
    _themeMode = next;
    notifyListeners();
  }
}
