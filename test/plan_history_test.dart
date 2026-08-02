import 'package:flutter_test/flutter_test.dart';

import 'package:cadence/domain/plan_history.dart';
import 'package:cadence/domain/plan_item.dart';

void main() {
  final plan = Plan(
    id: 'plan-1',
    title: 'August plan',
    startDate: DateTime(2026, 8, 3),
    endDate: DateTime(2026, 8, 9),
    repeatsWeekly: true,
    createdAt: DateTime(2026, 8, 1),
    statisticsFinalizedAt: DateTime(2026, 8, 16),
  );

  PlanItem item({
    required String id,
    required String title,
    required PlanType type,
    required PlanStatus status,
    String? compensatedById,
    DateTime? date,
  }) =>
      PlanItem(
        id: id,
        title: title,
        date: date ?? DateTime(2026, 8, 3),
        type: type,
        status: status,
        startMinute: 9 * 60,
        endMinute: 10 * 60,
        planId: plan.id,
        compensatedById: compensatedById,
      );

  group('PlanHistorySummary counts', () {
    test('includes tasks and fixed arrangements but excludes buffers', () {
      // Arrange
      final items = [
        item(
          id: 'task',
          title: 'Write report',
          type: PlanType.task,
          status: PlanStatus.completed,
        ),
        item(
          id: 'fixed',
          title: 'Team meeting',
          type: PlanType.fixed,
          status: PlanStatus.pending,
        ),
        item(
          id: 'buffer',
          title: 'Travel buffer',
          type: PlanType.buffer,
          status: PlanStatus.completed,
        ),
      ];

      // Act
      final summary = PlanHistorySummary(plan: plan, items: items);
      final taskCount =
          summary.items.where((value) => value.type == PlanType.task).length;
      final fixedCount =
          summary.items.where((value) => value.type == PlanType.fixed).length;

      // Assert
      expect(summary.scheduledCount, 2);
      expect(summary.completedCount, 1);
      expect(summary.incompleteCount, 1);
      expect(summary.completionPercent, 50);
      expect(taskCount, 1);
      expect(fixedCount, 1);
      expect(summary.items, isNot(contains(items.last)));
    });

    test('separates normal completions from compensated completions', () {
      // Arrange
      final items = [
        item(
          id: 'normal',
          title: 'Exercise',
          type: PlanType.task,
          status: PlanStatus.completed,
        ),
        item(
          id: 'compensated',
          title: 'Read',
          type: PlanType.task,
          status: PlanStatus.completed,
          compensatedById: 'extra-1',
        ),
        item(
          id: 'pending',
          title: 'Plan tomorrow',
          type: PlanType.task,
          status: PlanStatus.pending,
        ),
      ];

      // Act
      final summary = PlanHistorySummary(plan: plan, items: items);

      // Assert
      expect(summary.completedCount, 2);
      expect(summary.compensatedCount, 1);
      expect(summary.normalCompletedCount, 1);
      expect(summary.incompleteCount, 1);
    });
  });

  group('PlanHistorySummary unfinished groups', () {
    test('aggregates unfinished items with equivalent normalized titles', () {
      // Arrange
      final items = [
        item(
          id: 'first',
          title: '  Weekly Review ',
          type: PlanType.task,
          status: PlanStatus.pending,
        ),
        item(
          id: 'second',
          title: 'weekly   review',
          type: PlanType.task,
          status: PlanStatus.cancelled,
          date: DateTime(2026, 8, 4),
        ),
        item(
          id: 'completed',
          title: 'WEEKLY REVIEW',
          type: PlanType.task,
          status: PlanStatus.completed,
        ),
      ];

      // Act
      final summary = PlanHistorySummary(plan: plan, items: items);

      // Assert
      expect(summary.unfinishedGroups, hasLength(1));
      expect(summary.unfinishedGroups.single.normalizedTitle, 'weekly review');
      expect(summary.unfinishedGroups.single.displayTitle, 'Weekly Review');
      expect(summary.unfinishedGroups.single.items, hasLength(2));
      expect(
        summary.unfinishedGroups.single.items.map((value) => value.id),
        containsAll(['first', 'second']),
      );
    });
  });
}
