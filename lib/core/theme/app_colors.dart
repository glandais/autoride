import 'package:flutter/material.dart';

/// App color palette for light and dark themes
class AppColors {
  AppColors._();

  // Primary Colors
  static const Color primaryLight = Color(0xFF0277BD); // Light Blue 800
  static const Color primaryDark = Color(0xFF29B6F6); // Light Blue 400

  static const Color secondaryLight = Color(0xFFFF6F00); // Orange 900
  static const Color secondaryDark = Color(0xFFFFB74D); // Orange 300

  // Background Colors
  static const Color backgroundLight = Color(0xFFFAFAFA);
  static const Color backgroundDark = Color(0xFF121212);

  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF1E1E1E);

  // Text Colors
  static const Color textPrimaryLight = Color(0xFF212121);
  static const Color textPrimaryDark = Color(0xFFE0E0E0);

  static const Color textSecondaryLight = Color(0xFF757575);
  static const Color textSecondaryDark = Color(0xFFBDBDBD);

  // Semantic Colors
  static const Color success = Color(0xFF4CAF50); // Green 500
  static const Color warning = Color(0xFFFFA726); // Orange 400
  static const Color error = Color(0xFFE53935); // Red 600
  static const Color info = Color(0xFF42A5F5); // Blue 400

  // Trip Status Colors
  static const Color tripActive = Color(0xFF4CAF50); // Green - active trip
  static const Color tripPaused = Color(0xFFFFA726); // Orange - paused
  static const Color tripDetecting = Color(0xFF42A5F5); // Blue - detecting

  // Gradient Colors (for stats displays)
  static const List<Color> speedGradient = [
    Color(0xFF0277BD),
    Color(0xFF29B6F6),
  ];

  static const List<Color> distanceGradient = [
    Color(0xFFFF6F00),
    Color(0xFFFFB74D),
  ];
}
