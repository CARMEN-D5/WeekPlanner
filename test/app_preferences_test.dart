import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cadence/state/app_preferences.dart';

void main() {
  group('AppPreferences', () {
    test('switches between light and dark mode and notifies on changes', () {
      // Arrange
      final preferences = AppPreferences();
      var notificationCount = 0;
      preferences.addListener(() => notificationCount++);

      // Act
      preferences.setDarkMode(true);

      // Assert
      expect(preferences.themeMode, ThemeMode.dark);
      expect(preferences.isDarkMode, isTrue);
      expect(notificationCount, 1);

      // Act
      preferences.setDarkMode(false);

      // Assert
      expect(preferences.themeMode, ThemeMode.light);
      expect(preferences.isDarkMode, isFalse);
      expect(notificationCount, 2);
    });

    test('does not notify when the requested mode is already active', () {
      // Arrange
      final preferences = AppPreferences();
      var notificationCount = 0;
      preferences.addListener(() => notificationCount++);

      // Act
      preferences.setDarkMode(false);

      // Assert
      expect(preferences.themeMode, ThemeMode.light);
      expect(notificationCount, 0);
    });
  });
}
