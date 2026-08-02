import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:cadence/data/plan_repository.dart';
import 'package:cadence/domain/plan_item.dart';
import 'package:cadence/domain/timeline.dart';
import 'package:cadence/state/plan_controller.dart';
import 'package:cadence/ui/event_editor_sheet.dart';
import 'package:cadence/ui/plan_editor_page.dart';
import 'package:cadence/ui/time_wheel_picker.dart';
import 'package:cadence/ui/timeline_day_column.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('keyboard-safe editor sheets', () {
    testWidgets('event editor remains scrollable above a large keyboard inset',
        (tester) async {
      // Arrange
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 560);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showEventEditorSheet(
                    context,
                    date: DateTime(2026, 8, 2),
                    initialStart: 9 * 60,
                    initialEnd: 10 * 60,
                    mode: EventEditorMode.create,
                    onSave: (_) async {},
                  ),
                  child: const Text('Open editor'),
                ),
              ),
            ),
          ),
        ),
      );

      // Act
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('New event'), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.drag(
          find.byType(SingleChildScrollView), const Offset(0, -120));
      await tester.pumpAndSettle();
      expect(find.text('Save'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('numeric time picker remains scrollable above the keyboard',
        (tester) async {
      // Arrange
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 560);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showTimeWheelPicker(
                    context,
                    initialMinute: 9 * 60 + 30,
                  ),
                  child: const Text('Open time picker'),
                ),
              ),
            ),
          ),
        ),
      );

      // Act
      await tester.tap(find.text('Open time picker'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Choose time'), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
      expect(tester.takeException(), isNull);

      await tester.drag(
          find.byType(SingleChildScrollView), const Offset(0, -140));
      await tester.pumpAndSettle();
      expect(find.text('Done'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('keyboard insets do not change the timeline minute scale',
      (tester) async {
    // Arrange
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 700);
    addTearDown(tester.view.reset);

    const timeline = TimelineModel(
      blocks: [
        TimelineBlock(
          id: 'day',
          order: 0,
          name: 'Day',
          startMinute: 9 * 60,
          endMinute: 23 * 60,
        ),
      ],
      segments: [],
      gapLabels: {},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TimelineDayColumn(
              key: const Key('timeline'),
              date: DateTime(2026, 8, 2),
              timeline: timeline,
              events: const <PlanItem>[],
              onCreate: (_, __) {},
              onEdit: (_) {},
              onActions: (_) {},
            ),
          ),
        ),
      ),
    );
    final heightWithoutKeyboard =
        tester.getSize(find.byKey(const Key('timeline'))).height;

    // Act
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pump();
    final heightWithKeyboard =
        tester.getSize(find.byKey(const Key('timeline'))).height;

    // Assert
    expect(heightWithKeyboard, heightWithoutKeyboard);
    expect(heightWithKeyboard, 14 * 60 * .55 + 44);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'weekly plan grid and draft remain stable while the keyboard changes',
      (tester) async {
    // Arrange
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 560);
    tester.platformDispatcher.textScaleFactorTestValue = 1.2;
    addTearDown(tester.view.reset);
    addTearDown(
      tester.platformDispatcher.clearTextScaleFactorTestValue,
    );

    const timeline = TimelineModel(
      blocks: [
        TimelineBlock(
          id: 'day',
          order: 0,
          name: 'Day',
          startMinute: 9 * 60,
          endMinute: 23 * 60,
        ),
      ],
      segments: [],
      gapLabels: {},
    );
    final controller = PlanController(PlanRepository())
      ..timeline = timeline
      ..loading = false;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(home: PlanEditorPage()),
      ),
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    final mondayAxis = find.byKey(const ValueKey('template-day-axis-1'));
    final heightWithoutKeyboard = tester.getSize(mondayAxis).height;
    await tester.enterText(
      find.widgetWithText(TextField, 'Plan title (required)'),
      'Plan draft that must survive keyboard changes',
    );

    // Act
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    final heightWithKeyboard = tester.getSize(mondayAxis).height;

    // Assert
    expect(scaffold.resizeToAvoidBottomInset, isFalse);
    expect(heightWithKeyboard, heightWithoutKeyboard);
    expect(heightWithKeyboard, 14 * 60 * .46 + 44);
    expect(find.text('Plan draft that must survive keyboard changes'),
        findsOneWidget);
    expect(tester.takeException(), isNull);

    // Act
    await tester.tap(mondayAxis);
    await tester.pumpAndSettle();
    final editorScroll =
        find.byKey(const ValueKey('template-event-editor-scroll'));
    await tester.enterText(
      find.byType(TextFormField),
      'A long weekly template title that must remain intact',
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pumpAndSettle();

    // Assert
    expect(editorScroll, findsOneWidget);
    expect(
      find.text('A long weekly template title that must remain intact'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.drag(editorScroll, const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(find.text('Save event'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
