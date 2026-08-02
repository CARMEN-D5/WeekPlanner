import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../domain/plan_history.dart';
import '../domain/plan_item.dart';
import '../domain/timeline_render.dart';
import '../state/plan_controller.dart';
import 'finished_plan_details_page.dart';
import 'plan_editor_page.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  var _section = _HistorySection.records;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PlanController>();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('History', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 14),
        _HistoryTabs(
            selected: _section,
            onSelected: (value) => setState(() => _section = value)),
        const SizedBox(height: 18),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: switch (_section) {
            _HistorySection.records =>
              _ExecutionHistory(controller: controller),
            _HistorySection.compensation =>
              _CompensationHistory(controller: controller),
            _HistorySection.finished =>
              _FinishedPlansHistory(controller: controller),
          },
        ),
      ],
    );
  }
}

enum _HistorySection { records, compensation, finished }

class _HistoryTabs extends StatelessWidget {
  const _HistoryTabs({required this.selected, required this.onSelected});

  final _HistorySection selected;
  final ValueChanged<_HistorySection> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _tab(context, _HistorySection.records, 'Records'),
          _tab(context, _HistorySection.compensation, 'Compensation'),
          _tab(context, _HistorySection.finished, 'Finished plans'),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, _HistorySection section, String label) {
    final theme = Theme.of(context);
    final isSelected = selected == section;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: () => onSelected(section),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 11),
            decoration: BoxDecoration(
              color:
                  isSelected ? theme.colorScheme.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: isSelected
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExecutionHistory extends StatelessWidget {
  const _ExecutionHistory({required this.controller});

  final PlanController controller;

  @override
  Widget build(BuildContext context) {
    final selected = controller.selectedDate;
    final plan = _planForDate(controller.plans, selected);
    final monthItems = controller.items
        .where((item) =>
            item.date.year == selected.year &&
            item.date.month == selected.month &&
            item.countsForCompletion)
        .toList();
    final monthDone =
        monthItems.where((item) => item.status == PlanStatus.completed).length;
    final monthRate =
        monthItems.isEmpty ? 0 : (monthDone / monthItems.length * 100).round();
    return Column(
      key: const ValueKey('records'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HistoryPlanCard(
            plan: plan,
            onTap: plan == null
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => PlanEditorPage(plan: plan)))),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Completion in ${selected.month}/${selected.year}'),
              const SizedBox(height: 12),
              Text('$monthRate%',
                  style: Theme.of(context).textTheme.displaySmall),
              LinearProgressIndicator(
                  value: monthRate / 100,
                  color: const Color(0xFFA8B6C6),
                  backgroundColor: const Color(0xFFEEEAE5)),
              const SizedBox(height: 12),
              Text(
                  'Completed $monthDone / ${monthItems.length} tasks (buffers excluded)'),
            ]),
          ),
        ),
      ],
    );
  }
}

class _CompensationHistory extends StatelessWidget {
  const _CompensationHistory({required this.controller});

  final PlanController controller;

  @override
  Widget build(BuildContext context) {
    final groups = _groupCompensation(controller.compensationCandidates(
        referenceDate: controller.selectedDate));
    return Column(
      key: const ValueKey('compensation'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Unfinished tasks from the last 7 days',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (groups.isEmpty)
          const Card(
              child: ListTile(
                  leading: Icon(Icons.check_circle_outline),
                  title: Text('No unfinished tasks from the last 7 days'))),
        ...groups.map((group) => _CompensationCard(
            group: group,
            onCompensate: () =>
                controller.compensateOldest(group.normalizedTitle))),
      ],
    );
  }
}

class _FinishedPlansHistory extends StatelessWidget {
  const _FinishedPlansHistory({required this.controller});

  final PlanController controller;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final finished = controller.plans
        .where((plan) => plan.isFinished(today))
        .toList()
      ..sort((a, b) => b.endDate.compareTo(a.endDate));
    return Column(
      key: const ValueKey('finished'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (finished.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(children: [
                const Icon(Icons.archive_outlined, size: 34),
                const SizedBox(height: 10),
                Text('No finished plans yet',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                const Text(
                    'When a stage plan ends, its execution records will be saved here.',
                    textAlign: TextAlign.center),
                const SizedBox(height: 14),
                OutlinedButton(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const PlanEditorPage())),
                    child: const Text('Create a weekly plan')),
              ]),
            ),
          ),
        ...finished.map((plan) => _FinishedPlanCard(plan: plan)),
      ],
    );
  }
}

class _FinishedPlanCard extends StatelessWidget {
  const _FinishedPlanCard({required this.plan});

  final Plan plan;

  @override
  Widget build(BuildContext context) {
    final duration = plan.endDate.difference(plan.startDate).inDays + 1;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => FinishedPlanDetailsPage(plan: plan))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
          child: Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Text(plan.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium)),
                      const _StatusPill(
                          label: 'Finished', color: Color(0xFFD8D0DE)),
                    ]),
                    const SizedBox(height: 6),
                    Text(
                        '${DateFormat('MMM d').format(plan.startDate)} – ${DateFormat('MMM d').format(plan.endDate)}'),
                    Text('$duration days',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 8),
                    FutureBuilder<List<PlanItem>>(
                      future: context
                          .read<PlanController>()
                          .instancesForPlan(plan.id),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData)
                          return const SizedBox(
                              height: 18,
                              child: LinearProgressIndicator(minHeight: 3));
                        final summary = PlanHistorySummary(
                            plan: plan, items: snapshot.data!);
                        return Text(
                            '${summary.completionPercent}% completed · ${summary.completedCount} done · ${summary.incompleteCount} incomplete',
                            style: Theme.of(context).textTheme.bodySmall);
                      },
                    ),
                  ]),
            ),
            const Icon(Icons.chevron_right),
          ]),
        ),
      ),
    );
  }
}

class _CompensationGroup {
  const _CompensationGroup(
      {required this.normalizedTitle, required this.items});

  final String normalizedTitle;
  final List<PlanItem> items;
}

List<_CompensationGroup> _groupCompensation(List<PlanItem> candidates) {
  final byTitle = <String, List<PlanItem>>{};
  for (final item in candidates) {
    byTitle.putIfAbsent(normalizeEventTitle(item.title), () => []).add(item);
  }
  return byTitle.entries
      .map((entry) => _CompensationGroup(
          normalizedTitle: entry.key,
          items: entry.value..sort((a, b) => a.date.compareTo(b.date))))
      .toList()
    ..sort((a, b) => a.items.first.date.compareTo(b.items.first.date));
}

class _CompensationCard extends StatelessWidget {
  const _CompensationCard({required this.group, required this.onCompensate});

  final _CompensationGroup group;
  final Future<void> Function() onCompensate;

  @override
  Widget build(BuildContext context) {
    final displayTitle =
        group.items.first.title.trim().replaceAll(RegExp(r'\s+'), ' ');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: const Icon(Icons.pending_actions_outlined),
        title: Text('$displayTitle ×${group.items.length}'),
        subtitle: Text(
            group.items
                .map((item) => '${item.date.month}/${item.date.day}')
                .join(', '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        children: [
          for (final item in group.items)
            ListTile(
                dense: true,
                leading: const Icon(Icons.check_box_outline_blank, size: 18),
                title: Text(
                    '${item.date.month}/${item.date.day}  ${_clock(item.startMinute)}–${_clock(item.endMinute)}'),
                subtitle: Text(_typeName(item.type))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                    onPressed: () async {
                      await onCompensate();
                      if (context.mounted)
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text(
                                'The oldest unfinished record was completed')));
                    },
                    icon: const Icon(Icons.add_task_outlined),
                    label: const Text('Record an extra completion'))),
          ),
        ],
      ),
    );
  }
}

class _HistoryPlanCard extends StatelessWidget {
  const _HistoryPlanCard({required this.plan, required this.onTap});

  final Plan? plan;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Expanded(
                  child: Text(plan?.title ?? 'No active plan',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium)),
              if (plan != null) const Icon(Icons.edit_outlined, size: 20),
            ]),
          ),
        ),
      );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(12)),
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(label, style: Theme.of(context).textTheme.labelSmall)),
      );
}

Plan? _planForDate(List<Plan> plans, DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  for (final plan in plans) {
    if (plan.contains(day)) return plan;
  }
  return null;
}

String _typeName(PlanType type) => switch (type) {
      PlanType.task => 'Task',
      PlanType.fixed => 'Fixed',
      PlanType.buffer => 'Buffer',
    };

String _clock(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
