import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../domain/plan_item.dart';
import '../state/plan_controller.dart';
import 'about_page.dart';
import 'plan_editor_page.dart';
import 'timeline_editor_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool reminder = false;
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PlanController>();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(children: [
          Text('Settings', style: Theme.of(context).textTheme.headlineMedium),
          const Spacer(),
          FilledButton.icon(
              onPressed: () => _openEditor(context),
              icon: const Icon(Icons.add),
              label: const Text('New plan'))
        ]),
        const SizedBox(height: 20),
        Text('Weekly plans', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        if (controller.plans.isEmpty)
          const Card(
              child: ListTile(
                  leading: Icon(Icons.calendar_month_outlined),
                  title: Text('No weekly plans yet'),
                  subtitle: Text(
                      'Create a plan to generate daily instances automatically.'))),
        ...controller.plans.map((plan) => Card(
            child: ListTile(
                leading: const Icon(Icons.event_note_outlined),
                title: Text(plan.title),
                subtitle: Text(
                    '${DateFormat('yyyy/M/d').format(plan.startDate)} – ${DateFormat('yyyy/M/d').format(plan.endDate)}${plan.repeatsWeekly ? ' · Repeats weekly' : ''}'),
                trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete plan',
                    onPressed: () => _deletePlan(context, plan)),
                onTap: () => _openEditor(context, plan: plan)))),
        const SizedBox(height: 16),
        Card(
            child: ListTile(
                leading: const Icon(Icons.schedule),
                title: const Text('Timeline and gaps'),
                subtitle: const Text(
                    'Customize the three primary blocks and their gaps'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const TimelineEditorPage())))),
        SwitchListTile(
            value: reminder,
            onChanged: (value) => setState(() => reminder = value),
            title: const Text('Task reminders'),
            subtitle: Text(
                reminder ? 'Reminders are enabled' : 'Reminders are disabled')),
        const ListTile(
          leading: Icon(Icons.brightness_auto_outlined),
          title: Text('Appearance'),
          subtitle: Text('Follows your device light or dark theme'),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About WeekPlanner'),
            subtitle: const Text('Version and brand information'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AboutPage()),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openEditor(BuildContext context, {Plan? plan}) async {
    await Navigator.push<void>(
        context, MaterialPageRoute(builder: (_) => PlanEditorPage(plan: plan)));
    if (context.mounted) context.read<PlanController>().load();
  }

  Future<void> _deletePlan(BuildContext context, Plan plan) async {
    final delete = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
                title: const Text('Delete weekly plan?'),
                content: Text(
                    'The template and all generated instances for “${plan.title}” will be deleted.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Delete'))
                ]));
    if (delete == true && context.mounted)
      await context.read<PlanController>().deletePlan(plan.id);
  }
}
