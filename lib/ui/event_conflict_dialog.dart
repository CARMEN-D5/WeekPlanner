import 'package:flutter/material.dart';

import '../domain/timeline_render.dart';

Future<void> showEventConflictDialog(
  BuildContext context,
  EventConflictException error,
) =>
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Time conflict'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Change the start or end time.'),
            const SizedBox(height: 12),
            ...error.conflicts.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${_clock(item.startMinute)}–${_clock(item.endMinute)}  ${item.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Back to edit'),
          ),
        ],
      ),
    );

Future<void> showTemplateConflictDialog(
  BuildContext context,
  TemplateConflictException error,
) =>
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Template conflict'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Weekly templates on the same day cannot overlap.'),
            const SizedBox(height: 12),
            ...error.conflicts.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${_clock(item.startMinute)}–${_clock(item.endMinute)}  ${item.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Back to edit'),
          ),
        ],
      ),
    );

String _clock(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
