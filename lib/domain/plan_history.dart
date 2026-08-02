import 'plan_item.dart';
import 'timeline_render.dart';

class UnfinishedTaskGroup {
  UnfinishedTaskGroup(
      {required this.normalizedTitle, required List<PlanItem> items})
      : items = List.unmodifiable(items);

  final String normalizedTitle;
  final List<PlanItem> items;

  String get displayTitle =>
      items.first.title.trim().replaceAll(RegExp(r'\s+'), ' ');
}

class PlanHistorySummary {
  PlanHistorySummary({required this.plan, required List<PlanItem> items})
      : items =
            List.unmodifiable(items.where((item) => item.countsForCompletion)) {
    final byTitle = <String, List<PlanItem>>{};
    for (final item
        in this.items.where((item) => item.status != PlanStatus.completed)) {
      byTitle.putIfAbsent(normalizeEventTitle(item.title), () => []).add(item);
    }
    unfinishedGroups = byTitle.entries
        .map((entry) =>
            UnfinishedTaskGroup(normalizedTitle: entry.key, items: entry.value))
        .toList()
      ..sort((a, b) => b.items.length.compareTo(a.items.length));
  }

  final Plan plan;
  final List<PlanItem> items;
  late final List<UnfinishedTaskGroup> unfinishedGroups;

  int get scheduledCount => items.length;
  int get completedCount =>
      items.where((item) => item.status == PlanStatus.completed).length;
  int get incompleteCount =>
      items.where((item) => item.status != PlanStatus.completed).length;
  int get compensatedCount =>
      items.where((item) => item.compensatedById != null).length;
  int get normalCompletedCount => completedCount - compensatedCount;
  int get completionPercent =>
      scheduledCount == 0 ? 0 : (completedCount / scheduledCount * 100).round();
  bool get statisticsAreProvisional =>
      DateTime.now().isBefore(plan.finalizationDate);

  List<PlanItem> get completedItems =>
      items.where((item) => item.status == PlanStatus.completed).toList();

  List<WeeklyCompletion> get weeklyTrend {
    final groups = <DateTime, List<PlanItem>>{};
    for (final item in items) {
      final day = DateTime(item.date.year, item.date.month, item.date.day);
      final monday = day.subtract(Duration(days: day.weekday - 1));
      groups.putIfAbsent(monday, () => []).add(item);
    }
    final trend = groups.entries.map((entry) {
      final done = entry.value
          .where((item) => item.status == PlanStatus.completed)
          .length;
      final total = entry.value.length;
      return WeeklyCompletion(entry.key, total == 0 ? 0 : done / total);
    }).toList()
      ..sort((a, b) => a.week.compareTo(b.week));
    return trend;
  }
}

class WeeklyCompletion {
  const WeeklyCompletion(this.week, this.rate);

  final DateTime week;
  final double rate;
}
