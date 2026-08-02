import '../domain/timeline.dart';

String displayBlockName(TimelineBlock block) => switch (block.id) {
      'morning' => 'Morning',
      'afternoon' => 'Afternoon',
      'evening' => 'Evening',
      _ => block.name,
    };
