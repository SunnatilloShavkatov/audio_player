import 'package:material_ui/material_ui.dart';

/// Seed colour the light and dark colour schemes of the demo are generated from.
const Color demoSeedColor = Color(0xFF5B5BD6);

/// Builds the Material 3 theme shared by every demo screen.
ThemeData buildDemoTheme(Brightness brightness) {
  final colorScheme = ColorScheme.fromSeed(seedColor: demoSeedColor, brightness: brightness);
  final base = ThemeData(colorScheme: colorScheme, brightness: brightness);
  final textTheme = base.textTheme;
  return base.copyWith(
    scaffoldBackgroundColor: colorScheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 1,
      centerTitle: false,
      // The base text theme only carries colours until MaterialApp localizes it, so the size is set here.
      titleTextStyle: base.typography.englishLike.titleLarge
          ?.merge(textTheme.titleLarge)
          .copyWith(fontWeight: FontWeight.w600, color: colorScheme.onSurface),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
    ),
    sliderTheme: const SliderThemeData(trackHeight: 4),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(showDragHandle: true),
    textTheme: textTheme.copyWith(
      headlineSmall: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
  );
}

/// [MaterialApp] with the demo's light and dark themes. The theme follows the system setting.
class DemoApp extends StatelessWidget {
  const new({super.key, required this.title, required this.home, this.scaffoldMessengerKey});

  /// Title used by the operating system's task switcher.
  final String title;

  /// The screen to show.
  final Widget home;

  /// Optional key for showing snack bars from outside the widget tree.
  final GlobalKey<ScaffoldMessengerState>? scaffoldMessengerKey;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: title,
    scaffoldMessengerKey: scaffoldMessengerKey,
    theme: buildDemoTheme(Brightness.light),
    darkTheme: buildDemoTheme(Brightness.dark),
    home: home,
  );
}
