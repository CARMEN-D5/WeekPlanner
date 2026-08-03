import 'package:flutter/foundation.dart';

@immutable
class AppDateContext {
  const AppDateContext({
    required this.systemToday,
    required this.selectedCalendarDate,
  });

  final DateTime systemToday;
  final DateTime selectedCalendarDate;

  static DateTime localDay(DateTime value) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  factory AppDateContext.now({required DateTime selectedCalendarDate}) =>
      AppDateContext(
        systemToday: localDay(DateTime.now()),
        selectedCalendarDate: localDay(selectedCalendarDate),
      );
}

bool isWithinCompletionWindow(DateTime eventDate, DateTime systemToday) {
  final event = AppDateContext.localDay(eventDate);
  final today = AppDateContext.localDay(systemToday);
  return !event.isBefore(today.subtract(const Duration(days: 7))) &&
      !event.isAfter(today.add(const Duration(days: 7)));
}
