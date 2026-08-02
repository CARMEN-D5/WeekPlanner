import 'plan_item.dart';
import 'timeline.dart';

/// The visual kinds emitted by the shared daily/weekly template renderer.
enum TimelineRenderKind { primaryBlock, gap, event, empty }

/// A time-bounded value that can be rendered on a [TimelineModel].
class TimelineEventSpan<T> {
  const TimelineEventSpan({
    required this.value,
    required this.startMinute,
    required this.endMinute,
  });

  final T value;
  final int startMinute;
  final int endMinute;
}

/// A single continuous card on the calendar. Events retain their original
/// object so a card spanning blocks and gaps is still one event instance.
class TimelineRenderSegment<T> {
  const TimelineRenderSegment({
    required this.kind,
    required this.startMinute,
    required this.endMinute,
    this.event,
    this.block,
    this.gap,
  });

  final TimelineRenderKind kind;
  final int startMinute;
  final int endMinute;
  final T? event;
  final TimelineBlock? block;
  final TimelineGap? gap;

  int get duration => endMinute - startMinute;

  TimelineRenderSegment<T> copyWith(
          {int? endMinute, TimelineRenderKind? kind}) =>
      TimelineRenderSegment(
        kind: kind ?? this.kind,
        startMinute: startMinute,
        endMinute: endMinute ?? this.endMinute,
        event: event,
        block: block,
        gap: gap,
      );
}

/// Builds the one authoritative set of cards used by all timeline views.
///
/// A primary block is shown as one named card only when no event touches it.
/// Once touched, its free portions become unnamed empty cards. An empty portion
/// immediately followed by a gap is merged into the same white card, whereas a
/// gap after an event ending exactly at a block boundary stays grey.
List<TimelineRenderSegment<T>> buildTimelineSegments<T>({
  required TimelineModel timeline,
  required List<TimelineEventSpan<T>> events,
}) {
  final axisStart = timeline.visibleStart;
  final axisEnd = timeline.visibleEnd;
  final visibleEvents = events
      .where(
          (event) => event.endMinute > axisStart && event.startMinute < axisEnd)
      .map(
        (event) => TimelineEventSpan<T>(
          value: event.value,
          startMinute: event.startMinute.clamp(axisStart, axisEnd) as int,
          endMinute: event.endMinute.clamp(axisStart, axisEnd) as int,
        ),
      )
      .where((event) => event.endMinute > event.startMinute)
      .toList()
    ..sort((a, b) => a.startMinute.compareTo(b.startMinute));

  final touchedBlocks = <String>{
    for (final block in timeline.blocks)
      if (visibleEvents.any(
        (event) =>
            event.startMinute < block.endMinute &&
            event.endMinute > block.startMinute,
      ))
        block.id,
  };

  final boundaries = <int>{axisStart, axisEnd};
  for (final block in timeline.blocks) {
    boundaries.add(block.startMinute);
    boundaries.add(block.endMinute);
  }
  for (final gap in timeline.gaps) {
    boundaries.add(gap.startMinute);
    boundaries.add(gap.endMinute);
  }
  for (final event in visibleEvents) {
    boundaries.add(event.startMinute);
    boundaries.add(event.endMinute);
  }
  final points = boundaries.toList()..sort();
  final pieces = <TimelineRenderSegment<T>>[];

  for (var index = 0; index < points.length - 1; index++) {
    final start = points[index];
    final end = points[index + 1];
    if (end <= start) continue;

    TimelineEventSpan<T>? event;
    for (final candidate in visibleEvents) {
      if (candidate.startMinute <= start && candidate.endMinute >= end) {
        event = candidate;
        break;
      }
    }
    if (event != null) {
      pieces.add(
        TimelineRenderSegment(
          kind: TimelineRenderKind.event,
          startMinute: start,
          endMinute: end,
          event: event.value,
        ),
      );
      continue;
    }

    final block = _blockAt(timeline.blocks, start);
    if (block != null) {
      pieces.add(
        TimelineRenderSegment(
          kind: touchedBlocks.contains(block.id)
              ? TimelineRenderKind.empty
              : TimelineRenderKind.primaryBlock,
          startMinute: start,
          endMinute: end,
          block: block,
        ),
      );
      continue;
    }

    final gap = _gapAt(timeline.gaps, start);
    if (gap != null) {
      pieces.add(
        TimelineRenderSegment(
          kind: TimelineRenderKind.gap,
          startMinute: start,
          endMinute: end,
          gap: gap,
        ),
      );
    }
  }

  return _mergeAdjacent(pieces);
}

List<TimelineRenderSegment<T>> _mergeAdjacent<T>(
  List<TimelineRenderSegment<T>> pieces,
) {
  final merged = <TimelineRenderSegment<T>>[];
  for (final piece in pieces) {
    if (merged.isEmpty) {
      merged.add(piece);
      continue;
    }
    final previous = merged.last;
    if (previous.endMinute != piece.startMinute) {
      merged.add(piece);
      continue;
    }

    final sameEvent = previous.kind == TimelineRenderKind.event &&
        piece.kind == TimelineRenderKind.event &&
        identical(previous.event, piece.event);
    final samePrimary = previous.kind == TimelineRenderKind.primaryBlock &&
        piece.kind == TimelineRenderKind.primaryBlock &&
        previous.block?.id == piece.block?.id;
    final sameEmpty = previous.kind == TimelineRenderKind.empty &&
        piece.kind == TimelineRenderKind.empty;
    final emptyThenGap = previous.kind == TimelineRenderKind.empty &&
        piece.kind == TimelineRenderKind.gap;
    final sameGap = previous.kind == TimelineRenderKind.gap &&
        piece.kind == TimelineRenderKind.gap &&
        previous.gap?.afterOrder == piece.gap?.afterOrder;

    if (sameEvent || samePrimary || sameEmpty || sameGap) {
      merged[merged.length - 1] = previous.copyWith(endMinute: piece.endMinute);
    } else if (emptyThenGap) {
      // Keep the white empty style and deliberately omit the gap label.
      merged[merged.length - 1] = previous.copyWith(endMinute: piece.endMinute);
    } else {
      merged.add(piece);
    }
  }
  return merged;
}

TimelineBlock? _blockAt(List<TimelineBlock> blocks, int minute) {
  for (final block in blocks) {
    if (minute >= block.startMinute && minute < block.endMinute) return block;
  }
  return null;
}

TimelineGap? _gapAt(List<TimelineGap> gaps, int minute) {
  for (final gap in gaps) {
    if (minute >= gap.startMinute && minute < gap.endMinute) return gap;
  }
  return null;
}

bool eventsOverlap({
  required int startMinute,
  required int endMinute,
  required int otherStartMinute,
  required int otherEndMinute,
}) =>
    startMinute < otherEndMinute && endMinute > otherStartMinute;

String normalizeEventTitle(String title) =>
    title.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

class EventConflictException implements Exception {
  const EventConflictException(this.conflicts);

  final List<PlanItem> conflicts;
}

class TemplateConflictException implements Exception {
  const TemplateConflictException(this.conflicts);

  final List<WeekTemplate> conflicts;
}
