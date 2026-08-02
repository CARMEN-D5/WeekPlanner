import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../domain/plan_item.dart';
import '../domain/timeline.dart';
import '../domain/timeline_render.dart';
import '../state/plan_controller.dart';
import 'event_editor_sheet.dart';
import 'plan_editor_page.dart';
import 'timeline_day_column.dart';

enum _PlannerView { day, week, month }

enum _EventAction { edit, copy, delete }

class TodayPage extends StatefulWidget {
  const TodayPage({super.key});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> with WidgetsBindingObserver {
  _PlannerView _view = _PlannerView.day;
  Timer? _timer;
  bool _wasBackgrounded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _wasBackgrounded = true;
      return;
    }
    if (state == AppLifecycleState.resumed && _wasBackgrounded && mounted) {
      _wasBackgrounded = false;
      final controller = context.read<PlanController>();
      controller.loadDay(controller.selectedDate);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PlanController>();
    final dayState = controller.dayState;
    final date = dayState.selectedDate;
    final timeline = dayState.timeline;
    final plan = _planForDate(dayState.plans, date);

    return Column(
      children: [
        _Header(
          date: date,
          view: _view,
          plan: plan,
          onBack: () => controller.changeDate(_moveDate(date, -1)),
          onForward: () => controller.changeDate(_moveDate(date, 1)),
          onPlanTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => PlanEditorPage(plan: plan)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _ViewTabs(
            value: _view,
            onChanged: (value) => setState(() => _view = value),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: dayState.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : !dayState.isReady
                        ? _TimelineLoadError(
                            onRetry: () => controller.loadDay(date))
                        : switch (_view) {
                            _PlannerView.day => _DayView(
                                date: date,
                                timeline: timeline!,
                                items: dayState.items
                                    .where((item) => _sameDay(item.date, date))
                                    .toList(),
                                onCreate: (start, end) =>
                                    _eventSheet(date, start, end),
                                onEdit: (item) => _eventSheet(
                                  item.date,
                                  item.startMinute,
                                  item.endMinute,
                                  current: item,
                                ),
                                onActions: _eventActions,
                              ),
                            _PlannerView.week => _WeekView(
                                date: date,
                                timeline: timeline!,
                                itemsForDay: controller.itemsForDay,
                                onAdd: (day, start, end) =>
                                    _eventSheet(day, start, end),
                                onEdit: (item) => _eventSheet(
                                  item.date,
                                  item.startMinute,
                                  item.endMinute,
                                  current: item,
                                ),
                                onActions: _eventActions,
                              ),
                            _PlannerView.month => _MonthView(
                                selected: date,
                                itemsForDay: controller.itemsForDay,
                                onSelect: (day) async {
                                  await controller.changeDate(day);
                                  if (mounted) {
                                    setState(() => _view = _PlannerView.day);
                                  }
                                },
                              ),
                          },
              ),
              if (controller.isChangingDate)
                const Positioned(
                  top: 0,
                  left: 20,
                  right: 20,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
            ],
          ),
        ),
      ],
    );
  }

  DateTime _moveDate(DateTime date, int amount) => switch (_view) {
        _PlannerView.day => date.add(Duration(days: amount)),
        _PlannerView.week => date.add(Duration(days: amount * 7)),
        _PlannerView.month => DateTime(date.year, date.month + amount, 1),
      };

  void _eventSheet(
    DateTime date,
    int initialStart,
    int initialEnd, {
    PlanItem? current,
    PlanItem? copyFrom,
  }) {
    final source = current ?? copyFrom;
    // Capture the long-lived controller before opening the overlay.  The
    // editor itself owns all text/focus state and is disposed with its route.
    final controller = context.read<PlanController>();
    showEventEditorSheet(
      context,
      date: date,
      initialStart: initialStart,
      initialEnd: initialEnd,
      mode: current != null
          ? EventEditorMode.edit
          : copyFrom != null
              ? EventEditorMode.copy
              : EventEditorMode.create,
      source: source,
      onSave: (draft) => current == null
          ? controller.addItem(
              title: draft.title,
              type: draft.type,
              startMinute: draft.startMinute,
              endMinute: draft.endMinute,
              date: draft.date,
            )
          : controller.updateItem(
              current.copyWith(
                title: draft.title,
                date: draft.date,
                type: draft.type,
                startMinute: draft.startMinute,
                endMinute: draft.endMinute,
              ),
            ),
    );
  }

  Future<void> _eventActions(PlanItem item) async {
    final action = await showModalBottomSheet<_EventAction>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit event'),
              onTap: () => Navigator.pop(sheetContext, _EventAction.edit),
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Copy event'),
              onTap: () => Navigator.pop(sheetContext, _EventAction.copy),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              textColor: const Color(0xFF9A5B57),
              iconColor: const Color(0xFF9A5B57),
              title: const Text('Delete event'),
              onTap: () => Navigator.pop(sheetContext, _EventAction.delete),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _EventAction.edit:
        _eventSheet(item.date, item.startMinute, item.endMinute, current: item);
      case _EventAction.copy:
        _eventSheet(item.date, item.startMinute, item.endMinute,
            copyFrom: item);
      case _EventAction.delete:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Delete event?'),
            content: Text('“${item.title}” will be removed from this day.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirmed == true && mounted) {
          await context.read<PlanController>().deleteItem(item);
        }
    }
  }
}

class _TimelineLoadError extends StatelessWidget {
  const _TimelineLoadError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.event_busy_outlined, size: 34),
              const SizedBox(height: 10),
              const Text('Unable to load today’s timeline'),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => onRetry(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.date,
    required this.view,
    required this.plan,
    required this.onBack,
    required this.onForward,
    required this.onPlanTap,
  });

  final DateTime date;
  final _PlannerView view;
  final Plan? plan;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onPlanTap;

  @override
  Widget build(BuildContext context) {
    final dateText = switch (view) {
      _PlannerView.day =>
        '${DateFormat('MMM d').format(date)} ${DateFormat('EEEE').format(date)}',
      _PlannerView.week =>
        'Week of ${DateFormat('MMM d').format(date.subtract(Duration(days: date.weekday - 1)))}',
      _PlannerView.month => DateFormat('yyyy MMM').format(date),
    };
    final remaining = plan == null
        ? null
        : _day(plan!.endDate).difference(_day(date)).inDays + 1;
    final status = remaining == null
        ? null
        : remaining <= 1
            ? 'Due today'
            : '$remaining days left';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onPlanTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  ClipOval(
                    child: Image.asset(
                      Theme.of(context).brightness == Brightness.dark
                          ? 'assets/branding/avatar_dark.png'
                          : 'assets/branding/avatar_light.png',
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      semanticLabel: 'WeekPlanner',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plan?.title ?? 'No active plan',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          plan == null
                              ? 'Tap to create a weekly plan'
                              : '${DateFormat('MMM d').format(plan!.startDate)} – ${DateFormat('MMM d').format(plan!.endDate)}',
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (status != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: remaining! <= 7
                            ? const Color(0xFFE8D9D7)
                            : const Color(0xFFDDE7DC),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        status,
                        style: const TextStyle(
                          color: Color(0xFF566359),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  dateText,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                onPressed: onForward,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ViewTabs extends StatelessWidget {
  const _ViewTabs({required this.value, required this.onChanged});

  final _PlannerView value;
  final ValueChanged<_PlannerView> onChanged;

  @override
  Widget build(BuildContext context) {
    const labels = {
      _PlannerView.day: 'Daily',
      _PlannerView.week: 'Week',
      _PlannerView.month: 'Month',
    };
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Row(
        children: _PlannerView.values
            .map(
              (item) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Material(
                    color: value == item
                        ? Theme.of(context).colorScheme.secondaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => onChanged(item),
                      child: Center(
                        child: Text(
                          labels[item]!,
                          style: TextStyle(
                            color: value == item
                                ? Theme.of(context)
                                    .colorScheme
                                    .onSecondaryContainer
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _DayView extends StatelessWidget {
  const _DayView({
    required this.date,
    required this.timeline,
    required this.items,
    required this.onCreate,
    required this.onEdit,
    required this.onActions,
  });

  final DateTime date;
  final TimelineModel timeline;
  final List<PlanItem> items;
  final void Function(int, int) onCreate;
  final ValueChanged<PlanItem> onEdit;
  final ValueChanged<PlanItem> onActions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth ||
            !constraints.hasBoundedHeight ||
            !constraints.maxWidth.isFinite ||
            !constraints.maxHeight.isFinite ||
            constraints.maxWidth <= 1 ||
            constraints.maxHeight <= 1) {
          return const Center(child: CircularProgressIndicator());
        }
        final columnWidth = constraints.maxWidth - 24;
        if (!columnWidth.isFinite || columnWidth <= 1) {
          return const SizedBox.shrink();
        }
        return Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
              child: SizedBox(
                // Daily view always receives a full column width. Week cards
                // use their own 188px columns and are never reused here.
                width: columnWidth,
                child: TimelineDayColumn(
                  date: date,
                  timeline: timeline,
                  events: items,
                  onCreate: onCreate,
                  onEdit: onEdit,
                  onActions: onActions,
                  showNow: _sameDay(date, DateTime.now()),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: Center(
                child: FilledButton.icon(
                  onPressed: () => onCreate(
                    timeline.visibleStart,
                    timeline.visibleStart + 60,
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('New event'),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _WeekView extends StatelessWidget {
  const _WeekView({
    required this.date,
    required this.timeline,
    required this.itemsForDay,
    required this.onAdd,
    required this.onEdit,
    required this.onActions,
  });

  final DateTime date;
  final TimelineModel timeline;
  final List<PlanItem> Function(DateTime) itemsForDay;
  final void Function(DateTime, int, int) onAdd;
  final ValueChanged<PlanItem> onEdit;
  final ValueChanged<PlanItem> onActions;

  @override
  Widget build(BuildContext context) {
    final monday = date.subtract(Duration(days: date.weekday - 1));
    final days = List.generate(7, (index) => monday.add(Duration(days: index)));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final day in days)
            SizedBox(
              width: 188,
              child: Column(
                children: [
                  Text(
                    '${DateFormat.E().format(day)} ${day.day}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 500,
                    child: SingleChildScrollView(
                      child: TimelineDayColumn(
                        date: day,
                        timeline: timeline,
                        events: itemsForDay(day),
                        pixelsPerMinute: .46,
                        onCreate: (start, end) => onAdd(day, start, end),
                        onEdit: onEdit,
                        onActions: onActions,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MonthView extends StatelessWidget {
  const _MonthView({
    required this.selected,
    required this.itemsForDay,
    required this.onSelect,
  });

  final DateTime selected;
  final List<PlanItem> Function(DateTime) itemsForDay;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(selected.year, selected.month, 1);
    final gridStart = first.subtract(Duration(days: first.weekday - 1));
    final dates =
        List.generate(42, (index) => gridStart.add(Duration(days: index)));
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(child: Center(child: Text('Mon'))),
              Expanded(child: Center(child: Text('Tue'))),
              Expanded(child: Center(child: Text('Wed'))),
              Expanded(child: Center(child: Text('Thu'))),
              Expanded(child: Center(child: Text('Fri'))),
              Expanded(child: Center(child: Text('Sat'))),
              Expanded(child: Center(child: Text('Sun'))),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: dates.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: .85,
            ),
            itemBuilder: (context, index) {
              final day = dates[index];
              final entries = itemsForDay(day)
                  .where((item) => item.countsForCompletion)
                  .toList();
              final done = entries
                  .where((item) => item.status == PlanStatus.completed)
                  .length;
              final pending = entries.length - done;
              final statusColor = _monthStatusColor(
                total: entries.length,
                pending: pending,
              );
              return InkWell(
                onTap: () => onSelect(day),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  margin: const EdgeInsets.all(2),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: day.month == selected.month
                        ? statusColor.withValues(alpha: .34)
                        : const Color(0xFFF0EFEC),
                    border:
                        Border.all(color: statusColor.withValues(alpha: .5)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${day.day}'),
                      const Spacer(),
                      if (entries.isNotEmpty)
                        Text('$done/${entries.length}',
                            style: const TextStyle(fontSize: 11)),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Icon(Icons.circle, size: 7, color: statusColor),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

Plan? _planForDate(List<Plan> plans, DateTime date) {
  final normalized = _day(date);
  for (final plan in plans) {
    if (!normalized.isBefore(_day(plan.startDate)) &&
        !normalized.isAfter(_day(plan.endDate))) {
      return plan;
    }
  }
  return null;
}

DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

Color _monthStatusColor({required int total, required int pending}) {
  if (total == 0) return const Color(0xFFB8AFC4);
  if (pending == 0) return const Color(0xFFAAB9A3);
  final unfinishedRate = pending / total;
  if (unfinishedRate >= .5) return const Color(0xFFC9A09C);
  if (unfinishedRate >= .25) return const Color(0xFFD2B08C);
  return const Color(0xFFC9D7C4);
}

String _clock(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
