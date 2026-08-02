import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/plan_repository.dart';
import '../domain/plan_item.dart';
import '../domain/timeline.dart';
import '../domain/timeline_render.dart';

/// A complete, internally consistent snapshot for the currently selected day.
///
/// Keeping this as one value prevents the first frame from mixing a new date
/// with an old timeline (or with an empty event list) while SQLite is loading.
@immutable
class DayTimelineState {
  const DayTimelineState._({
    required this.selectedDate,
    required this.timeline,
    required this.items,
    required this.plans,
    required this.isLoading,
    this.error,
  });

  factory DayTimelineState.loading(DateTime selectedDate) => DayTimelineState._(
        selectedDate: selectedDate,
        timeline: null,
        items: const [],
        plans: const [],
        isLoading: true,
      );

  factory DayTimelineState.ready({
    required DateTime selectedDate,
    required TimelineModel timeline,
    required List<PlanItem> items,
    required List<Plan> plans,
  }) =>
      DayTimelineState._(
        selectedDate: selectedDate,
        timeline: timeline,
        items: List.unmodifiable(items),
        plans: List.unmodifiable(plans),
        isLoading: false,
      );

  factory DayTimelineState.failed(DateTime selectedDate, Object error) =>
      DayTimelineState._(
        selectedDate: selectedDate,
        timeline: null,
        items: const [],
        plans: const [],
        isLoading: false,
        error: error,
      );

  final DateTime selectedDate;
  final TimelineModel? timeline;
  final List<PlanItem> items;
  final List<Plan> plans;
  final bool isLoading;
  final Object? error;

  bool get isReady => !isLoading && error == null && timeline != null;

  DayTimelineState withItems(List<PlanItem> value) => DayTimelineState._(
        selectedDate: selectedDate,
        timeline: timeline,
        items: List.unmodifiable(value),
        plans: plans,
        isLoading: isLoading,
        error: error,
      );
}

/// Owns one complete timeline snapshot. The UI only leaves its loading state
/// after the selected date, timeline configuration, instances and plans have
/// all been committed together.
class PlanController extends ChangeNotifier {
  PlanController(this._repository) {
    selectedDate = normalizeLocalDate(DateTime.now());
    dayState = DayTimelineState.loading(selectedDate);
  }

  final PlanRepository _repository;
  final _uuid = const Uuid();

  late DateTime selectedDate;
  List<PlanItem> items = [];
  List<Plan> plans = [];
  TimelineModel? timeline;
  bool loading = true;
  late DayTimelineState dayState;
  int _loadGeneration = 0;
  bool _disposed = false;
  final Map<String, DayTimelineState> _dayCache = {};
  final Set<String> _updatingEventIds = {};
  bool isChangingDate = false;

  bool isUpdatingEvent(String id) => _updatingEventIds.contains(id);

  /// The app stores and compares calendar days in local time only. In
  /// particular, no query should inherit the current hour/minute or UTC date.
  static DateTime normalizeLocalDate(DateTime value) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  static DateTime _day(DateTime value) => normalizeLocalDate(value);

  /// The one and only selected-day load path. Cold start, date navigation and
  /// lifecycle refresh must all use this method so a daily timeline is never
  /// laid out from partial state.
  Future<void> loadDay(DateTime value) async {
    if (_disposed) return;
    final generation = ++_loadGeneration;
    final requestedDate = normalizeLocalDate(value);
    final cacheKey = _dateKey(requestedDate);
    final cached = _dayCache[cacheKey];

    // A day and its neighbours share one already loaded data range. Returning
    // the snapshot immediately makes arrow navigation continuous.
    if (cached != null && cached.isReady) {
      selectedDate = requestedDate;
      dayState = cached;
      timeline = cached.timeline;
      items = cached.items;
      plans = cached.plans;
      loading = false;
      isChangingDate = false;
      _notifyIfAlive();
      return;
    }

    final keepVisibleContent = dayState.isReady;
    selectedDate = requestedDate;
    if (keepVisibleContent) {
      // A jump outside the cache keeps the prior day on screen until the new
      // one is ready; only a small in-place progress indicator is shown.
      loading = false;
      isChangingDate = true;
    } else {
      dayState = DayTimelineState.loading(requestedDate);
      loading = true;
      isChangingDate = false;
    }
    _notifyIfAlive();

    try {
      // The repository filters by its indexed date column. Loading the current
      // month plus a one-week margin is enough for day/week/month views and is
      // far cheaper than generating and filtering several months in Dart.
      final rangeStart = DateTime(requestedDate.year, requestedDate.month, 1)
          .subtract(const Duration(days: 7));
      final rangeEnd = DateTime(requestedDate.year, requestedDate.month + 1, 0)
          .add(const Duration(days: 7));
      final loadedTimeline = await _repository.fetchTimeline();
      final loadedItems =
          await _repository.fetchInstances(rangeStart, rangeEnd);
      final loadedPlans = await _repository.fetchPlans();

      // A newer date request won while this query was in flight.
      if (_disposed || generation != _loadGeneration) return;

      selectedDate = requestedDate;
      timeline = loadedTimeline;
      items = List.unmodifiable(loadedItems);
      plans = List.unmodifiable(loadedPlans);
      loading = false;
      isChangingDate = false;
      dayState = DayTimelineState.ready(
        selectedDate: requestedDate,
        timeline: loadedTimeline,
        items: loadedItems,
        plans: loadedPlans,
      );
      _dayCache[cacheKey] = dayState;
      _cacheAdjacentDays(requestedDate);
      _debugTimelineSnapshot(dayState);
      _notifyIfAlive();
    } catch (error) {
      if (_disposed || generation != _loadGeneration) return;
      selectedDate = requestedDate;
      timeline = null;
      items = const [];
      plans = const [];
      loading = false;
      isChangingDate = false;
      dayState = DayTimelineState.failed(requestedDate, error);
      _debugTimelineSnapshot(dayState);
      _notifyIfAlive();
    }
  }

  Future<void> load() => loadDay(selectedDate);

  List<PlanItem> itemsForDay(DateTime value) =>
      items.where((item) => _sameDay(item.date, value)).toList()
        ..sort((a, b) => a.startMinute.compareTo(b.startMinute));

  List<PlanItem> get selectedItems => itemsForDay(selectedDate);

  List<PlanItem> itemsForRange(DateTime start, DateTime end) => items
      .where(
        (item) =>
            !item.date.isBefore(_day(start)) && !item.date.isAfter(_day(end)),
      )
      .toList();

  List<PlanItem> conflictsFor({
    required DateTime date,
    required int startMinute,
    required int endMinute,
    String? excludingId,
  }) =>
      itemsForDay(date)
          .where(
            (item) =>
                item.id != excludingId &&
                eventsOverlap(
                  startMinute: startMinute,
                  endMinute: endMinute,
                  otherStartMinute: item.startMinute,
                  otherEndMinute: item.endMinute,
                ),
          )
          .toList();

  Future<void> changeDate(DateTime value) async {
    await loadDay(value);
  }

  Future<void> addItem({
    required String title,
    required PlanType type,
    required int startMinute,
    required int endMinute,
    DateTime? date,
  }) async {
    final targetDate = _day(date ?? selectedDate);
    _ensureAvailable(
      date: targetDate,
      startMinute: startMinute,
      endMinute: endMinute,
    );
    final item = PlanItem(
      id: _uuid.v4(),
      title: title,
      date: targetDate,
      type: type,
      status: PlanStatus.pending,
      startMinute: startMinute,
      endMinute: endMinute,
      createdAt: DateTime.now(),
    );
    await _repository.saveInstance(item);
    _upsertItemLocally(item);
  }

  Future<void> updateItem(PlanItem item) async {
    _ensureAvailable(
      date: item.date,
      startMinute: item.startMinute,
      endMinute: item.endMinute,
      excludingId: item.id,
    );
    final previous = _itemById(item.id);
    _upsertItemLocally(item);
    try {
      await _repository.saveInstance(item);
    } catch (_) {
      if (previous != null) _upsertItemLocally(previous);
      rethrow;
    }
  }

  Future<void> deleteItem(PlanItem item) async {
    _removeItemLocally(item.id);
    try {
      await _repository.deleteInstance(item.id);
    } catch (_) {
      _upsertItemLocally(item);
      rethrow;
    }
  }

  Future<void> complete(PlanItem item) => _setCompletion(item, true);

  Future<void> undoComplete(PlanItem item) => _setCompletion(item, false);

  List<PlanItem> compensationCandidates({DateTime? referenceDate}) {
    final reference = _day(referenceDate ?? selectedDate);
    final cutoff = reference.subtract(const Duration(days: 7));
    return items
        .where(
          (item) =>
              item.countsForCompletion &&
              item.status == PlanStatus.pending &&
              !item.date.isBefore(cutoff) &&
              item.date.isBefore(reference),
        )
        .toList()
      ..sort((a, b) {
        final dateOrder = a.date.compareTo(b.date);
        return dateOrder != 0
            ? dateOrder
            : a.startMinute.compareTo(b.startMinute);
      });
  }

  /// Records one explicitly declared extra completion against the oldest
  /// unfinished item with this normalized title. It never changes today's
  /// planned task, so one tick cannot be counted twice.
  Future<void> compensateOldest(String normalizedTitle) async {
    final candidate = compensationCandidates().firstWhere(
      (item) => normalizeEventTitle(item.title) == normalizedTitle,
      orElse: () => throw StateError('No compensation candidate'),
    );
    final completed = candidate.copyWith(
      status: PlanStatus.completed,
      compensatedById: 'extra_${_uuid.v4()}',
      completedAt: DateTime.now(),
    );
    _upsertItemLocally(completed);
    try {
      await _repository.saveInstance(completed);
    } catch (_) {
      _upsertItemLocally(candidate);
      rethrow;
    }
  }

  Future<void> moveItem(PlanItem item, DateTime date, int startMinute) async {
    final moved = item.copyWith(
      date: _day(date),
      startMinute: startMinute,
      endMinute: startMinute + item.duration,
    );
    _ensureAvailable(
      date: moved.date,
      startMinute: moved.startMinute,
      endMinute: moved.endMinute,
      excludingId: item.id,
    );
    final previous = _itemById(item.id);
    _upsertItemLocally(moved);
    try {
      await _repository.saveInstance(moved);
    } catch (_) {
      if (previous != null) _upsertItemLocally(previous);
      rethrow;
    }
  }

  Future<void> saveTimeline(TimelineModel value) async {
    await _repository.saveTimeline(value);
    _dayCache.clear();
    await loadDay(selectedDate);
  }

  Future<void> splitTimelineSegment(String segmentId, int atMinute) async {
    await _repository.splitSegment(segmentId, atMinute);
    _dayCache.clear();
    await loadDay(selectedDate);
  }

  Future<void> mergeTimelineSegment(String segmentId) async {
    await _repository.mergeSegmentWithNext(segmentId);
    _dayCache.clear();
    await loadDay(selectedDate);
  }

  Future<void> savePlan(Plan plan, List<WeekTemplate> templates) async {
    await _repository.savePlan(plan, templates);
    _dayCache.clear();
    await loadDay(selectedDate);
  }

  Future<void> overwriteConflictingPlans(
    Plan plan,
    List<WeekTemplate> templates,
  ) async {
    await _repository.replaceConflictingAndSave(plan, templates);
    _dayCache.clear();
    await loadDay(selectedDate);
  }

  Future<void> deletePlan(String planId) async {
    await _repository.deletePlan(planId);
    _dayCache.clear();
    await loadDay(selectedDate);
  }

  Future<List<WeekTemplate>> templatesFor(String planId) =>
      _repository.fetchTemplates(planId);

  Future<List<PlanItem>> instancesForPlan(String planId) =>
      _repository.fetchInstancesForPlan(planId);

  Future<void> _setCompletion(PlanItem item, bool completed) async {
    if (_updatingEventIds.contains(item.id)) return;
    final previous = _itemById(item.id) ?? item;
    final next = completed
        ? previous.copyWith(
            status: PlanStatus.completed,
            completedAt: DateTime.now(),
          )
        : previous.copyWith(
            status: PlanStatus.pending,
            clearCompletion: true,
          );
    _updatingEventIds.add(item.id);
    _upsertItemLocally(next);
    try {
      await _repository.saveInstance(next);
    } catch (_) {
      _upsertItemLocally(previous);
      rethrow;
    } finally {
      _updatingEventIds.remove(item.id);
      _notifyIfAlive();
    }
  }

  PlanItem? _itemById(String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  void _upsertItemLocally(PlanItem item) {
    final next = List<PlanItem>.of(items);
    final index = next.indexWhere((value) => value.id == item.id);
    if (index < 0) {
      next.add(item);
    } else {
      next[index] = item;
    }
    _commitLocalItems(next);
  }

  void _removeItemLocally(String id) {
    _commitLocalItems(items.where((item) => item.id != id).toList());
  }

  void _commitLocalItems(List<PlanItem> next) {
    items = List.unmodifiable(next);
    if (dayState.isReady) dayState = dayState.withItems(items);
    for (final entry in _dayCache.entries.toList()) {
      _dayCache[entry.key] = entry.value.withItems(items);
    }
    _notifyIfAlive();
  }

  void _cacheAdjacentDays(DateTime center) {
    if (!dayState.isReady || timeline == null) return;
    for (final offset in const [-1, 1]) {
      final day = normalizeLocalDate(center.add(Duration(days: offset)));
      // Crossing into another month receives a fresh indexed monthly query,
      // so the month overview never reuses a partial neighbour snapshot.
      if (day.month != center.month || day.year != center.year) continue;
      final key = _dateKey(day);
      _dayCache[key] ??= DayTimelineState.ready(
        selectedDate: day,
        timeline: timeline!,
        items: items,
        plans: plans,
      );
    }
  }

  static String _dateKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  void _ensureAvailable({
    required DateTime date,
    required int startMinute,
    required int endMinute,
    String? excludingId,
  }) {
    final conflicts = conflictsFor(
      date: date,
      startMinute: startMinute,
      endMinute: endMinute,
      excludingId: excludingId,
    );
    if (conflicts.isNotEmpty) throw EventConflictException(conflicts);
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _notifyIfAlive() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _loadGeneration++;
    super.dispose();
  }

  void _debugTimelineSnapshot(DayTimelineState state) {
    assert(() {
      final loadedTimeline = state.timeline;
      if (loadedTimeline == null) {
        debugPrint(
          'DayTimeline: date=${state.selectedDate.toIso8601String()} '
          'loading=${state.isLoading} error=${state.error}',
        );
        return true;
      }
      final eventCount = state.items
          .where((item) => _sameDay(item.date, state.selectedDate))
          .length;
      final activePlans =
          state.plans.where((plan) => plan.contains(state.selectedDate));
      final activePlan = activePlans.isEmpty ? null : activePlans.first;
      final segmentCount = buildTimelineSegments<PlanItem>(
        timeline: loadedTimeline,
        events: itemsForDay(state.selectedDate)
            .map(
              (item) => TimelineEventSpan(
                value: item,
                startMinute: item.startMinute,
                endMinute: item.endMinute,
              ),
            )
            .toList(),
      ).length;
      debugPrint(
        'DayTimeline: date=${state.selectedDate.toIso8601String()} '
        'timezone=${DateTime.now().timeZoneName} '
        'plan=${activePlan?.title ?? 'none'} '
        'range=${loadedTimeline.visibleStart}-${loadedTimeline.visibleEnd} '
        'events=$eventCount segments=$segmentCount',
      );
      return true;
    }());
  }
}
