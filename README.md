# Cadence

Cadence is a local-first Flutter application for turning a weekly plan into a practical daily schedule. It combines reusable weekly templates, concrete task instances, configurable timeline blocks, completion tracking, and plan history in one Android-focused app.

## Features

- Create date-bounded plans with optional weekly recurrence.
- Build reusable templates for tasks, fixed commitments, and buffer time.
- Materialize templates as daily task instances while preserving completed history.
- View the same schedule by day, week, or month.
- Configure primary timeline blocks and the gaps between them.
- Render events continuously across blocks and gaps.
- Move, complete, undo, and compensate eligible unfinished items.
- Review completion totals, unfinished-title groups, and weekly trends.
- Switch between light and dark themes.
- Store all application data locally in SQLite.

## Architecture

Cadence separates planning data from its calendar presentation.

### Planning lifecycle

```text
Plan -> WeekTemplate -> TaskInstance
```

- `Plan` defines a title, active date range, recurrence behavior, and lifecycle state.
- `WeekTemplate` defines a reusable weekday event using start and end minutes.
- `TaskInstance` is the persisted occurrence of a template. In Dart, instances are represented by `PlanItem` and stored in the `task_instances` SQLite table.

Completed instances are retained when a plan is edited. Pending future instances can be regenerated from the updated templates.

### Timeline model

```text
Timeline
|- TimelineBlock (primary named period)
|- TimelineSegment (editable subdivision of a block)
`- Gap (derived space between consecutive blocks)
```

Events store only their start and end minutes; they are not assigned to a morning, afternoon, or evening bucket. The shared renderer overlays events onto the timeline and keeps an event that crosses a block or gap as one continuous card. A `Gap` is calculated whenever the next ordered block starts after the previous block ends.

### Application layers

- `lib/domain`: planning, history, timeline, rendering, and conflict rules.
- `lib/data`: SQLite schema, persistence, and task-instance generation.
- `lib/state`: application controllers and presentation preferences.
- `lib/ui`: Material 3 pages, editors, dialogs, and timeline widgets.

## Technology Stack

- Flutter and Dart
- Material 3
- Provider for state management
- SQLite through `sqflite`
- `intl` for date formatting
- `uuid` for identifiers
- `flutter_test` for automated tests

## Requirements

- Flutter SDK with Dart `>=3.3.0 <4.0.0`
- Android SDK and Android platform tools
- JDK 17 for Android builds
- An Android emulator or physical device for interactive use

Run `flutter doctor` to confirm that the local Flutter and Android toolchains are configured.

## Run Locally

```powershell
flutter pub get
flutter run
```

Select an available Android device when Flutter prompts for a target. The core unit tests do not require an emulator or physical device.

## Tests

Format the project and run the complete automated test suite with:

```powershell
dart format --output=none --set-exit-if-changed lib test tool
flutter test
```

The tests cover timeline rendering and gaps, event conflict boundaries, title normalization, plan lifecycle states, history statistics and grouping, and theme preference notifications.

## Build an APK

Build a release APK with:

```powershell
flutter pub get
flutter build apk --release
```

The generated package is written to:

```text
build/app/outputs/flutter-apk/app-release.apk
```

For smaller architecture-specific APKs, run `flutter build apk --release --split-per-abi`.

## Project Structure

```text
WeekPlanner/
|- android/                 Android host project and Gradle configuration
|- lib/
|  |- data/                 SQLite repository and instance generation
|  |- domain/               Plans, history, timelines, and rendering rules
|  |- state/                Controllers and app preferences
|  |- ui/                   Screens and reusable widgets
|  `- main.dart             Application entry point
|- test/                    Automated unit and Flutter tests
|- tool/                    Standalone development checks
|- analysis_options.yaml    Dart analyzer configuration
`- pubspec.yaml             Package metadata and dependencies
```

## Current Status

Cadence is an early-stage (`0.1.0`) local-first application. Core plan editing, recurrence generation, timeline customization, daily/weekly/monthly views, completion and compensation flows, history summaries, and Android build configuration are implemented. The project currently targets local development and Android use; distribution metadata and platform-specific release setup are not yet included.

## License

This repository does not currently include a license file. Until a license is added, the source code is not granted for reuse, modification, or redistribution. Add an OSI-approved license before accepting external contributions or distributing the project as open source.
