import '../lib/domain/timeline.dart';
import '../lib/domain/timeline_render.dart';

void main() {
  const timeline = TimelineModel(
    blocks: [
      TimelineBlock(
        id: 'morning',
        order: 0,
        name: '早上',
        startMinute: 540,
        endMinute: 690,
      ),
      TimelineBlock(
        id: 'afternoon',
        order: 1,
        name: '下午',
        startMinute: 780,
        endMinute: 990,
      ),
      TimelineBlock(
        id: 'evening',
        order: 2,
        name: '晚上',
        startMinute: 1080,
        endMinute: 1380,
      ),
    ],
    segments: [],
    gapLabels: {},
  );

  final segments = buildTimelineSegments<String>(
    timeline: timeline,
    events: const [
      TimelineEventSpan(value: 'gym', startMinute: 660, endMinute: 840),
    ],
  );

  if (segments.length != 4 ||
      segments[1].kind != TimelineRenderKind.event ||
      segments[1].startMinute != 660 ||
      segments[1].endMinute != 840 ||
      segments[2].kind != TimelineRenderKind.empty ||
      segments[2].endMinute != 1080 ||
      eventsOverlap(
        startMinute: 600,
        endMinute: 660,
        otherStartMinute: 660,
        otherEndMinute: 720,
      )) {
    throw StateError('Timeline rendering rules failed');
  }
  print('timeline smoke check passed');
}
