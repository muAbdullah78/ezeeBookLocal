import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class AppTheme {
  AppTheme._();

  /// Theme for the active [locale].
  ///
  /// Urdu needs its own font: the default Android face (Roboto) has no
  /// Arabic-script glyphs, so switching the app to Urdu without this renders
  /// every label as empty boxes.
  static ThemeData forLocale(Locale locale) =>
      locale.languageCode == 'ur' ? urduTheme : lightTheme;

  /// The Urdu face, used for the app and the PDF receipt alike.
  ///
  /// Noto **Naskh** Arabic, not Nastaliq. Nastaliq is the more beautiful script
  /// and the one Urdu books are set in, but it is a calligraphic display face:
  /// at UI sizes its steep diagonal baselines read as heavy and cluttered, and
  /// its bold weight is heavier still. Naskh is a text face — horizontal
  /// baseline, even weight, meant to be read small — which is what a shop
  /// screen and a printed receipt both need.
  static const String _urduFontFamily = 'NotoNaskhArabic';

  /// Urdu variant of [lightTheme].
  ///
  /// Arabic script sits taller than Latin at the same point size, so it wants a
  /// little extra leading — but only a little. The generous allowance this
  /// previously used was there to stop Nastaliq's descenders clipping; applied
  /// to Naskh it just made every screen look loose and unfinished.
  static ThemeData get urduTheme {
    final base = lightTheme;
    // Naskh's own metrics are close to Latin, so it needs no size correction.
    TextTheme urdu(TextTheme t) =>
        t.apply(fontFamily: _urduFontFamily, heightDelta: 0.15);

    return base.copyWith(
      textTheme: urdu(base.textTheme),
      primaryTextTheme: urdu(base.primaryTextTheme),
      appBarTheme: base.appBarTheme.copyWith(
        titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(
          fontFamily: _urduFontFamily,
          fontSize: 19,
          height: 1.35,
        ),
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,

      // Colors
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
        surface: AppColors.background
      ),
      scaffoldBackgroundColor: AppColors.background,

      // AppBar
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.textOnPrimary,
        ),
      ),

      // Cards
      cardTheme: CardThemeData(
        color: AppColors.cardBackground,
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      // Buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textOnPrimary,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Input Fields
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.background,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        hintStyle: const TextStyle(color: AppColors.textHint),
      ),

      // Bottom Navigation Bar
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.cardBackground,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        selectedLabelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 12),
      ),

      // Floating Action Button
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        elevation: 4,
      ),

      // Divider
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),
    );
  }
}