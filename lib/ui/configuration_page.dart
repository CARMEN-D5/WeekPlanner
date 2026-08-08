import 'package:flutter/material.dart';

class ConfigurationPage extends StatelessWidget {
  const ConfigurationPage({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
    body: SafeArea(child: Center(child: Padding(
      padding: EdgeInsets.all(28),
      child: Text('WeekPlanner needs a Supabase publishable key at build time. No secret or service-role key should be used.', textAlign: TextAlign.center),
    ))),
  );
}
