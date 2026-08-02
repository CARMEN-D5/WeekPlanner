import 'package:flutter/material.dart';

/// App-wide presentation preferences. It intentionally lives above
/// MaterialApp so changing the theme never replaces the provider that owns
/// plan data or any open page.
class AppPreferences extends ChangeNotifier {
  final ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;
}
