import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typography styles for the app
class AppTextStyles {
  AppTextStyles._();

  // Display - Large headings (trip stats)
  static TextStyle displayLarge = GoogleFonts.roboto(
    fontSize: 57,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.25,
  );

  static TextStyle displayMedium = GoogleFonts.roboto(
    fontSize: 45,
    fontWeight: FontWeight.w400,
  );

  static TextStyle displaySmall = GoogleFonts.roboto(
    fontSize: 36,
    fontWeight: FontWeight.w400,
  );

  // Headline - Section titles
  static TextStyle headlineLarge = GoogleFonts.roboto(
    fontSize: 32,
    fontWeight: FontWeight.w400,
  );

  static TextStyle headlineMedium = GoogleFonts.roboto(
    fontSize: 28,
    fontWeight: FontWeight.w400,
  );

  static TextStyle headlineSmall = GoogleFonts.roboto(
    fontSize: 24,
    fontWeight: FontWeight.w400,
  );

  // Title - Card headers, dialog titles
  static TextStyle titleLarge = GoogleFonts.roboto(
    fontSize: 22,
    fontWeight: FontWeight.w400,
  );

  static TextStyle titleMedium = GoogleFonts.roboto(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.15,
  );

  static TextStyle titleSmall = GoogleFonts.roboto(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
  );

  // Body - Regular content
  static TextStyle bodyLarge = GoogleFonts.roboto(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.5,
  );

  static TextStyle bodyMedium = GoogleFonts.roboto(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.25,
  );

  static TextStyle bodySmall = GoogleFonts.roboto(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.4,
  );

  // Label - Small text, captions
  static TextStyle labelLarge = GoogleFonts.roboto(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
  );

  static TextStyle labelMedium = GoogleFonts.roboto(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
  );

  static TextStyle labelSmall = GoogleFonts.roboto(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
  );
}
