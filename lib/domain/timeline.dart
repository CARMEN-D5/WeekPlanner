class TimelineBlock {
  const TimelineBlock({
    required this.id,
    required this.order,
    required this.name,
    required this.startMinute,
    required this.endMinute,
  });

  final String id;
  final int order;
  final String name;
  final int startMinute;
  final int endMinute;

  TimelineBlock copyWith({String? name, int? startMinute, int? endMinute}) =>
      TimelineBlock(
        id: id,
        order: order,
        name: name ?? this.name,
        startMinute: startMinute ?? this.startMinute,
        endMinute: endMinute ?? this.endMinute,
      );
}

class TimelineSegment {
  const TimelineSegment({
    required this.id,
    required this.blockId,
    required this.startMinute,
    required this.endMinute,
  });

  final String id;
  final String blockId;
  final int startMinute;
  final int endMinute;
}

class TimelineGap {
  const TimelineGap({
    required this.afterOrder,
    required this.startMinute,
    required this.endMinute,
    this.label,
  });

  final int afterOrder;
  final int startMinute;
  final int endMinute;
  final String? label;
}

class TimelineModel {
  const TimelineModel({
    required this.blocks,
    required this.segments,
    required this.gapLabels,
  });

  final List<TimelineBlock> blocks;
  final List<TimelineSegment> segments;
  final Map<int, String> gapLabels;

  List<TimelineSegment> segmentsFor(TimelineBlock block) =>
      segments.where((segment) => segment.blockId == block.id).toList()
        ..sort((a, b) => a.startMinute.compareTo(b.startMinute));

  List<TimelineGap> get gaps {
    final result = <TimelineGap>[];
    final sorted = List<TimelineBlock>.of(blocks)
      ..sort((a, b) => a.order.compareTo(b.order));
    for (var index = 0; index < sorted.length - 1; index++) {
      final previous = sorted[index];
      final next = sorted[index + 1];
      if (next.startMinute > previous.endMinute) {
        result.add(TimelineGap(
          afterOrder: previous.order,
          startMinute: previous.endMinute,
          endMinute: next.startMinute,
          label: gapLabels[previous.order],
        ));
      }
    }
    return result;
  }

  int get visibleStart =>
      blocks.map((block) => block.startMinute).reduce((a, b) => a < b ? a : b);
  int get visibleEnd =>
      blocks.map((block) => block.endMinute).reduce((a, b) => a > b ? a : b);
  TimelineBlock? blockForMinute(int minute) {
    for (final block in blocks) {
      if (minute >= block.startMinute && minute < block.endMinute) return block;
    }
    return null;
  }
}
