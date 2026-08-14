import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'tokens.dart';

/// Светлая и тёмная темы Traktor из токенов брендбука. Обе обязательны с v1
/// (ТЗ §1.7). Приложение задаёт тему один раз в корне; секции не инвертируются.
class TkTheme {
  TkTheme._();

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final isDark = b == Brightness.dark;
    final primary = isDark ? TkColors.primaryDark : TkColors.primary;
    final bg = isDark ? TkColors.bgDark : TkColors.bgLight;
    final surface = isDark ? TkColors.surfaceDark : TkColors.surfaceLight;
    final text = isDark ? TkColors.textDark : TkColors.textLight;
    final text2 = isDark ? TkColors.text2Dark : TkColors.text2Light;
    final border = isDark ? TkColors.borderDark : TkColors.borderLight;

    final scheme = ColorScheme(
      brightness: b,
      primary: primary,
      onPrimary: Colors.white,
      secondary: primary,
      onSecondary: Colors.white,
      error: TkColors.error,
      onError: Colors.white,
      surface: surface,
      onSurface: text,
      surfaceContainerHighest: isDark ? TkColors.surface2Dark : TkColors.surface2Light,
      outline: border,
    );

    // Inter — латиница/кириллица; Noto Sans Armenian — армянский фолбэк.
    final base = GoogleFonts.interTextTheme(
      isDark ? Typography.material2021().white : Typography.material2021().black,
    );
    final textTheme = base.copyWith(
      displaySmall: TkText.h1.copyWith(color: text),
      headlineSmall: TkText.h2.copyWith(color: text),
      titleMedium: TkText.h3.copyWith(color: text),
      bodyMedium: TkText.body.copyWith(color: text),
      bodySmall: TkText.caption.copyWith(color: text2),
      labelLarge: TkText.body.copyWith(fontWeight: FontWeight.w600),
    ).apply(fontFamilyFallback: const ['Noto Sans Armenian']);

    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      textTheme: textTheme,
      dividerColor: border,
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: TkRadius.cardR),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(50),
          shape: const RoundedRectangleBorder(borderRadius: TkRadius.buttonR),
          textStyle: TkText.body.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size.fromHeight(50),
          side: BorderSide(color: primary, width: 1.5),
          shape: const RoundedRectangleBorder(borderRadius: TkRadius.buttonR),
          textStyle: TkText.body.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: border, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: border, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
        hintStyle: TkText.body.copyWith(color: text2),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: primary.withValues(alpha: 0.12),
        labelTextStyle: WidgetStatePropertyAll(
          TkText.caption.copyWith(fontSize: 11, fontWeight: FontWeight.w500),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? primary : text2),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        side: BorderSide(color: border),
        labelStyle: TkText.caption.copyWith(color: text),
        shape: const StadiumBorder(),
      ),
    );
  }
}
