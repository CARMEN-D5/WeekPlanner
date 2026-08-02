import 'package:flutter/material.dart';

import '../domain/plan_item.dart';

/// A deliberately fixed-size alternative to [SegmentedButton].
///
/// The three labels have very different lengths in Chinese, so a normal
/// segmented control can reflow while switching selection.  Each tab here
/// always receives one third of the available width.
class EventTypeTabs extends StatelessWidget {
  const EventTypeTabs({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final PlanType value;
  final ValueChanged<PlanType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Row(
        children: [
          _TypeTab(
            label: 'Task',
            selected: value == PlanType.task,
            onTap: () => onChanged(PlanType.task),
          ),
          _TypeTab(
            label: 'Buffer',
            selected: value == PlanType.buffer,
            onTap: () => onChanged(PlanType.buffer),
          ),
          _TypeTab(
            label: 'Fixed',
            selected: value == PlanType.fixed,
            onTap: () => onChanged(PlanType.fixed),
          ),
        ],
      ),
    );
  }
}

class _TypeTab extends StatelessWidget {
  const _TypeTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Material(
          color: selected
              ? Theme.of(context).colorScheme.secondaryContainer
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected
                      ? Theme.of(context).colorScheme.onSecondaryContainer
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
