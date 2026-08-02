import 'package:flutter_test/flutter_test.dart';

import 'package:cadence/domain/plan_item.dart';

void main() {
  group('Plan.statusAt', () {
    final plan = Plan(
      id: 'plan-1',
      title: 'August plan',
      startDate: DateTime(2026, 8, 3),
      endDate: DateTime(2026, 8, 9),
      repeatsWeekly: true,
      createdAt: DateTime(2026, 8, 1),
    );

    test('returns upcoming before the plan start date', () {
      // Arrange
      final date = DateTime(2026, 8, 2, 23, 59);

      // Act
      final status = plan.statusAt(date);

      // Assert
      expect(status, PlanLifecycleStatus.upcoming);
    });

    test('returns active on both inclusive date boundaries', () {
      // Arrange
      final dates = [
        DateTime(2026, 8, 3),
        DateTime(2026, 8, 9, 23, 59),
      ];

      // Act
      final statuses = dates.map(plan.statusAt).toList();

      // Assert
      expect(statuses, everyElement(PlanLifecycleStatus.active));
    });

    test('returns finished after the plan end date', () {
      // Arrange
      final date = DateTime(2026, 8, 10);

      // Act
      final status = plan.statusAt(date);

      // Assert
      expect(status, PlanLifecycleStatus.finished);
      expect(plan.isFinished(date), isTrue);
    });

    test('keeps an archived plan archived regardless of the date', () {
      // Arrange
      final archivedPlan = Plan(
        id: 'plan-2',
        title: 'Archived plan',
        startDate: DateTime(2026, 8, 3),
        endDate: DateTime(2026, 8, 9),
        repeatsWeekly: true,
        createdAt: DateTime(2026, 8, 1),
        status: PlanLifecycleStatus.archived,
      );

      // Act
      final status = archivedPlan.statusAt(DateTime(2026, 8, 5));

      // Assert
      expect(status, PlanLifecycleStatus.archived);
    });
  });
}
