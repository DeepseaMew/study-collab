import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class AppColors {
  // ── 60% — Base / Background ──────────────────────────────────────────────
  static const background = Color(0xFFFAFCFF);
  static const surface = Color(0xFFFFFFFF); // BG Frame

  // ── 30% — Secondary / Cards ──────────────────────────────────────────────
  static const secondary = Color(0xFFEDE9FE);
  static const secondaryHover = Color(0xFFE3DCFF);

  // ── 10% — Buttons / Accent (Purple) ──────────────────────────────────────
  static const accent = Color(0xFF7C3AED);
  static const accentHover = Color(0xFF6D28D9);

  // ── Neutrals ─────────────────────────────────────────────────────────────
  static const border = Color(0xFFD4D4D4); // Border Frame
  static const hint = Color(0xFF888888); // Hint Frame
  static const disabled = Color(0xFFDED8F7); // Disabled Frame
  static const text = Color(0xFF1A1A2E);

  // ── Semantic ─────────────────────────────────────────────────────────────
  static const error = Color(0xFFE53E3E);
  static const success = Color(0xFF38A169);
  static const warning = Color(0xFFD69E2E);
}

class AppTheme {
  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF1A1A2E),
        colorScheme: const ColorScheme.dark(
          primary: AppColors.accent,
          secondary: Color(0xFF2D2757),
          error: AppColors.error,
          surface: Color(0xFF232340),
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: Colors.white,
          outline: Color(0xFF3D3D5C),
        ),
        textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme).copyWith(
          displayLarge: GoogleFonts.poppins(
              fontSize: 40, fontWeight: FontWeight.w700, height: 1.2, color: Colors.white),
          displayMedium: GoogleFonts.poppins(
              fontSize: 24, fontWeight: FontWeight.w600, height: 1.35, color: Colors.white),
          displaySmall: GoogleFonts.poppins(
              fontSize: 18, fontWeight: FontWeight.w500, height: 1.4, color: Colors.white),
          titleLarge: GoogleFonts.poppins(
              fontSize: 16, fontWeight: FontWeight.w600, height: 1.5, color: Colors.white),
          bodyLarge: GoogleFonts.poppins(
              fontSize: 16, fontWeight: FontWeight.w400, height: 1.6, color: Colors.white),
          bodyMedium: GoogleFonts.poppins(
              fontSize: 14, fontWeight: FontWeight.w400, height: 1.6, color: Colors.white),
          labelLarge: GoogleFonts.poppins(
              fontSize: 14, fontWeight: FontWeight.w500, height: 1.4, color: Colors.white),
          labelSmall: GoogleFonts.poppins(
              fontSize: 10, fontWeight: FontWeight.w500, height: 1.4,
              color: const Color(0xFF9999AA)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            disabledBackgroundColor: AppColors.disabled,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.accent,
            minimumSize: const Size(double.infinity, 48),
            side: const BorderSide(color: AppColors.accent),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF2A2A4A),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF3D3D5C))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF3D3D5C))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.accent, width: 2)),
          errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.error)),
          hintStyle: GoogleFonts.poppins(color: const Color(0xFF888888), fontSize: 14),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF232340),
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFF3D3D5C))),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFF1A1A2E),
          elevation: 0,
          titleTextStyle: GoogleFonts.poppins(
              fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
      );

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.light(
          primary: AppColors.accent,
          secondary: AppColors.secondary,
          error: AppColors.error,
          surface: AppColors.surface, // Updated from white
          onPrimary: Colors.white,
          onSecondary: AppColors.text,
          onSurface: AppColors.text,
        ),
        textTheme: GoogleFonts.poppinsTextTheme().copyWith(
          displayLarge: GoogleFonts.poppins(
              fontSize: 40,
              fontWeight: FontWeight.w700,
              height: 1.2,
              color: AppColors.text),
          displayMedium: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              height: 1.35,
              color: AppColors.text),
          displaySmall: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              height: 1.4,
              color: AppColors.text),
          titleLarge: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1.5,
              color: AppColors.text),
          bodyLarge: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              height: 1.6,
              color: AppColors.text),
          bodyMedium: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              height: 1.6,
              color: AppColors.text),
          labelLarge: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.4,
              color: AppColors.text),
          labelSmall: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              height: 1.4,
              color: AppColors.hint),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 48),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            disabledBackgroundColor: AppColors.disabled,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.accent,
            minimumSize: const Size(double.infinity, 48),
            side: const BorderSide(color: AppColors.accent),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.accent, width: 2)),
          errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.error)),
          hintStyle: GoogleFonts.poppins(color: AppColors.hint, fontSize: 14),
        ),
        cardTheme: CardThemeData(
          color: AppColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.border)),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.background,
          elevation: 0,
          titleTextStyle: GoogleFonts.poppins(
              fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.text),
          iconTheme: const IconThemeData(color: AppColors.text),
        ),
      );
}
