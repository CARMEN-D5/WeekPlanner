import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../domain/plan_item.dart';
import '../domain/timeline.dart';
import '../domain/timeline_render.dart';

/// SQLite storage for the Plan → Template → Instance model.
class PlanRepository {
  final _uuid = const Uuid();
  Database? _database;

  Future<Database> get _db async {
    if (_database != null) return _database!;
    final databasesPath = await getDatabasesPath();
    _database = await openDatabase(
      path.join(databasesPath, 'cadence_v1.db'),
      version: 5,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE plans (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            start_date TEXT NOT NULL,
            end_date TEXT NOT NULL,
            repeats_weekly INTEGER NOT NULL,
            created_at TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'active',
            finished_at TEXT,
            statistics_finalized_at TEXT
            ,timeline_snapshot TEXT
          )
        ''');
        await database.execute('''
          CREATE TABLE week_templates (
            id TEXT PRIMARY KEY,
            plan_id TEXT NOT NULL,
            title TEXT NOT NULL,
            weekday INTEGER NOT NULL,
            block INTEGER NOT NULL,
            type INTEGER NOT NULL,
            start_minute INTEGER,
            end_minute INTEGER
          )
        ''');
        await database.execute('''
          CREATE TABLE task_instances (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            date TEXT NOT NULL,
            type INTEGER NOT NULL,
            status INTEGER NOT NULL,
            block INTEGER NOT NULL,
            start_minute INTEGER,
            end_minute INTEGER,
            plan_id TEXT,
            template_id TEXT,
            compensated_by_id TEXT,
            completed_at TEXT,
            created_at TEXT NOT NULL
          )
        ''');
        await database.execute(
          'CREATE INDEX instance_date_index ON task_instances(date)',
        );
        await database.execute(
          'CREATE INDEX instance_template_index ON task_instances(template_id, date)',
        );
        await _createTimelineTables(database);
        await _createGenerationConflictTable(database);
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createTimelineTables(database);
        if (oldVersion < 3) await _createGenerationConflictTable(database);
        if (oldVersion < 4) await _addPlanHistoryColumns(database);
        if (oldVersion < 5) {
          await database.execute(
            'ALTER TABLE plans ADD COLUMN timeline_snapshot TEXT',
          );
        }
      },
    );
    return _database!;
  }

  Future<void> _addPlanHistoryColumns(DatabaseExecutor database) async {
    await database.execute(
      "ALTER TABLE plans ADD COLUMN status TEXT NOT NULL DEFAULT 'active'",
    );
    await database.execute('ALTER TABLE plans ADD COLUMN finished_at TEXT');
    await database.execute(
      'ALTER TABLE plans ADD COLUMN statistics_finalized_at TEXT',
    );
  }

  Future<void> _createTimelineTables(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE timeline_blocks (
        id TEXT PRIMARY KEY,
        order_index INTEGER NOT NULL,
        name TEXT NOT NULL,
        start_minute INTEGER NOT NULL,
        end_minute INTEGER NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE timeline_segments (
        id TEXT PRIMARY KEY,
        block_id TEXT NOT NULL,
        start_minute INTEGER NOT NULL,
        end_minute INTEGER NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE timeline_gaps (
        after_order INTEGER PRIMARY KEY,
        label TEXT
      )
    ''');
  }

  Future<void> _createGenerationConflictTable(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE generation_conflicts (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL,
        plan_id TEXT NOT NULL,
        template_id TEXT NOT NULL,
        conflicting_instance_id TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await database.execute(
      'CREATE UNIQUE INDEX generation_conflict_template_date_index ON generation_conflicts(template_id, date)',
    );
  }

  Future<TimelineModel> fetchTimeline() async {
    final database = await _db;
    var blockRows = await database.query(
      'timeline_blocks',
      orderBy: 'order_index ASC',
    );
    if (blockRows.isEmpty) {
      await _seedTimeline(database);
      blockRows = await database.query(
        'timeline_blocks',
        orderBy: 'order_index ASC',
      );
    }
    final segmentRows = await database.query('timeline_segments');
    final gapRows = await database.query('timeline_gaps');
    return TimelineModel(
      blocks: blockRows
          .map(
            (row) => TimelineBlock(
              id: row['id']! as String,
              order: row['order_index']! as int,
              name: row['name']! as String,
              startMinute: row['start_minute']! as int,
              endMinute: row['end_minute']! as int,
            ),
          )
          .toList(),
      segments: segmentRows
          .map(
            (row) => TimelineSegment(
              id: row['id']! as String,
              blockId: row['block_id']! as String,
              startMinute: row['start_minute']! as int,
              endMinute: row['end_minute']! as int,
            ),
          )
          .toList(),
      gapLabels: {
        for (final row in gapRows)
          row['after_order']! as int: row['label'] as String? ?? '',
      },
    );
  }

  Future<void> saveTimeline(TimelineModel timeline) async {
    final database = await _db;
    await database.transaction((transaction) async {
      await transaction.delete('timeline_blocks');
      await transaction.delete('timeline_segments');
      await transaction.delete('timeline_gaps');
      for (final block in timeline.blocks) {
        await transaction.insert('timeline_blocks', {
          'id': block.id,
          'order_index': block.order,
          'name': block.name,
          'start_minute': block.startMinute,
          'end_minute': block.endMinute,
        });
      }
      for (final segment in timeline.segments) {
        await transaction.insert('timeline_segments', {
          'id': segment.id,
          'block_id': segment.blockId,
          'start_minute': segment.startMinute,
          'end_minute': segment.endMinute,
        });
      }
      for (final entry in timeline.gapLabels.entries) {
        await transaction.insert('timeline_gaps', {
          'after_order': entry.key,
          'label': entry.value,
        });
      }
    });
  }

  Future<void> preserveMissingPlanTimelineSnapshots(
    TimelineModel currentTimeline,
  ) async {
    final database = await _db;
    await database.update('plans', {
      'timeline_snapshot': _encodeTimeline(currentTimeline),
    }, where: 'timeline_snapshot IS NULL');
  }

  Future<void> applyTimelineToActiveAndUpcomingPlans(
    TimelineModel timeline,
  ) async {
    final database = await _db;
    await database.update(
      'plans',
      {'timeline_snapshot': _encodeTimeline(timeline)},
      where: 'end_date >= ?',
      whereArgs: [_date(DateTime.now())],
    );
  }

  Future<List<TimelineTemplateConflict>> timelineConflicts(
    TimelineModel timeline,
  ) async {
    final today = _day(DateTime.now());
    final result = <TimelineTemplateConflict>[];
    for (final plan in (await fetchPlans()).where(
      (value) => !value.endDate.isBefore(today),
    )) {
      for (final template in await fetchTemplates(plan.id)) {
        if (!timeline.containsRange(template.startMinute, template.endMinute)) {
          result.add(TimelineTemplateConflict(plan: plan, template: template));
        }
      }
    }
    return result;
  }

  Future<void> splitSegment(String segmentId, int atMinute) async {
    final timeline = await fetchTimeline();
    final segment = timeline.segments.firstWhere(
      (item) => item.id == segmentId,
    );
    if (atMinute <= segment.startMinute || atMinute >= segment.endMinute)
      return;
    final database = await _db;
    await database.transaction((transaction) async {
      await transaction.delete(
        'timeline_segments',
        where: 'id = ?',
        whereArgs: [segmentId],
      );
      await transaction.insert('timeline_segments', {
        'id': _uuid.v4(),
        'block_id': segment.blockId,
        'start_minute': segment.startMinute,
        'end_minute': atMinute,
      });
      await transaction.insert('timeline_segments', {
        'id': _uuid.v4(),
        'block_id': segment.blockId,
        'start_minute': atMinute,
        'end_minute': segment.endMinute,
      });
    });
  }

  Future<void> mergeSegmentWithNext(String segmentId) async {
    final timeline = await fetchTimeline();
    final segment = timeline.segments.firstWhere(
      (item) => item.id == segmentId,
    );
    final segments = timeline.segmentsFor(
      timeline.blocks.firstWhere((block) => block.id == segment.blockId),
    );
    final index = segments.indexWhere((item) => item.id == segmentId);
    if (index < 0 ||
        index == segments.length - 1 ||
        segments[index + 1].startMinute != segment.endMinute)
      return;
    final next = segments[index + 1];
    final database = await _db;
    await database.transaction((transaction) async {
      await transaction.delete(
        'timeline_segments',
        where: 'id IN (?, ?)',
        whereArgs: [segment.id, next.id],
      );
      await transaction.insert('timeline_segments', {
        'id': _uuid.v4(),
        'block_id': segment.blockId,
        'start_minute': segment.startMinute,
        'end_minute': next.endMinute,
      });
    });
  }

  Future<void> _seedTimeline(DatabaseExecutor database) async {
    final defaults = [
      const TimelineBlock(
        id: 'morning',
        order: 0,
        name: 'Morning',
        startMinute: 360,
        endMinute: 720,
      ),
      const TimelineBlock(
        id: 'afternoon',
        order: 1,
        name: 'Afternoon',
        startMinute: 720,
        endMinute: 1080,
      ),
      const TimelineBlock(
        id: 'evening',
        order: 2,
        name: 'Evening',
        startMinute: 1080,
        endMinute: 1410,
      ),
    ];
    for (final block in defaults) {
      await database.insert('timeline_blocks', {
        'id': block.id,
        'order_index': block.order,
        'name': block.name,
        'start_minute': block.startMinute,
        'end_minute': block.endMinute,
      });
      await database.insert('timeline_segments', {
        'id': _uuid.v4(),
        'block_id': block.id,
        'start_minute': block.startMinute,
        'end_minute': block.endMinute,
      });
    }
  }

  Future<List<Plan>> fetchPlans() async {
    final database = await _db;
    final rows = await database.query('plans', orderBy: 'start_date ASC');
    return rows.map(_planFromRow).toList();
  }

  Future<List<WeekTemplate>> fetchTemplates(String planId) async {
    final database = await _db;
    final rows = await database.query(
      'week_templates',
      where: 'plan_id = ?',
      whereArgs: [planId],
    );
    return rows.map(_templateFromRow).toList();
  }

  Future<List<PlanItem>> fetchInstances(DateTime from, DateTime to) async {
    await _generateInstances(from, to);
    final database = await _db;
    final rows = await database.query(
      'task_instances',
      where: 'date >= ? AND date <= ?',
      whereArgs: [_date(from), _date(to)],
    );
    return rows.map(_itemFromRow).toList();
  }

  /// Reads every retained instance belonging to one plan. The bounded
  /// generation pass materializes any historical recurrence rows that were
  /// never opened while the plan was active; it never generates beyond the
  /// plan end date.
  Future<List<PlanItem>> fetchInstancesForPlan(String planId) async {
    final plans = await fetchPlans();
    Plan? plan;
    for (final candidate in plans) {
      if (candidate.id == planId) {
        plan = candidate;
        break;
      }
    }
    if (plan != null) await _generateInstances(plan.startDate, plan.endDate);
    final database = await _db;
    final rows = await database.query(
      'task_instances',
      where: 'plan_id = ?',
      whereArgs: [planId],
      orderBy: 'date ASC, start_minute ASC',
    );
    return rows.map(_itemFromRow).toList();
  }

  Future<void> savePlan(Plan plan, List<WeekTemplate> templates) async {
    _ensureTemplateTimesDoNotOverlap(templates);
    final conflicts = (await fetchPlans())
        .where(
          (candidate) =>
              candidate.id != plan.id &&
              _overlaps(
                plan.startDate,
                plan.endDate,
                candidate.startDate,
                candidate.endDate,
              ),
        )
        .toList();
    if (conflicts.isNotEmpty) throw PlanConflictException(conflicts);
    final database = await _db;
    final today = _date(DateTime.now());
    await database.transaction((transaction) async {
      await transaction.insert(
        'plans',
        _planRow(plan),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await transaction.delete(
        'week_templates',
        where: 'plan_id = ?',
        whereArgs: [plan.id],
      );
      // Keep completed history intact, but regenerate pending instances from
      // today onward so a long-term template edit is reflected everywhere.
      await transaction.delete(
        'task_instances',
        where: 'plan_id = ? AND status = ? AND date >= ?',
        whereArgs: [plan.id, PlanStatus.pending.index, today],
      );
      for (final template in templates) {
        await transaction.insert('week_templates', _templateRow(template));
      }
    });
  }

  Future<void> replaceConflictingAndSave(
    Plan plan,
    List<WeekTemplate> templates,
  ) async {
    _ensureTemplateTimesDoNotOverlap(templates);
    final conflicts = (await fetchPlans())
        .where(
          (candidate) =>
              candidate.id != plan.id &&
              _overlaps(
                plan.startDate,
                plan.endDate,
                candidate.startDate,
                candidate.endDate,
              ),
        )
        .toList();
    final database = await _db;
    final today = _date(DateTime.now());
    await database.transaction((transaction) async {
      for (final conflict in conflicts) {
        await transaction.delete(
          'plans',
          where: 'id = ?',
          whereArgs: [conflict.id],
        );
        await transaction.delete(
          'week_templates',
          where: 'plan_id = ?',
          whereArgs: [conflict.id],
        );
        await transaction.delete(
          'task_instances',
          where: 'plan_id = ?',
          whereArgs: [conflict.id],
        );
      }
      await transaction.insert(
        'plans',
        _planRow(plan),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await transaction.delete(
        'week_templates',
        where: 'plan_id = ?',
        whereArgs: [plan.id],
      );
      await transaction.delete(
        'task_instances',
        where: 'plan_id = ? AND status = ? AND date >= ?',
        whereArgs: [plan.id, PlanStatus.pending.index, today],
      );
      for (final template in templates) {
        await transaction.insert('week_templates', _templateRow(template));
      }
    });
  }

  Future<void> deletePlan(String planId) async {
    final database = await _db;
    await database.transaction((transaction) async {
      await transaction.delete('plans', where: 'id = ?', whereArgs: [planId]);
      await transaction.delete(
        'week_templates',
        where: 'plan_id = ?',
        whereArgs: [planId],
      );
      await transaction.delete(
        'task_instances',
        where: 'plan_id = ?',
        whereArgs: [planId],
      );
    });
  }

  Future<void> saveInstance(PlanItem item) async {
    final database = await _db;
    await database.insert(
      'task_instances',
      _itemRow(item),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteInstance(String instanceId) async {
    final database = await _db;
    await database.delete(
      'task_instances',
      where: 'id = ?',
      whereArgs: [instanceId],
    );
  }

  Future<void> _generateInstances(DateTime from, DateTime to) async {
    final database = await _db;
    final plans = await fetchPlans();
    var day = _day(from);
    final end = _day(to);
    while (!day.isAfter(end)) {
      for (final plan in plans.where((value) => value.contains(day))) {
        final templates = await fetchTemplates(plan.id);
        for (final template in templates) {
          final shouldGenerate = plan.repeatsWeekly
              ? day.weekday == template.weekday
              : _sameDay(day, plan.startDate) &&
                    day.weekday == template.weekday;
          if (!shouldGenerate) continue;
          final existing = await database.query(
            'task_instances',
            columns: ['id'],
            where: 'template_id = ? AND date = ?',
            whereArgs: [template.id, _date(day)],
            limit: 1,
          );
          if (existing.isNotEmpty) continue;
          final overlapping = await database.query(
            'task_instances',
            columns: ['id'],
            where: 'date = ? AND start_minute < ? AND end_minute > ?',
            whereArgs: [_date(day), template.endMinute, template.startMinute],
            limit: 1,
          );
          // A manually created item or a one-off adjustment owns this time.
          // Do not generate a second overlapping instance on top of it.
          if (overlapping.isNotEmpty) {
            await database.insert('generation_conflicts', {
              'id': _uuid.v4(),
              'date': _date(day),
              'plan_id': plan.id,
              'template_id': template.id,
              'conflicting_instance_id': overlapping.first['id'] as String?,
              'created_at': DateTime.now().toIso8601String(),
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
            continue;
          }
          await database.insert(
            'task_instances',
            _itemRow(
              PlanItem(
                id: _uuid.v4(),
                title: template.title,
                date: day,
                type: template.type,
                status: PlanStatus.pending,
                startMinute: template.startMinute,
                endMinute: template.endMinute,
                planId: plan.id,
                templateId: template.id,
                createdAt: DateTime.now(),
              ),
            ),
          );
        }
      }
      day = day.add(const Duration(days: 1));
    }
  }

  Map<String, Object?> _planRow(Plan plan) => {
    'id': plan.id,
    'title': plan.title,
    'start_date': _date(plan.startDate),
    'end_date': _date(plan.endDate),
    'repeats_weekly': plan.repeatsWeekly ? 1 : 0,
    'created_at': plan.createdAt.toIso8601String(),
    'status': _storedLifecycleStatus(plan).name,
    'finished_at': _storedLifecycleStatus(plan) == PlanLifecycleStatus.finished
        ? (plan.finishedAt ?? plan.endDate).toIso8601String()
        : plan.finishedAt?.toIso8601String(),
    'statistics_finalized_at': plan.finalizationDate.toIso8601String(),
    'timeline_snapshot': plan.timelineSnapshot == null
        ? null
        : _encodeTimeline(plan.timelineSnapshot!),
  };

  PlanLifecycleStatus _storedLifecycleStatus(Plan plan) {
    if (plan.status == PlanLifecycleStatus.archived) {
      return PlanLifecycleStatus.archived;
    }
    final today = _day(DateTime.now());
    if (today.isAfter(_day(plan.endDate))) return PlanLifecycleStatus.finished;
    if (today.isBefore(_day(plan.startDate)))
      return PlanLifecycleStatus.upcoming;
    return PlanLifecycleStatus.active;
  }

  Map<String, Object?> _templateRow(WeekTemplate item) => {
    'id': item.id,
    'plan_id': item.planId,
    'title': item.title,
    'weekday': item.weekday,
    'block': 0,
    'type': item.type.index,
    'start_minute': item.startMinute,
    'end_minute': item.endMinute,
  };
  Map<String, Object?> _itemRow(PlanItem item) => {
    'id': item.id,
    'title': item.title,
    'date': _date(item.date),
    'type': item.type.index,
    'status': item.status.index,
    'block': 0,
    'start_minute': item.startMinute,
    'end_minute': item.endMinute,
    'plan_id': item.planId,
    'template_id': item.templateId,
    'compensated_by_id': item.compensatedById,
    'completed_at': item.completedAt?.toIso8601String(),
    'created_at': (item.createdAt ?? DateTime.now()).toIso8601String(),
  };
  Plan _planFromRow(Map<String, Object?> row) => Plan(
    id: row['id']! as String,
    title: row['title']! as String,
    startDate: DateTime.parse(row['start_date']! as String),
    endDate: DateTime.parse(row['end_date']! as String),
    repeatsWeekly: row['repeats_weekly'] == 1,
    createdAt: DateTime.parse(row['created_at']! as String),
    status: _lifecycleStatus(row['status'] as String?),
    finishedAt: _parseNullableDate(row['finished_at'] as String?),
    statisticsFinalizedAt: _parseNullableDate(
      row['statistics_finalized_at'] as String?,
    ),
    timelineSnapshot: _decodeTimeline(row['timeline_snapshot'] as String?),
  );

  PlanLifecycleStatus _lifecycleStatus(String? value) {
    for (final status in PlanLifecycleStatus.values) {
      if (status.name == value) return status;
    }
    return PlanLifecycleStatus.active;
  }

  DateTime? _parseNullableDate(String? value) =>
      value == null ? null : DateTime.tryParse(value);

  String _encodeTimeline(TimelineModel timeline) => jsonEncode({
    'blocks': [
      for (final block in timeline.blocks)
        {
          'id': block.id,
          'order': block.order,
          'name': block.name,
          'start': block.startMinute,
          'end': block.endMinute,
        },
    ],
    'segments': [
      for (final segment in timeline.segments)
        {
          'id': segment.id,
          'blockId': segment.blockId,
          'start': segment.startMinute,
          'end': segment.endMinute,
        },
    ],
    'gaps': {
      for (final entry in timeline.gapLabels.entries)
        '${entry.key}': entry.value,
    },
  });

  TimelineModel? _decodeTimeline(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      final data = jsonDecode(value) as Map<String, dynamic>;
      final blocks = (data['blocks'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(
            (item) => TimelineBlock(
              id: item['id'] as String,
              order: item['order'] as int,
              name: item['name'] as String,
              startMinute: item['start'] as int,
              endMinute: item['end'] as int,
            ),
          )
          .toList();
      final segments = (data['segments'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(
            (item) => TimelineSegment(
              id: item['id'] as String,
              blockId: item['blockId'] as String,
              startMinute: item['start'] as int,
              endMinute: item['end'] as int,
            ),
          )
          .toList();
      final gaps = (data['gaps'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(int.parse(key), value as String),
      );
      return TimelineModel(blocks: blocks, segments: segments, gapLabels: gaps);
    } catch (_) {
      return null;
    }
  }

  WeekTemplate _templateFromRow(Map<String, Object?> row) => WeekTemplate(
    id: row['id']! as String,
    planId: row['plan_id']! as String,
    title: row['title']! as String,
    weekday: row['weekday']! as int,
    type: PlanType.values[row['type']! as int],
    startMinute: row['start_minute'] as int? ?? 540,
    endMinute: row['end_minute'] as int? ?? 600,
  );
  PlanItem _itemFromRow(Map<String, Object?> row) => PlanItem(
    id: row['id']! as String,
    title: row['title']! as String,
    date: DateTime.parse(row['date']! as String),
    type: PlanType.values[row['type']! as int],
    status: PlanStatus.values[row['status']! as int],
    startMinute: row['start_minute'] as int? ?? 540,
    endMinute: row['end_minute'] as int? ?? 600,
    planId: row['plan_id'] as String?,
    templateId: row['template_id'] as String?,
    compensatedById: row['compensated_by_id'] as String?,
    completedAt: row['completed_at'] == null
        ? null
        : DateTime.parse(row['completed_at']! as String),
    createdAt: DateTime.parse(row['created_at']! as String),
  );

  void _ensureTemplateTimesDoNotOverlap(List<WeekTemplate> templates) {
    final conflicts = <WeekTemplate>[];
    for (var index = 0; index < templates.length; index++) {
      final current = templates[index];
      for (
        var otherIndex = index + 1;
        otherIndex < templates.length;
        otherIndex++
      ) {
        final other = templates[otherIndex];
        if (current.weekday == other.weekday &&
            eventsOverlap(
              startMinute: current.startMinute,
              endMinute: current.endMinute,
              otherStartMinute: other.startMinute,
              otherEndMinute: other.endMinute,
            )) {
          if (!conflicts.any((item) => item.id == current.id)) {
            conflicts.add(current);
          }
          if (!conflicts.any((item) => item.id == other.id)) {
            conflicts.add(other);
          }
        }
      }
    }
    if (conflicts.isNotEmpty) throw TemplateConflictException(conflicts);
  }

  bool _overlaps(
    DateTime aStart,
    DateTime aEnd,
    DateTime bStart,
    DateTime bEnd,
  ) => !aEnd.isBefore(bStart) && !aStart.isAfter(bEnd);
  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);
  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
