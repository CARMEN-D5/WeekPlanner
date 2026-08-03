import 'package:flutter_test/flutter_test.dart';

import 'package:cadence/domain/app_date_context.dart';

void main() {
  test('normalizes system and selected dates independently', () {
    final context = AppDateContext(
      systemToday: AppDateContext.localDay(DateTime(2026, 8, 3, 23, 15)),
      selectedCalendarDate:
          AppDateContext.localDay(DateTime(2026, 8, 19, 8, 30)),
    );

    expect(context.systemToday, DateTime(2026, 8, 3));
    expect(context.selectedCalendarDate, DateTime(2026, 8, 19));
  });

  test('completion window includes both seven-day boundaries', () {
    final today = DateTime(2026, 8, 3);

    expect(isWithinCompletionWindow(DateTime(2026, 7, 27), today), isTrue);
    expect(isWithinCompletionWindow(DateTime(2026, 8, 10), today), isTrue);
    expect(isWithinCompletionWindow(DateTime(2026, 7, 26), today), isFalse);
    expect(isWithinCompletionWindow(DateTime(2026, 8, 11), today), isFalse);
  });
}
