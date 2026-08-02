import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../domain/plan_history.dart';
import '../domain/plan_item.dart';
import '../state/plan_controller.dart';
import 'plan_editor_page.dart';

class FinishedPlanDetailsPage extends StatelessWidget {
  const FinishedPlanDetailsPage({super.key, required this.plan});

  final Plan plan;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<PlanController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Finished plan'),
        actions: [
          PopupMenuButton<_PlanAction>(
            onSelected: (action) => _handleAction(context, action),
            itemBuilder: (context) => const [
              PopupMenuItem(value: _PlanAction.rename, child: Text('Rename')),
              PopupMenuItem(
                  value: _PlanAction.delete, child: Text('Delete history')),
            ],
          ),
        ],
      ),
      body: FutureBuilder<List<PlanItem>>(
        future: controller.instancesForPlan(plan.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
                child: Text('Unable to load plan history: ${snapshot.error}'));
          }
          return _FinishedPlanBody(
              summary: PlanHistorySummary(
                  plan: plan, items: snapshot.data ?? const []));
        },
      ),
    );
  }

  Future<void> _handleAction(BuildContext context, _PlanAction action) async {
    if (action == _PlanAction.rename) {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => PlanEditorPage(plan: plan)));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete plan history?'),
        content: const Text(
            'This will delete the plan, event records and statistics. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<PlanController>().deletePlan(plan.id);
      if (context.mounted) Navigator.pop(context);
    }
  }
}

enum _PlanAction { rename, delete }

class _FinishedPlanBody extends StatelessWidget {
  const _FinishedPlanBody({required this.summary});

  final PlanHistorySummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final start = DateFormat('MMM d, yyyy').format(summary.plan.startDate);
    final end = DateFormat('MMM d, yyyy').format(summary.plan.endDate);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text(summary.plan.title,
                        style: theme.textTheme.headlineSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis)),
                _StatusPill(label: 'Finished', color: const Color(0xFFD8D0DE)),
              ]),
              const SizedBox(height: 8),
              Text('$start – $end',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              if (summary.statisticsAreProvisional) ...[
                const SizedBox(height: 8),
                Text(
                    'Statistics may update during the 7-day compensation window.',
                    style: theme.textTheme.bodySmall),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 14),
        _StatsGrid(summary: summary),
        const SizedBox(height: 18),
        _SectionTitle(title: 'Completion overview'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(children: [
              SizedBox(
                  width: 132,
                  height: 132,
                  child: CustomPaint(
                      painter: _DoughnutPainter(
                          done: summary.completedCount,
                          total: summary.scheduledCount,
                          colors: [
                        const Color(0xFFAAB9A3),
                        const Color(0xFFD7C5C5)
                      ]))),
              const SizedBox(width: 20),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('${summary.completionPercent}%',
                        style: theme.textTheme.displaySmall),
                    const SizedBox(height: 8),
                    _LegendRow(
                        color: const Color(0xFFAAB9A3),
                        label: 'Completed',
                        value: summary.completedCount),
                    _LegendRow(
                        color: const Color(0xFFD7C5C5),
                        label: 'Incomplete',
                        value: summary.incompleteCount),
                  ])),
            ]),
          ),
        ),
        const SizedBox(height: 18),
        if (summary.weeklyTrend.isNotEmpty) ...[
          const _SectionTitle(title: 'Weekly execution trend'),
          Card(
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
                  child: Column(children: [
                    for (final trend in summary.weeklyTrend)
                      _TrendRow(week: trend.week, rate: trend.rate),
                  ]))),
          const SizedBox(height: 18),
        ],
        const _SectionTitle(title: 'Unfinished task details'),
        if (summary.unfinishedGroups.isEmpty)
          const Card(
              child: ListTile(
                  leading: Icon(Icons.check_circle_outline),
                  title: Text('All planned tasks were completed.')))
        else ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Unfinished task distribution',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 14),
                    _UnfinishedDistribution(groups: summary.unfinishedGroups),
                  ]),
            ),
          ),
          const SizedBox(height: 8),
          for (final group in summary.unfinishedGroups)
            _UnfinishedGroupTile(
                group: group,
                plan: summary.plan,
                totalIncomplete: summary.incompleteCount),
        ],
      ],
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.summary});

  final PlanHistorySummary summary;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _StatCard(label: 'Planned', value: summary.scheduledCount.toString()),
          _StatCard(
              label: 'Completed', value: summary.completedCount.toString()),
          _StatCard(
              label: 'Incomplete', value: summary.incompleteCount.toString()),
          _StatCard(
              label: 'Compensated', value: summary.compensatedCount.toString()),
        ],
      );
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: (MediaQuery.sizeOf(context).width - 56) / 2,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 3),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(14)),
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            child: Text(label)),
      );
}

class _LegendRow extends StatelessWidget {
  const _LegendRow(
      {required this.color, required this.label, required this.value});

  final Color color;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          Text(value.toString()),
        ]),
      );
}

class _TrendRow extends StatelessWidget {
  const _TrendRow({required this.week, required this.rate});

  final DateTime week;
  final double rate;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(children: [
          SizedBox(
              width: 70,
              child: Text(DateFormat('MMM d').format(week),
                  style: Theme.of(context).textTheme.bodySmall)),
          Expanded(
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                      minHeight: 9,
                      value: rate,
                      color: const Color(0xFFAAB9A3),
                      backgroundColor: const Color(0xFFE5E1DD)))),
          const SizedBox(width: 10),
          SizedBox(
              width: 42,
              child:
                  Text('${(rate * 100).round()}%', textAlign: TextAlign.end)),
        ]),
      );
}

class _UnfinishedGroupTile extends StatelessWidget {
  const _UnfinishedGroupTile(
      {required this.group, required this.plan, required this.totalIncomplete});

  final UnfinishedTaskGroup group;
  final Plan plan;
  final int totalIncomplete;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ExpansionTile(
          title: Text('${group.displayTitle} ×${group.items.length}'),
          subtitle: Text(
              '${(group.items.length / math.max(1, totalIncomplete) * 100).round()}% of unfinished records'),
          children: [
            for (final item in group.items)
              ListTile(
                dense: true,
                leading: Icon(item.compensatedById == null
                    ? Icons.warning_amber_outlined
                    : Icons.replay_circle_filled_outlined),
                title: Text(
                    '${DateFormat('MMM d').format(item.date)}  ${_clock(item.startMinute)}–${_clock(item.endMinute)}'),
                subtitle: Text(
                    '${_typeName(item.type)} · ${item.compensatedById == null ? (item.date.isBefore(plan.finalizationDate) ? 'Not completed' : 'Compensation expired') : 'Completed by compensation'}'),
              ),
          ],
        ),
      );
}

class _UnfinishedDistribution extends StatelessWidget {
  const _UnfinishedDistribution({required this.groups});

  final List<UnfinishedTaskGroup> groups;

  @override
  Widget build(BuildContext context) {
    if (groups.length <= 6) {
      return Row(children: [
        SizedBox(
            width: 130,
            height: 130,
            child: CustomPaint(painter: _MultiSlicePainter(groups: groups))),
        const SizedBox(width: 16),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var index = 0; index < groups.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(children: [
                Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                        color: _unfinishedColor(index),
                        shape: BoxShape.circle)),
                const SizedBox(width: 7),
                Expanded(
                    child: Text(groups[index].displayTitle,
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
                Text(groups[index].items.length.toString()),
              ]),
            ),
        ])),
      ]);
    }
    return SizedBox(
        height: 170,
        child: CustomPaint(painter: _UnfinishedBarsPainter(groups: groups)));
  }
}

String _typeName(PlanType type) => switch (type) {
      PlanType.task => 'Task',
      PlanType.fixed => 'Fixed',
      PlanType.buffer => 'Buffer',
    };

String _clock(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

class _DoughnutPainter extends CustomPainter {
  const _DoughnutPainter(
      {required this.done, required this.total, required this.colors});

  final int done;
  final int total;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 8;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 22
      ..strokeCap = StrokeCap.butt;
    final rate = total == 0 ? 0.0 : done / total;
    paint.color = colors[1];
    canvas.drawCircle(center, radius, paint);
    paint.color = colors[0];
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2, math.pi * 2 * rate, false, paint);
  }

  @override
  bool shouldRepaint(covariant _DoughnutPainter oldDelegate) =>
      oldDelegate.done != done || oldDelegate.total != total;
}

class _UnfinishedBarsPainter extends CustomPainter {
  const _UnfinishedBarsPainter({required this.groups});

  final List<UnfinishedTaskGroup> groups;

  @override
  void paint(Canvas canvas, Size size) {
    final maxCount =
        groups.fold<int>(1, (max, group) => math.max(max, group.items.length));
    final visible = groups.take(6).toList();
    final rowHeight = size.height / math.max(1, visible.length);
    final textStyle = const TextStyle(fontSize: 11, color: Color(0xFF5D5A56));
    for (var index = 0; index < visible.length; index++) {
      final group = visible[index];
      final y = index * rowHeight + 4;
      final width = (size.width - 96) * group.items.length / maxCount;
      final label = group.displayTitle.length > 15
          ? '${group.displayTitle.substring(0, 15)}…'
          : group.displayTitle;
      final painter = TextPainter(
          text: TextSpan(text: label, style: textStyle),
          textDirection: ui.TextDirection.ltr)
        ..layout(maxWidth: 78);
      painter.paint(canvas, Offset(0, y));
      final bar = Paint()..color = const Color(0xFFD7C5C5);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(86, y + 2, width, 16), const Radius.circular(8)),
          bar);
      final countPainter = TextPainter(
          text: TextSpan(text: group.items.length.toString(), style: textStyle),
          textDirection: ui.TextDirection.ltr)
        ..layout();
      countPainter.paint(canvas, Offset(92 + width, y + 2));
    }
  }

  @override
  bool shouldRepaint(covariant _UnfinishedBarsPainter oldDelegate) =>
      oldDelegate.groups != groups;
}

class _MultiSlicePainter extends CustomPainter {
  const _MultiSlicePainter({required this.groups});

  final List<UnfinishedTaskGroup> groups;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 8;
    final total = groups.fold<int>(0, (sum, group) => sum + group.items.length);
    var start = -math.pi / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 22;
    for (var index = 0; index < groups.length; index++) {
      final sweep =
          total == 0 ? 0.0 : math.pi * 2 * groups[index].items.length / total;
      paint.color = _unfinishedColor(index);
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), start,
          sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _MultiSlicePainter oldDelegate) =>
      oldDelegate.groups != groups;
}

Color _unfinishedColor(int index) => const [
      Color(0xFFD7C5C5),
      Color(0xFFC7D1D8),
      Color(0xFFD8D0DE),
      Color(0xFFD6C9AF),
      Color(0xFFC8D1C1),
      Color(0xFFD3C6BC),
    ][index % 6];
