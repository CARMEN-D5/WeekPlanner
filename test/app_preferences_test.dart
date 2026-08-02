import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cadence/state/app_preferences.dart';

void main() {
  group('AppPreferences', () {
    test('follows the system appearance by default', () {
      final preferences = AppPreferences();
      var notificationCount = 0;
      preferences.addListener(() => notificationCount++);

      expect(preferences.themeMode, ThemeMode.system);
      expect(notificationCount, 0);
    });
  });
}
