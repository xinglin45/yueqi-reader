import 'package:flutter/material.dart';

ThemeData paperTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final text = Color(dark ? 0xFFE7E0D5 : 0xFF2D2925);
  final accent = Color(dark ? 0xFFD5A184 : 0xFF9F654B);
  final paper = Color(dark ? 0xFF242321 : 0xFFFBF9F5);
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness)
      .copyWith(
        primary: accent,
        onPrimary: dark ? const Color(0xFF242321) : Colors.white,
        surface: paper,
        onSurface: text,
        onSurfaceVariant: Color(dark ? 0xFFB3AAA0 : 0xFF6D6760),
        surfaceContainerLow: Color(dark ? 0xFF1E1E1D : 0xFFEEECE7),
        surfaceContainer: Color(dark ? 0xFF282724 : 0xFFF5F3EF),
        surfaceContainerHigh: Color(dark ? 0xFF3D3933 : 0xFFDED9D1),
        surfaceContainerHighest: Color(dark ? 0xFF302E2B : 0xFFFFFEFB),
        outlineVariant: Color(dark ? 0xFF48443E : 0xFFDEDAD3),
      );
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'PingFang SC',
    fontFamilyFallback: const ['.AppleSystemUIFont', 'sans-serif'],
    colorScheme: scheme,
    brightness: brightness,
  );
  return base.copyWith(
    scaffoldBackgroundColor: paper,
    textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    iconTheme: IconThemeData(color: text, size: 21),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 400),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        textStyle: const TextStyle(fontWeight: FontWeight.w400),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
