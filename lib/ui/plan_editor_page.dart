import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../domain/plan_item.dart';
import '../domain/timeline.dart';
import '../domain/timeline_render.dart';
import '../state/plan_controller.dart';
import 'event_conflict_dialog.dart';
import 'time_wheel_picker.dart';
import 'type_tabs.dart';
import 'timeline_labels.dart';

class PlanEditorPage extends StatefulWidget {
  const PlanEditorPage({super.key, this.plan});

  final Plan? plan;

  @override
  State<PlanEditorPage> createState() => _PlanEditorPageState();
}

enum _UnsavedExitAction { keepEditing, discard, save }

class _PlanEditorPageState extends State<PlanEditorPage> {
  final _uuid = const Uuid();
  late final String _planId;
  late final TextEditingController _title;
  late DateTime _start;
  late DateTime _end;
  bool _repeats = true;
  bool _loading = false;
  bool _allowPop = false;
  List<WeekTemplate> _templates = [];
  WeekTemplate? _copySource;
  String _savedFingerprint = '';

  @override
  void initState() {
    super.initState();
    final plan = widget.plan;
    _planId = plan?.id ?? _uuid.v4();
    _title = TextEditingController(text: plan?.title ?? '');
    _start = _day(plan?.startDate ?? DateTime.now());
    _end = _day(plan?.endDate ?? DateTime.now().add(const Duration(days: 30)));
    _repeats = plan?.repeatsWeekly ?? true;
    _title.addListener(_markDraftChanged);
    _savedFingerprint = _draftFingerprint();
    if (plan != null) _loadTemplates();
  }

  @override
  void dispose() {
    _title.removeListener(_markDraftChanged);
    _title.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    setState(() => _loading = true);
    final templates =
        await context.read<PlanController>().templatesFor(_planId);
    if (mounted) {
      setState(() {
        _templates = templates;
        _loading = false;
        _savedFingerprint = _draftFingerprint();
      });
    }
  }

  bool get _isDirty => _draftFingerprint() != _savedFingerprint;

  String _draftFingerprint() {
    final entries = _templates
        .map(
          (item) => [
            item.id,
            item.title,
            item.weekday,
            item.type.name,
            item.startMinute,
            item.endMinute,
          ].join(':'),
        )
        .toList()
      ..sort();
    return [
      _title.text,
      _start.toIso8601String(),
      _end.toIso8601String(),
      _repeats,
      entries.join('|'),
    ].join('\u001f');
  }

  void _markDraftChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final timeline = context.watch<PlanController>().timeline;
    return PopScope(
      canPop: _allowPop || !_isDirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _requestExit();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
              widget.plan == null ? 'New weekly plan' : 'Edit weekly plan'),
          actions: [
            TextButton(
              onPressed: _loading ? null : _save,
              child: const Text('Save'),
            ),
          ],
        ),
        body: _loading || timeline == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _PlanDetails(
                    title: _title,
                    start: _start,
                    end: _end,
                    repeats: _repeats,
                    onStart: () => _pickDate(true),
                    onEnd: () => _pickDate(false),
                    onRepeat: (value) => setState(() => _repeats = value),
                  ),
                  if (_copySource != null)
                    MaterialBanner(
                      content: Text(
                          'Copying “${_copySource!.title}”. Tap a target time slot.'),
                      actions: [
                        TextButton(
                          onPressed: () => setState(() => _copySource = null),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  Expanded(
                    child: _TemplateWeekTimeline(
                      timeline: timeline,
                      templates: _templates,
                      onCreate: _createTemplateAt,
                      onEdit: _editTemplate,
                      onActions: _onTemplateActions,
                      onMove: _moveTemplate,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _requestExit() async {
    if (!_isDirty || !mounted) return;
    final action = await showDialog<_UnsavedExitAction>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard unsaved changes?'),
        content: const Text('Changes to this plan have not been saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              _UnsavedExitAction.keepEditing,
            ),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              _UnsavedExitAction.discard,
            ),
            child: const Text('Discard changes'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _UnsavedExitAction.save),
            child: const Text('Save and exit'),
          ),
        ],
      ),
    );
    if (!mounted ||
        action == null ||
        action == _UnsavedExitAction.keepEditing) {
      return;
    }
    if (action == _UnsavedExitAction.save) {
      await _save();
      return;
    }
    setState(() => _allowPop = true);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickDate(bool start) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _start : _end,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = _day(picked);
        if (_end.isBefore(_start)) _end = _start;
      } else {
        _end = _day(picked);
        if (_end.isBefore(_start)) _start = _end;
      }
    });
  }

  bool _canPlaceTemplate({
    required int weekday,
    required int startMinute,
    required int endMinute,
    String? excludingId,
  }) {
    final conflicts = _templates
        .where(
          (item) =>
              item.id != excludingId &&
              item.weekday == weekday &&
              eventsOverlap(
                startMinute: startMinute,
                endMinute: endMinute,
                otherStartMinute: item.startMinute,
                otherEndMinute: item.endMinute,
              ),
        )
        .toList();
    if (conflicts.isEmpty) return true;
    showTemplateConflictDialog(context, TemplateConflictException(conflicts));
    return false;
  }

  void _createTemplateAt(int weekday, int startMinute, int endMinute) {
    if (_copySource != null) {
      final source = _copySource!;
      final timelineEnd = context.read<PlanController>().timeline!.visibleEnd;
      final duration =
          source.duration.clamp(1, timelineEnd - startMinute) as int;
      if (!_canPlaceTemplate(
        weekday: weekday,
        startMinute: startMinute,
        endMinute: startMinute + duration,
      )) {
        return;
      }
      setState(() {
        _templates.add(
          WeekTemplate(
            id: _uuid.v4(),
            planId: _planId,
            title: source.title,
            weekday: weekday,
            type: source.type,
            startMinute: startMinute,
            endMinute: startMinute + duration,
          ),
        );
        _copySource = null;
      });
      return;
    }
    _eventSheet(weekday, startMinute, endMinute);
  }

  void _eventSheet(
    int weekday,
    int initialStart,
    int initialEnd, {
    WeekTemplate? current,
  }) {
    var title = current?.title ?? '';
    var type = current?.type ?? PlanType.task;
    var start = current?.startMinute ?? initialStart;
    var end = current?.endMinute ?? initialEnd;
    if (end <= start) end = start + 1;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              24,
              24,
              MediaQuery.viewInsetsOf(context).bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_weekday(weekday)} · ${current == null ? 'New template event' : 'Edit template event'}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  initialValue: title,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Event name'),
                  onChanged: (value) => title = value,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _TimeButton(
                        label: 'Start',
                        minute: start,
                        onTap: () async {
                          final value = await _timePicker(context, start);
                          if (value == null || !context.mounted) return;
                          setSheetState(() {
                            start = value;
                            if (end <= start) end = start + 1;
                          });
                        },
                      ),
                    ),
                    Expanded(
                      child: _TimeButton(
                        label: 'End',
                        minute: end,
                        onTap: () async {
                          final value = await _timePicker(context, end);
                          if (value == null || !context.mounted) return;
                          setSheetState(() {
                            end = value;
                            if (end <= start) start = end - 1;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                EventTypeTabs(
                  value: type,
                  onChanged: (value) => setSheetState(() => type = value),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      if (title.trim().isEmpty || end <= start) return;
                      if (!_canPlaceTemplate(
                        weekday: weekday,
                        startMinute: start,
                        endMinute: end,
                        excludingId: current?.id,
                      )) {
                        return;
                      }
                      setState(() {
                        _templates
                            .removeWhere((item) => item.id == current?.id);
                        _templates.add(
                          WeekTemplate(
                            id: current?.id ?? _uuid.v4(),
                            planId: _planId,
                            title: title.trim(),
                            weekday: weekday,
                            type: type,
                            startMinute: start,
                            endMinute: end,
                          ),
                        );
                      });
                      Navigator.pop(sheetContext);
                    },
                    child: const Text('Save event'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onTemplateActions(WeekTemplate template) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () {
                Navigator.pop(sheetContext);
                _editTemplate(template);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Copy to another time'),
              onTap: () {
                setState(() => _copySource = template);
                Navigator.pop(sheetContext);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () {
                setState(() =>
                    _templates.removeWhere((item) => item.id == template.id));
                Navigator.pop(sheetContext);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _editTemplate(WeekTemplate template) => _eventSheet(
        template.weekday,
        template.startMinute,
        template.endMinute,
        current: template,
      );

  void _moveTemplate(WeekTemplate template, int weekday, int startMinute) {
    final timeline = context.read<PlanController>().timeline!;
    final maxStart = (timeline.visibleEnd - template.duration)
        .clamp(timeline.visibleStart, timeline.visibleEnd - 1) as int;
    final adjustedStart =
        startMinute.clamp(timeline.visibleStart, maxStart) as int;
    if (!_canPlaceTemplate(
      weekday: weekday,
      startMinute: adjustedStart,
      endMinute: adjustedStart + template.duration,
      excludingId: template.id,
    )) {
      return;
    }
    setState(() {
      _templates.removeWhere((item) => item.id == template.id);
      _templates.add(
        WeekTemplate(
          id: template.id,
          planId: template.planId,
          title: template.title,
          weekday: weekday,
          type: template.type,
          startMinute: adjustedStart,
          endMinute: adjustedStart + template.duration,
        ),
      );
    });
  }

  void _markSavedAndExit() {
    if (!mounted) return;
    setState(() => _savedFingerprint = _draftFingerprint());
    Navigator.of(context).pop();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a plan title')),
      );
      return;
    }
    final plan = Plan(
      id: _planId,
      title: _title.text.trim(),
      startDate: _start,
      endDate: _end,
      repeatsWeekly: _repeats,
      createdAt: widget.plan?.createdAt ?? DateTime.now(),
    );
    final controller = context.read<PlanController>();
    try {
      await controller.savePlan(plan, _templates);
      _markSavedAndExit();
    } on TemplateConflictException catch (error) {
      if (mounted) await showTemplateConflictDialog(context, error);
    } on PlanConflictException catch (error) {
      if (!mounted) return;
      final overwrite = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Date range conflict'),
          content: Text(
              'This overlaps with “${error.conflicts.map((item) => item.title).join(', ')}”.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Overwrite all'),
            ),
          ],
        ),
      );
      if (overwrite == true) {
        await controller.overwriteConflictingPlans(plan, _templates);
        _markSavedAndExit();
      }
    }
  }
}

class _PlanDetails extends StatelessWidget {
  const _PlanDetails({
    required this.title,
    required this.start,
    required this.end,
    required this.repeats,
    required this.onStart,
    required this.onEnd,
    required this.onRepeat,
  });

  final TextEditingController title;
  final DateTime start;
  final DateTime end;
  final bool repeats;
  final VoidCallback onStart;
  final VoidCallback onEnd;
  final ValueChanged<bool> onRepeat;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
        child: Column(
          children: [
            TextField(
              controller: title,
              decoration:
                  const InputDecoration(labelText: 'Plan title (required)'),
            ),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: onStart,
                    child: Text('Start ${DateFormat('yy/M/d').format(start)}'),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: onEnd,
                    child: Text('End ${DateFormat('yy/M/d').format(end)}'),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Repeat weekly'),
              value: repeats,
              onChanged: onRepeat,
            ),
          ],
        ),
      );
}

class _TemplateWeekTimeline extends StatelessWidget {
  const _TemplateWeekTimeline({
    required this.timeline,
    required this.templates,
    required this.onCreate,
    required this.onEdit,
    required this.onActions,
    required this.onMove,
  });

  final TimelineModel timeline;
  final List<WeekTemplate> templates;
  final void Function(int weekday, int startMinute, int endMinute) onCreate;
  final ValueChanged<WeekTemplate> onEdit;
  final ValueChanged<WeekTemplate> onActions;
  final void Function(WeekTemplate template, int weekday, int startMinute)
      onMove;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(
            7,
            (index) {
              final weekday = index + 1;
              return SizedBox(
                width: 188,
                child: Column(
                  children: [
                    Text(
                      _weekday(weekday),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 500,
                      child: SingleChildScrollView(
                        child: _TemplateDayAxis(
                          weekday: weekday,
                          timeline: timeline,
                          templates: templates
                              .where((item) => item.weekday == weekday)
                              .toList(),
                          onCreate: onCreate,
                          onEdit: onEdit,
                          onActions: onActions,
                          onMove: onMove,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
}

class _TemplateDayAxis extends StatelessWidget {
  const _TemplateDayAxis({
    required this.weekday,
    required this.timeline,
    required this.templates,
    required this.onCreate,
    required this.onEdit,
    required this.onActions,
    required this.onMove,
  });

  final int weekday;
  final TimelineModel timeline;
  final List<WeekTemplate> templates;
  final void Function(int weekday, int startMinute, int endMinute) onCreate;
  final ValueChanged<WeekTemplate> onEdit;
  final ValueChanged<WeekTemplate> onActions;
  final void Function(WeekTemplate template, int weekday, int startMinute)
      onMove;

  static const _pixelsPerMinute = .46;

  @override
  Widget build(BuildContext context) {
    final start = timeline.visibleStart;
    final end = timeline.visibleEnd;
    final axisHeight = (end - start) * _pixelsPerMinute;
    final renderSegments = buildTimelineSegments<WeekTemplate>(
      timeline: timeline,
      events: templates
          .map(
            (item) => TimelineEventSpan(
              value: item,
              startMinute: item.startMinute,
              endMinute: item.endMinute,
            ),
          )
          .toList(),
    );

    int minuteFor(Offset globalOffset) {
      final box = context.findRenderObject() as RenderBox?;
      if (box == null) return start;
      final local = box.globalToLocal(globalOffset);
      return (start + local.dy / _pixelsPerMinute).round().clamp(start, end - 1)
          as int;
    }

    return DragTarget<WeekTemplate>(
      onAcceptWithDetails: (details) =>
          onMove(details.data, weekday, minuteFor(details.offset)),
      builder: (context, candidates, rejected) => SizedBox(
        height: axisHeight + 44,
        child: Stack(
          clipBehavior: Clip.none,
          children: _surfaces(renderSegments, start, end),
        ),
      ),
    );
  }

  List<Widget> _surfaces(
    List<TimelineRenderSegment<WeekTemplate>> segments,
    int axisStart,
    int axisEnd,
  ) {
    final surfaces = <Widget>[];
    for (final segment in segments) {
      if (segment.kind == TimelineRenderKind.event) {
        surfaces.add(_templateCard(segment.event!, axisStart, axisEnd));
        continue;
      }
      final isPrimary = segment.kind == TimelineRenderKind.primaryBlock;
      final isGap = segment.kind == TimelineRenderKind.gap;
      surfaces.add(
        _TemplateSurface(
          top: (segment.startMinute - axisStart) * _pixelsPerMinute,
          height: (segment.endMinute - segment.startMinute) * _pixelsPerMinute,
          label: isPrimary
              ? displayBlockName(segment.block!)
              : isGap
                  ? segment.gap!.label ?? ''
                  : '',
          subtitle:
              '${_formatMinute(segment.startMinute)}–${_formatMinute(segment.endMinute)}',
          color: isGap ? const Color(0xFFEEEAE5) : null,
          onTap: () => onCreate(
            weekday,
            segment.startMinute,
            segment.endMinute,
          ),
        ),
      );
    }
    return surfaces;
  }

  Widget _templateCard(WeekTemplate item, int axisStart, int axisEnd) {
    final start = item.startMinute.clamp(axisStart, axisEnd) as int;
    final end = item.endMinute.clamp(axisStart, axisEnd) as int;
    final actualHeight = (end - start) * _pixelsPerMinute;
    // Every real template event stays reachable even when it begins in a Gap
    // or spans only a short interval.  Its content switches to compact mode
    // instead of overflowing the measured card height.
    final height = actualHeight < 40 ? 40.0 : actualHeight - 4;
    _TemplateCard buildCard() => _TemplateCard(
          event: item,
          onEdit: () => onEdit(item),
          onActions: () => onActions(item),
        );
    return Positioned(
      left: 8,
      right: 8,
      top: (start - axisStart) * _pixelsPerMinute + 2,
      height: height,
      child: LongPressDraggable<WeekTemplate>(
        data: item,
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(width: 180, height: height, child: buildCard()),
        ),
        childWhenDragging: Opacity(opacity: .25, child: buildCard()),
        child: buildCard(),
      ),
    );
  }
}

class _TemplateSurface extends StatelessWidget {
  const _TemplateSurface({
    required this.top,
    required this.height,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final double top;
  final double height;
  final String label;
  final String subtitle;
  final Color? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Positioned(
        left: 8,
        right: 8,
        top: top + 2,
        height: height < 4 ? 2 : height - 4,
        child: Material(
          color: color ?? Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // A Gap/primary surface must not try to fit two text lines into
                // a short real-time interval. It stays as one centred time line
                // until the measured height is genuinely sufficient.
                if (constraints.maxHeight < 56) {
                  return Center(
                    child: Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF88817A),
                        fontSize: 10,
                      ),
                    ),
                  );
                }
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF88817A),
                          fontSize: 10,
                        ),
                      ),
                      if (label.isNotEmpty)
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF45413D),
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.event,
    required this.onEdit,
    required this.onActions,
  });

  final WeekTemplate event;
  final VoidCallback onEdit;
  final VoidCallback onActions;

  @override
  Widget build(BuildContext context) => Material(
        color: _typeColor(event.type),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onEdit,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 36;
              final showDetails = constraints.maxHeight >= 56;
              final showMenu = constraints.maxHeight >= 36;
              if (compact) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF45413D),
                        fontSize: 11,
                      ),
                    ),
                  ),
                );
              }
              return Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: showDetails ? 4 : 0,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: showDetails
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _templateTitle(event, 12),
                                Text(
                                  '${_formatMinute(event.startMinute)}–${_formatMinute(event.endMinute)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF77716B),
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            )
                          : _templateTitle(event, 11),
                    ),
                    if (showMenu)
                      SizedBox(
                        width: 26,
                        height: 26,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          iconSize: 17,
                          tooltip: 'More actions',
                          onPressed: onActions,
                          icon: const Icon(Icons.more_horiz),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      );
}

Widget _templateTitle(WeekTemplate event, double fontSize) => Text(
      event.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontWeight: FontWeight.w700,
        color: const Color(0xFF45413D),
        fontSize: fontSize,
      ),
    );

class _TimeButton extends StatelessWidget {
  const _TimeButton({
    required this.label,
    required this.minute,
    required this.onTap,
  });

  final String label;
  final int minute;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onTap,
        child: Text('$label ${_formatMinute(minute)}'),
      );
}

Future<int?> _timePicker(BuildContext context, int minute) =>
    showTimeWheelPicker(context, initialMinute: minute);

DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

String _formatMinute(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

String _weekday(int weekday) =>
    const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][weekday - 1];

Color _typeColor(PlanType type) => switch (type) {
      PlanType.task => const Color(0xFFDCE4EA),
      PlanType.buffer => const Color(0xFFEEEAE5),
      PlanType.fixed => const Color(0xFFE5DFE9),
    };
