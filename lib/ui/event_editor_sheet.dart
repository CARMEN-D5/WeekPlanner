import 'package:flutter/material.dart';

import '../domain/plan_item.dart';
import '../domain/timeline_render.dart';
import 'event_conflict_dialog.dart';
import 'time_wheel_picker.dart';
import 'type_tabs.dart';

/// The event editor owns all of its local state.  In particular, text and
/// focus controllers are not kept by a [StatefulBuilder] in a route overlay;
/// this makes opening and closing the keyboard a normal widget lifecycle.
Future<void> showEventEditorSheet(
  BuildContext context, {
  required DateTime date,
  required int initialStart,
  required int initialEnd,
  required EventEditorMode mode,
  PlanItem? source,
  required Future<void> Function(EventEditorDraft draft) onSave,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EventEditorSheet(
        date: date,
        initialStart: initialStart,
        initialEnd: initialEnd,
        mode: mode,
        source: source,
        onSave: onSave,
      ),
    );

enum EventEditorMode { create, edit, copy }

class EventEditorDraft {
  const EventEditorDraft({
    required this.title,
    required this.date,
    required this.type,
    required this.startMinute,
    required this.endMinute,
  });

  final String title;
  final DateTime date;
  final PlanType type;
  final int startMinute;
  final int endMinute;
}

class _EventEditorSheet extends StatefulWidget {
  const _EventEditorSheet({
    required this.date,
    required this.initialStart,
    required this.initialEnd,
    required this.mode,
    required this.source,
    required this.onSave,
  });

  final DateTime date;
  final int initialStart;
  final int initialEnd;
  final EventEditorMode mode;
  final PlanItem? source;
  final Future<void> Function(EventEditorDraft draft) onSave;

  @override
  State<_EventEditorSheet> createState() => _EventEditorSheetState();
}

class _EventEditorSheetState extends State<_EventEditorSheet> {
  late final TextEditingController _title;
  late DateTime _date;
  late PlanType _type;
  late int _start;
  late int _end;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final source = widget.source;
    _title = TextEditingController(text: source?.title ?? '');
    _date = source?.date ?? widget.date;
    _type = source?.type ?? PlanType.task;
    _start = source?.startMinute ?? widget.initialStart;
    _end = source?.endMinute ?? widget.initialEnd;
    if (_end <= _start) _end = _start + 1;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  String get _heading => switch (widget.mode) {
        EventEditorMode.create => 'New event',
        EventEditorMode.edit => 'Edit event',
        EventEditorMode.copy => 'Copy event',
      };

  Future<void> _chooseTime({required bool start}) async {
    final picked = await showTimeWheelPicker(
      context,
      initialMinute: start ? _start : _end,
      title: start ? 'Choose start time' : 'Choose end time',
    );
    if (!mounted || picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
        if (_end <= _start) _end = _start + 1;
      } else {
        _end = picked;
        if (_end <= _start) _start = _end - 1;
      }
    });
  }

  Future<void> _chooseDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (!mounted || picked == null) return;
    setState(() => _date = DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    if (title.isEmpty || _end <= _start || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(
        EventEditorDraft(
          title: title,
          date: _date,
          type: _type,
          startMinute: _start,
          endMinute: _end,
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } on EventConflictException catch (error) {
      if (mounted) await showEventConflictDialog(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_heading, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 14),
              TextField(
                controller: _title,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Event name'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _TimeButton(
                      label: 'Start',
                      minute: _start,
                      onTap: () => _chooseTime(start: true),
                    ),
                  ),
                  Expanded(
                    child: _TimeButton(
                      label: 'End',
                      minute: _end,
                      onTap: () => _chooseTime(start: false),
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _chooseDate,
                  icon: const Icon(Icons.calendar_today_outlined, size: 17),
                  label: Text(
                    '${_date.year}/${_date.month}/${_date.day}',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              EventTypeTabs(
                value: _type,
                onChanged: (value) => setState(() => _type = value),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: Text(_saving ? 'Saving…' : 'Save'),
                ),
              ),
            ],
          ),
        ),
      );
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({
    required this.label,
    required this.minute,
    required this.onTap,
  });

  final String label;
  final int minute;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onTap,
        child: Text('$label ${_clock(minute)}'),
      );
}

String _clock(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
