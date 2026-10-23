import 'package:flutter/material.dart';

/// Bharosa Color Palette - strictly strictly derived from Section 8.2 of Brief.md
class AppColors {
  AppColors._();

  /// Ink: Main text, icons, dark highlights
  static const Color ink = Color(0xFF14121F);

  /// Ultraviolet: Primary buttons, send button, sent bubbles, links, active tab
  static const Color ultraviolet = Color(0xFF6C4CFF);

  /// Lavender: Received bubbles, tags, selected states, input focus
  static const Color lavender = Color(0xFFD9D1FF);

  /// Lavender Light: Subtler background for input highlights and chips
  static const Color lavenderLight = Color(0xFFF2EFFF);

  /// Paper: App background
  static const Color paper = Color(0xFFF7F6F2);

  /// White: Cards, input fields, bottom sheets
  static const Color white = Color(0xFFFFFFFF);

  /// Grey 500: Secondary text, timestamps
  static const Color grey500 = Color(0xFF6B6880);

  /// Grey 200: Borders, dividers
  static const Color grey200 = Color(0xFFE6E3EE);

  /// Success: Delivered, verified status
  static const Color success = Color(0xFF1F9D6B);

  /// Warning: Cautions, disappearing timer
  static const Color warning = Color(0xFFE5A100);

  /// Error: Failures, security code mismatch
  static const Color error = Color(0xFFD93F4C);

  // Soft Shadows
  static List<BoxShadow> softCardShadow = [
    BoxShadow(
      color: ink.withValues(alpha: 0.04),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
    BoxShadow(
      color: ink.withValues(alpha: 0.02),
      blurRadius: 4,
      offset: const Offset(0, 1),
    ),
  ];

  static List<BoxShadow> elevatedShadow = [
    BoxShadow(
      color: ultraviolet.withValues(alpha: 0.15),
      blurRadius: 20,
      offset: const Offset(0, 6),
    ),
  ];
}
