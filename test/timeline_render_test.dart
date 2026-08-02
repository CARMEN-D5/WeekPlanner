import 'package:flutter_test/flutter_test.dart';

import 'package:cadence/domain/timeline.dart';
import 'package:cadence/domain/timeline_render.dart';

void main() {
  const morning = TimelineBlock(
    id: 'morning',
    order: 0,
    name: 'Morning',
    startMinute: 9 * 60,
    endMinute: 11 * 60 + 30,
  );
  const afternoon = TimelineBlock(
    id: 'afternoon',
    order: 1,
    name: 'Afternoon',
    startMinute: 13 * 60,
    endMinute: 16 * 60 + 30,
  );
  const evening = TimelineBlock(
    id: 'evening',
    order: 2,
    name: 'Evening',
    startMinute: 18 * 60,
    endMinute: 23 * 60,
  );
  const timeline = TimelineModel(
    blocks: [morning, afternoon, evening],
    segments: [],
    gapLabels: {0: 'Lunch', 1: 'Break'},
  );

  group('TimelineModel', () {
    test('calculates labelled gaps between ordered primary blocks', () {
      // Arrange
      const model = timeline;

      // Act
      final gaps = model.gaps;

      // Assert
      expect(gaps, hasLength(2));
      expect(gaps[0].afterOrder, 0);
      expect(gaps[0].startMinute, 11 * 60 + 30);
      expect(gaps[0].endMinute, 13 * 60);
      expect(gaps[0].label, 'Lunch');
      expect(gaps[1].afterOrder, 1);
      expect(gaps[1].startMinute, 16 * 60 + 30);
      expect(gaps[1].endMinute, 18 * 60);
      expect(gaps[1].label, 'Break');
    });

    test('does not create a gap for adjacent or overlapping blocks', () {
      // Arrange
      const model = TimelineModel(
        blocks: [
          TimelineBlock(
            id: 'first',
            order: 0,
            name: 'First',
            startMinute: 540,
            endMinute: 660,
          ),
          TimelineBlock(
            id: 'adjacent',
            order: 1,
            name: 'Adjacent',
            startMinute: 660,
            endMinute: 780,
          ),
          TimelineBlock(
            id: 'overlapping',
            order: 2,
            name: 'Overlapping',
            startMinute: 750,
            endMinute: 900,
          ),
        ],
        segments: [],
        gapLabels: {},
      );

      // Act
      final gaps = model.gaps;

      // Assert
      expect(gaps, isEmpty);
    });
  });

  group('buildTimelineSegments', () {
    test('keeps an event crossing blocks and gaps as one event segment', () {
      // Arrange
      const events = [
        TimelineEventSpan(
          value: 'Gym',
          startMinute: 11 * 60,
          endMinute: 14 * 60,
        ),
      ];

      // Act
      final segments = buildTimelineSegments<String>(
        timeline: timeline,
        events: events,
      );

      // Assert
      final eventSegments = segments
          .where((segment) => segment.kind == TimelineRenderKind.event)
          .toList();
      expect(eventSegments, hasLength(1));
      expect(eventSegments.single.event, 'Gym');
      expect(eventSegments.single.startMinute, 11 * 60);
      expect(eventSegments.single.endMinute, 14 * 60);
      expect(segments.map((segment) => segment.kind), [
        TimelineRenderKind.empty,
        TimelineRenderKind.event,
        TimelineRenderKind.empty,
        TimelineRenderKind.primaryBlock,
      ]);
      expect(segments[2].startMinute, 14 * 60);
      expect(segments[2].endMinute, 18 * 60);
    });

    test('renders an untouched labelled gap as a separate gap segment', () {
      // Arrange
      const events = <TimelineEventSpan<String>>[];

      // Act
      final segments = buildTimelineSegments<String>(
        timeline: timeline,
        events: events,
      );

      // Assert
      final gaps = segments
          .where((segment) => segment.kind == TimelineRenderKind.gap)
          .toList();
      expect(gaps, hasLength(2));
      expect(gaps[0].startMinute, 11 * 60 + 30);
      expect(gaps[0].endMinute, 13 * 60);
      expect(gaps[0].gap?.label, 'Lunch');
      expect(gaps[1].startMinute, 16 * 60 + 30);
      expect(gaps[1].endMinute, 18 * 60);
      expect(gaps[1].gap?.label, 'Break');
    });

    test('keeps a gap separate when an event ends at a block boundary', () {
      // Arrange
      const events = [
        TimelineEventSpan(
          value: 'Study',
          startMinute: 10 * 60,
          endMinute: 11 * 60 + 30,
        ),
      ];

      // Act
      final segments = buildTimelineSegments<String>(
        timeline: timeline,
        events: events,
      );

      // Assert
      expect(segments[0].kind, TimelineRenderKind.empty);
      expect(segments[1].kind, TimelineRenderKind.event);
      expect(segments[2].kind, TimelineRenderKind.gap);
      expect(segments[2].startMinute, 11 * 60 + 30);
      expect(segments[2].endMinute, 13 * 60);
    });
  });

  group('event conflict rules', () {
    test('allows adjacent events that only share a boundary', () {
      // Arrange
      const firstStart = 10 * 60;
      const firstEnd = 11 * 60;
      const secondStart = 11 * 60;
      const secondEnd = 12 * 60;

      // Act
      final overlaps = eventsOverlap(
        startMinute: firstStart,
        endMinute: firstEnd,
        otherStartMinute: secondStart,
        otherEndMinute: secondEnd,
      );

      // Assert
      expect(overlaps, isFalse);
    });

    test('rejects events whose time ranges overlap by one minute', () {
      // Arrange
      const firstStart = 10 * 60;
      const firstEnd = 11 * 60 + 1;
      const secondStart = 11 * 60;
      const secondEnd = 12 * 60;

      // Act
      final overlaps = eventsOverlap(
        startMinute: firstStart,
        endMinute: firstEnd,
        otherStartMinute: secondStart,
        otherEndMinute: secondEnd,
      );

      // Assert
      expect(overlaps, isTrue);
    });
  });

  group('normalizeEventTitle', () {
    test('trims, collapses whitespace, and ignores letter case', () {
      // Arrange
      const title = '  Weekly\n   Review  ';

      // Act
      final normalized = normalizeEventTitle(title);

      // Assert
      expect(normalized, 'weekly review');
    });
  });
}
