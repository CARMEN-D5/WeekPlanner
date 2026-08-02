import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'data/plan_repository.dart';
import 'state/app_preferences.dart';
import 'state/plan_controller.dart';
import 'ui/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _enableDebugErrorLogging();
  Intl.defaultLocale = 'en_US';
  await initializeDateFormatting('en_US');
  // This object intentionally outlives every page, tab, loading state and
  // dialog. Keeping the provider above MaterialApp prevents descendants from
  // retaining a dependency on a provider that is being replaced mid-frame.
  final planController = PlanController(PlanRepository());
  planController.loadDay(DateTime.now());
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppPreferences(),
      child: ChangeNotifierProvider.value(
        value: planController,
        child: const CadenceApp(),
      ),
    ),
  );
}

/// Keeps Flutter's normal red error screen intact while also sending the full
/// framework stack to Android Logcat. This is debug-only and deliberately does
/// not mark an error as handled or replace the framework error widget.
void _enableDebugErrorLogging() {
  assert(() {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('Cadence framework error: ${details.exceptionAsString()}');
      debugPrintStack(stackTrace: details.stack);
    };
    return true;
  }());
}

class CadenceApp extends StatelessWidget {
  const CadenceApp({super.key});

  @override
  Widget build(BuildContext context) {
    final preferences = context.watch<AppPreferences>();
    return MaterialApp(
      title: 'Cadence',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8C9CAB),
          brightness: Brightness.light,
          surface: const Color(0xFFFFFDFC),
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F4EF),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF7F4EF),
          foregroundColor: Color(0xFF45413D),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFFFFFDFC),
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFF0ECE7)),
          ),
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: Color(0xFFFFFDFC),
          surfaceTintColor: Colors.transparent,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFFFFDFC),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFCBC5BD)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFCBC5BD)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: Color(0xFFA8B6C6),
              width: 1.5,
            ),
          ),
        ),
        switchTheme: SwitchThemeData(
          trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? const Color(0xFFA8B6C6)
                : const Color(0xFFDDD7D0),
          ),
          thumbColor: const WidgetStatePropertyAll(Color(0xFFFFFDFC)),
        ),
        checkboxTheme: CheckboxThemeData(
          fillColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? const Color(0xFFAAB9A3)
                : Colors.transparent,
          ),
          side: const BorderSide(color: Color(0xFF88817A)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF788A94),
            foregroundColor: const Color(0xFFFFFDFC),
            minimumSize: const Size(0, 46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Color(0xFFFFFDFC),
          indicatorColor: Color(0xFFDDE5E8),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              color: states.contains(WidgetState.selected)
                  ? const Color(0xFF4E5A60)
                  : const Color(0xFF817A73),
              fontWeight: FontWeight.w500,
            ),
          ),
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? const Color(0xFF4E5A60)
                  : const Color(0xFF817A73),
            ),
          ),
        ),
      ),
      darkTheme: _cadenceDarkTheme(),
      themeMode: preferences.themeMode,
      home: const AppShell(),
    );
  }
}

ThemeData _cadenceDarkTheme() {
  const background = Color(0xFF17191B);
  const surface = Color(0xFF232629);
  const border = Color(0xFF3B4145);
  const foreground = Color(0xFFE9E6E1);
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF9EADBA),
    brightness: Brightness.dark,
    surface: surface,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    appBarTheme: const AppBarTheme(
      backgroundColor: background,
      foregroundColor: foreground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
        side: BorderSide(color: border),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: Color(0xFFA8B6C6), width: 1.5),
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: Color(0xFF3C4A53),
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(color: foreground, fontWeight: FontWeight.w500),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF788A94),
        foregroundColor: foreground,
        minimumSize: const Size(0, 46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}
