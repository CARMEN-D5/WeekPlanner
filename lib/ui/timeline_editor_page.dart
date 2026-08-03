import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/timeline.dart';
import '../state/plan_controller.dart';
import 'plan_editor_page.dart';
import 'time_wheel_picker.dart';
import 'timeline_labels.dart';

class TimelineEditorPage extends StatelessWidget {
  const TimelineEditorPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PlanController>();
    final timeline = controller.timeline;
    if (timeline == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Timeline settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Customize the three primary blocks and their start/end times. Gaps are generated automatically.',
          ),
          const SizedBox(height: 12),
          for (final block in timeline.blocks) ...[
            Card(
              child: ListTile(
                leading: const Icon(Icons.view_agenda_outlined),
                title: Text(displayBlockName(block)),
                subtitle: Text(
                  '${_clock(block.startMinute)}–${_clock(block.endMinute)} · Long-press a child segment to split or merge',
                ),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => _editBlock(context, timeline, block),
              ),
            ),
            ...timeline
                .segmentsFor(block)
                .map(
                  (segment) => Padding(
                    padding: const EdgeInsets.only(left: 24),
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.drag_handle, size: 18),
                      title: Text(
                        '${_clock(segment.startMinute)}–${_clock(segment.endMinute)}',
                      ),
                      subtitle: const Text(
                        'Long-press: split / merge with the next segment',
                      ),
                      onLongPress: () => _segmentActions(context, segment),
                    ),
                  ),
                ),
            for (final gap in timeline.gaps.where(
              (gap) => gap.afterOrder == block.order,
            ))
              Card(
                color: const Color(0xFFE7E7E5),
                child: ListTile(
                  leading: const Icon(Icons.space_bar_outlined),
                  title: Text(
                    (gap.label?.isNotEmpty ?? false) ? gap.label! : 'Gap',
                  ),
                  subtitle: Text(
                    '${_clock(gap.startMinute)}–${_clock(gap.endMinute)}',
                  ),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _editGap(context, timeline, gap),
                ),
              ),
          ],
        ],
      ),
    );
  }

  void _editBlock(
    BuildContext context,
    TimelineModel timeline,
    TimelineBlock block,
  ) {
    var name = displayBlockName(block);
    final controller = context.read<PlanController>();
    var start = block.startMinute;
    var end = block.endMinute;
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
              children: [
                TextFormField(
                  initialValue: name,
                  decoration: const InputDecoration(labelText: 'Name'),
                  onChanged: (value) => name = value,
                ),
                Row(
                  children: [
                    Expanded(
                      child: _TimeButton(
                        label: 'Start',
                        value: start,
                        onTap: () async {
                          final time = await _pickTime(context, start);
                          if (time != null && context.mounted) {
                            setSheetState(() => start = time);
                          }
                        },
                      ),
                    ),
                    Expanded(
                      child: _TimeButton(
                        label: 'End',
                        value: end,
                        onTap: () async {
                          final time = await _pickTime(context, end);
                          if (time != null && context.mounted) {
                            setSheetState(() => end = time);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      if (name.trim().isEmpty || end <= start) return;
                      final blocks = timeline.blocks
                          .map(
                            (item) => item.id == block.id
                                ? item.copyWith(
                                    name: name.trim(),
                                    startMinute: start,
                                    endMinute: end,
                                  )
                                : item,
                          )
                          .toList();
                      if (!_valid(blocks)) {
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'The three blocks cannot overlap, and end must be after start.',
                            ),
                          ),
                        );
                        return;
                      }
                      final segments = [
                        ...timeline.segments.where(
                          (item) => item.blockId != block.id,
                        ),
                        TimelineSegment(
                          id: '${block.id}_${DateTime.now().millisecondsSinceEpoch}',
                          blockId: block.id,
                          startMinute: start,
                          endMinute: end,
                        ),
                      ];
                      final proposed = TimelineModel(
                        blocks: blocks,
                        segments: segments,
                        gapLabels: timeline.gapLabels,
                      );
                      final saved = await _saveTimelineChange(
                        sheetContext,
                        controller,
                        proposed,
                      );
                      if (saved && sheetContext.mounted) {
                        Navigator.pop(sheetContext);
                      }
                    },
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _editGap(BuildContext context, TimelineModel timeline, TimelineGap gap) {
    var label = gap.label ?? '';
    final controller = context.read<PlanController>();
    var start = gap.startMinute;
    var end = gap.endMinute;
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
              children: [
                TextFormField(
                  initialValue: label,
                  decoration: const InputDecoration(
                    labelText: 'Gap name (optional)',
                  ),
                  onChanged: (value) => label = value,
                ),
                Row(
                  children: [
                    Expanded(
                      child: _TimeButton(
                        label: 'Start',
                        value: start,
                        onTap: () async {
                          final time = await _pickTime(context, start);
                          if (time != null && context.mounted) {
                            setSheetState(() => start = time);
                          }
                        },
                      ),
                    ),
                    Expanded(
                      child: _TimeButton(
                        label: 'End',
                        value: end,
                        onTap: () async {
                          final time = await _pickTime(context, end);
                          if (time != null && context.mounted) {
                            setSheetState(() => end = time);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      if (end <= start) return;
                      final before = timeline.blocks.firstWhere(
                        (block) => block.order == gap.afterOrder,
                      );
                      final after = timeline.blocks.firstWhere(
                        (block) => block.order == gap.afterOrder + 1,
                      );
                      final blocks = timeline.blocks.map((block) {
                        if (block.id == before.id) {
                          return block.copyWith(endMinute: start);
                        }
                        if (block.id == after.id) {
                          return block.copyWith(startMinute: end);
                        }
                        return block;
                      }).toList();
                      if (!_valid(blocks)) {
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'The Gap conflicts with an adjacent block.',
                            ),
                          ),
                        );
                        return;
                      }
                      final segments =
                          timeline.segments
                              .where(
                                (segment) =>
                                    segment.blockId != before.id &&
                                    segment.blockId != after.id,
                              )
                              .toList()
                            ..addAll([
                              TimelineSegment(
                                id: '${before.id}_${DateTime.now().microsecondsSinceEpoch}',
                                blockId: before.id,
                                startMinute: before.startMinute,
                                endMinute: start,
                              ),
                              TimelineSegment(
                                id: '${after.id}_${DateTime.now().microsecondsSinceEpoch}',
                                blockId: after.id,
                                startMinute: end,
                                endMinute: after.endMinute,
                              ),
                            ]);
                      final labels = Map<int, String>.of(timeline.gapLabels)
                        ..[gap.afterOrder] = label.trim();
                      final proposed = TimelineModel(
                        blocks: blocks,
                        segments: segments,
                        gapLabels: labels,
                      );
                      final saved = await _saveTimelineChange(
                        sheetContext,
                        controller,
                        proposed,
                      );
                      if (saved && sheetContext.mounted) {
                        Navigator.pop(sheetContext);
                      }
                    },
                    child: const Text('Save Gap'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _segmentActions(BuildContext context, TimelineSegment segment) {
    final controller = context.read<PlanController>();
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.call_split_outlined),
              title: const Text('Split'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final at = await _pickTime(
                  context,
                  (segment.startMinute + segment.endMinute) ~/ 2,
                );
                if (at != null &&
                    at > segment.startMinute &&
                    at < segment.endMinute &&
                    context.mounted) {
                  await controller.splitTimelineSegment(segment.id, at);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.merge_type_outlined),
              title: const Text('Merge with next segment'),
              onTap: () async {
                await controller.mergeTimelineSegment(segment.id);
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              },
            ),
          ],
        ),
      ),
    );
  }

  bool _valid(List<TimelineBlock> blocks) {
    final sorted = List<TimelineBlock>.of(blocks)
      ..sort((a, b) => a.order.compareTo(b.order));
    for (var index = 0; index < sorted.length; index++) {
      if (sorted[index].endMinute <= sorted[index].startMinute) return false;
      if (index > 0 &&
          sorted[index].startMinute < sorted[index - 1].endMinute) {
        return false;
      }
    }
    return true;
  }

  Future<bool> _saveTimelineChange(
    BuildContext context,
    PlanController controller,
    TimelineModel proposed,
  ) async {
    if (controller.plans.isEmpty) {
      await controller.saveTimeline(proposed);
      return true;
    }
    final choice = await showDialog<_TimelineSaveChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Apply timeline changes to existing plans?'),
        content: const Text(
          'Your primary time blocks have changed. Would you like to apply the new timeline ranges to existing plans?\n\nFinished plans are always left unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _TimelineSaveChoice.newPlansOnly),
            child: const Text('Only future plans'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              _TimelineSaveChoice.activeAndUpcoming,
            ),
            child: const Text('Apply to existing plans'),
          ),
        ],
      ),
    );
    if (choice == null) return false;
    if (choice == _TimelineSaveChoice.newPlansOnly) {
      await controller.saveTimeline(proposed);
      return true;
    }

    final conflicts = await controller.timelineConflicts(proposed);
    if (!context.mounted) return false;
    if (conflicts.isNotEmpty) {
      final review = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Some events fall outside the new timeline range.'),
          content: SingleChildScrollView(
            child: Text(
              '${conflicts.length} events require attention:\n\n'
              '${conflicts.take(8).map((conflict) => '${_weekday(conflict.template.weekday)} · ${conflict.template.title} · ${_clock(conflict.template.startMinute)}–${_clock(conflict.template.endMinute)}').join('\n')}'
              '${conflicts.length > 8 ? '\n…and ${conflicts.length - 8} more' : ''}\n\n'
              'Please update these events before applying the new timeline.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel changes'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Review conflicts'),
            ),
          ],
        ),
      );
      if (review == true && context.mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PlanEditorPage(plan: conflicts.first.plan),
          ),
        );
      }
      return false;
    }
    await controller.saveTimelineAndApplyToExisting(proposed);
    return true;
  }
}

enum _TimelineSaveChoice { newPlansOnly, activeAndUpcoming }

String _weekday(int value) => const [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
][value - 1];

class _TimeButton extends StatelessWidget {
  const _TimeButton({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final int value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) =>
      TextButton(onPressed: onTap, child: Text('$label ${_clock(value)}'));
}

Future<int?> _pickTime(BuildContext context, int value) =>
    showTimeWheelPicker(context, initialMinute: value);

String _clock(int value) =>
    '${(value ~/ 60).toString().padLeft(2, '0')}:${(value % 60).toString().padLeft(2, '0')}';
