import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/plan_item.dart';
import '../domain/timeline.dart';
import '../domain/timeline_render.dart';
import '../state/plan_controller.dart';
import 'event_conflict_dialog.dart';
import 'timeline_labels.dart';

/// One independent vertical axis for a calendar day.
///
/// Its cards come from [buildTimelineSegments], the same algorithm used by the
/// week and plan-template views. This prevents a primary block, an empty card,
/// and a gap from being calculated differently on different screens.
class TimelineDayColumn extends StatelessWidget {
  const TimelineDayColumn({
    super.key,
    required this.date,
    required this.timeline,
    required this.events,
    required this.onCreate,
    required this.onEdit,
    required this.onActions,
    this.showNow = false,
    this.pixelsPerMinute = .55,
  });

  final DateTime date;
  final TimelineModel timeline;
  final List<PlanItem> events;
  final void Function(int startMinute, int endMinute) onCreate;
  final ValueChanged<PlanItem> onEdit;
  final ValueChanged<PlanItem> onActions;
  final bool showNow;
  final double pixelsPerMinute;

  @override
  Widget build(BuildContext context) {
    final start = timeline.visibleStart;
    final end = timeline.visibleEnd;
    final totalMinutes = end - start;
    if (totalMinutes <= 0 ||
        !pixelsPerMinute.isFinite ||
        pixelsPerMinute <= 0) {
      // Invalid axis data must never leave behind a tappable sliver.
      return const SizedBox.shrink();
    }
    final segments = buildTimelineSegments<PlanItem>(
      timeline: timeline,
      events: events
          .map(
            (item) => TimelineEventSpan(
              value: item,
              startMinute: item.startMinute,
              endMinute: item.endMinute,
            ),
          )
          .toList(),
    );
    final axisHeight = totalMinutes * pixelsPerMinute;
    if (!axisHeight.isFinite || axisHeight <= 0) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth ||
            !constraints.maxWidth.isFinite ||
            constraints.maxWidth <= 1) {
          // A ScrollView can briefly provide no usable width on its first
          // frame. Waiting here is safer than building a vertical, clickable
          // remnant with a collapsed width.
          return const SizedBox.shrink();
        }
        assert(() {
          debugPrint(
            'DayTimeline layout: date=${date.toIso8601String()} '
            'width=${constraints.maxWidth} height=$axisHeight '
            'ppm=$pixelsPerMinute segments=${segments.length}',
          );
          for (final segment in segments) {
            debugPrint(
              '  ${segment.kind} ${segment.startMinute}-${segment.endMinute}',
            );
          }
          return true;
        }());
        return DragTarget<PlanItem>(
          onAcceptWithDetails: (details) {
            _moveItem(context, details.data, details.offset, start, end);
          },
          builder: (context, candidates, rejected) => SizedBox(
            width: constraints.maxWidth,
            // A fixed minute-based height keeps the vertical scale independent
            // from first-frame viewport height.
            height: axisHeight + 44,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ...segments.map((segment) => _segmentCard(segment, start, end)),
                if (showNow) _nowLine(start, end),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _moveItem(
    BuildContext context,
    PlanItem item,
    Offset globalOffset,
    int axisStart,
    int axisEnd,
  ) async {
    if (!pixelsPerMinute.isFinite ||
        pixelsPerMinute <= 0 ||
        axisEnd <= axisStart) {
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(globalOffset);
    final latestStart = (axisEnd - item.duration).clamp(axisStart, axisEnd - 1);
    final minute =
        (axisStart + local.dy / pixelsPerMinute).round().clamp(
              axisStart,
              latestStart,
            )
            as int;
    try {
      await context.read<PlanController>().moveItem(item, date, minute);
    } on EventConflictException catch (error) {
      if (context.mounted) await showEventConflictDialog(context, error);
    }
  }

  Widget _segmentCard(
    TimelineRenderSegment<PlanItem> segment,
    int axisStart,
    int axisEnd,
  ) {
    final top = (segment.startMinute - axisStart) * pixelsPerMinute;
    final realHeight =
        (segment.endMinute - segment.startMinute) * pixelsPerMinute;
    if (segment.kind == TimelineRenderKind.event) {
      return _eventCard(
        segment.event!,
        segment.startMinute,
        segment.endMinute,
        axisStart,
        realHeight,
      );
    }

    final isGap = segment.kind == TimelineRenderKind.gap;
    final isPrimary = segment.kind == TimelineRenderKind.primaryBlock;
    return _AxisSegmentCard(
      top: top,
      height: realHeight,
      title: isPrimary
          ? displayBlockName(segment.block!)
          : isGap
          ? segment.gap!.label ?? ''
          : '',
      subtitle: '${_clock(segment.startMinute)}–${_clock(segment.endMinute)}',
      color: isGap ? const Color(0xFFEEEAE5) : null,
      onTap: () => onCreate(segment.startMinute, segment.endMinute),
    );
  }

  Widget _eventCard(
    PlanItem item,
    int startMinute,
    int endMinute,
    int axisStart,
    double realHeight,
  ) {
    // Keep tiny real-world intervals operable without letting their child
    // content overflow.  The card body still switches to compact content
    // based on this visual height.
    final eventHeight = realHeight < 40 ? 40.0 : realHeight - 4;
    final color = switch (item.type) {
      PlanType.task => const Color(0xFFDCE4EA),
      PlanType.buffer => const Color(0xFFEEEAE5),
      PlanType.fixed => const Color(0xFFE5DFE9),
    };
    final complete = item.status == PlanStatus.completed;
    _EventCardBody buildBody() => _EventCardBody(
      item: item,
      color: color,
      complete: complete,
      onTap: () => onEdit(item),
      onActions: () => onActions(item),
    );

    return Positioned(
      left: 8,
      right: 8,
      top: (startMinute - axisStart) * pixelsPerMinute + 2,
      height: eventHeight,
      child: LongPressDraggable<PlanItem>(
        data: item,
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(width: 180, height: eventHeight, child: buildBody()),
        ),
        childWhenDragging: Opacity(opacity: .25, child: buildBody()),
        child: buildBody(),
      ),
    );
  }

  Widget _nowLine(int start, int end) {
    final now = TimeOfDay.now().hour * 60 + TimeOfDay.now().minute;
    if (now < start || now > end) return const SizedBox();
    return Positioned(
      left: 0,
      right: 0,
      top: (now - start) * pixelsPerMinute,
      child: const Row(
        children: [
          Icon(Icons.circle, color: Color(0xFFC9A8A4), size: 9),
          SizedBox(width: 3),
          Expanded(child: Divider(color: Color(0xFFC9A8A4), thickness: 1.4)),
        ],
      ),
    );
  }
}

class _AxisSegmentCard extends StatelessWidget {
  const _AxisSegmentCard({
    required this.top,
    required this.height,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final double top;
  final double height;
  final String title;
  final String subtitle;
  final Color? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
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
              // Time-axis surfaces keep one centred line until there is room
              // for two lines; otherwise even a few pixels of rounding can
              // produce a RenderFlex overflow.
              if (constraints.maxHeight < 56) {
                return Center(
                  child: Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF88817A),
                    ),
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
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
                        fontSize: 11,
                        color: Color(0xFF88817A),
                      ),
                    ),
                    if (title.isNotEmpty)
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF45413D),
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
}

class _EventCardBody extends StatelessWidget {
  const _EventCardBody({
    required this.item,
    required this.color,
    required this.complete,
    required this.onTap,
    required this.onActions,
  });

  final PlanItem item;
  final Color color;
  final bool complete;
  final VoidCallback onTap;
  final VoidCallback onActions;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<PlanController>();
    final canChangeCompletion = controller.canToggleCompletion(item);
    return Material(
      color: complete ? const Color(0xFFDEE5DA) : color,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.maxHeight;
            final compact = height < 36;
            final showDetails = height >= 56;
            final showControls = height >= 36;
            final padding = showDetails ? 10.0 : 6.0;
            if (compact) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      decoration: complete ? TextDecoration.lineThrough : null,
                      color: const Color(0xFF45413D),
                    ),
                  ),
                ),
              );
            }
            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: padding,
                vertical: showDetails ? 4 : 0,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (showControls && item.type != PlanType.buffer)
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: canChangeCompletion
                            ? null
                            : () => ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'This event is outside the 7-day completion window.',
                                  ),
                                ),
                              ),
                        child: Checkbox(
                          value: complete,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          onChanged: canChangeCompletion
                              ? (_) async {
                                  try {
                                    if (complete) {
                                      await controller.undoComplete(item);
                                    } else {
                                      await controller.complete(item);
                                    }
                                  } catch (_) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Save failed. Please try again.',
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                }
                              : null,
                        ),
                      ),
                    ),
                  if (showControls && item.type != PlanType.buffer)
                    const SizedBox(width: 3),
                  Expanded(
                    child: showDetails
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _eventTitle(item, complete, 13),
                              Text(
                                '${_clock(item.startMinute)}–${_clock(item.endMinute)} · ${_typeLabel(item.type)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFF88817A),
                                ),
                              ),
                            ],
                          )
                        : _eventTitle(item, complete, 11),
                  ),
                  if (showControls)
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        tooltip: 'More actions',
                        iconSize: 18,
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
}

Widget _eventTitle(PlanItem item, bool complete, double fontSize) => Text(
  item.title,
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  style: TextStyle(
    fontSize: fontSize,
    fontWeight: FontWeight.w700,
    decoration: complete ? TextDecoration.lineThrough : null,
    color: const Color(0xFF45413D),
  ),
);

String _clock(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

String _typeLabel(PlanType type) => switch (type) {
  PlanType.task => 'Task',
  PlanType.buffer => 'Buffer',
  PlanType.fixed => 'Fixed',
};
