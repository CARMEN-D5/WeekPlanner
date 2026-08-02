enum PlanType { task, buffer, fixed }

enum PlanStatus { pending, completed, cancelled }

enum PlanLifecycleStatus { draft, upcoming, active, finished, archived }

class Plan {
  const Plan({
    required this.id,
    required this.title,
    required this.startDate,
    required this.endDate,
    required this.repeatsWeekly,
    required this.createdAt,
    this.status = PlanLifecycleStatus.active,
    this.finishedAt,
    this.statisticsFinalizedAt,
  });
  final String id;
  final String title;
  final DateTime startDate;
  final DateTime endDate;
  final bool repeatsWeekly;
  final DateTime createdAt;
  final PlanLifecycleStatus status;
  final DateTime? finishedAt;
  final DateTime? statisticsFinalizedAt;

  PlanLifecycleStatus statusAt(DateTime value) {
    if (status == PlanLifecycleStatus.archived) {
      return PlanLifecycleStatus.archived;
    }
    final day = _day(value);
    if (day.isBefore(_day(startDate))) return PlanLifecycleStatus.upcoming;
    if (day.isAfter(_day(endDate))) return PlanLifecycleStatus.finished;
    return PlanLifecycleStatus.active;
  }

  bool isFinished(DateTime value) =>
      statusAt(value) == PlanLifecycleStatus.finished;

  DateTime get finalizationDate =>
      statisticsFinalizedAt ?? _day(endDate).add(const Duration(days: 7));

  bool contains(DateTime day) =>
      !day.isBefore(_day(startDate)) && !day.isAfter(_day(endDate));
  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

/// A weekly recurrence record. Its location is expressed only by minutes.
class WeekTemplate {
  const WeekTemplate(
      {required this.id,
      required this.planId,
      required this.title,
      required this.weekday,
      required this.type,
      required this.startMinute,
      required this.endMinute});
  final String id;
  final String planId;
  final String title;
  final int weekday;
  final PlanType type;
  final int startMinute;
  final int endMinute;
  int get duration => endMinute - startMinute;
}

/// A concrete event. It deliberately knows nothing about blocks or gaps.
class PlanItem {
  const PlanItem({
    required this.id,
    required this.title,
    required this.date,
    required this.type,
    required this.status,
    required this.startMinute,
    required this.endMinute,
    this.planId,
    this.templateId,
    this.compensatedById,
    this.completedAt,
    this.createdAt,
  });

  final String id;
  final String title;
  final DateTime date;
  final PlanType type;
  final PlanStatus status;
  final int startMinute;
  final int endMinute;
  final String? planId;
  final String? templateId;
  final String? compensatedById;
  final DateTime? completedAt;
  final DateTime? createdAt;

  bool get countsForCompletion => type != PlanType.buffer;
  int get duration => endMinute - startMinute;

  PlanItem copyWith({
    String? title,
    DateTime? date,
    PlanType? type,
    PlanStatus? status,
    int? startMinute,
    int? endMinute,
    String? compensatedById,
    DateTime? completedAt,
    bool clearCompletion = false,
  }) =>
      PlanItem(
        id: id,
        title: title ?? this.title,
        date: date ?? this.date,
        type: type ?? this.type,
        status: status ?? this.status,
        startMinute: startMinute ?? this.startMinute,
        endMinute: endMinute ?? this.endMinute,
        planId: planId,
        templateId: templateId,
        compensatedById: compensatedById ?? this.compensatedById,
        completedAt: clearCompletion ? null : completedAt ?? this.completedAt,
        createdAt: createdAt,
      );
}

class PlanConflictException implements Exception {
  const PlanConflictException(this.conflicts);
  final List<Plan> conflicts;
}
