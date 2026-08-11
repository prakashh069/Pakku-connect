import 'package:flutter/material.dart';

class AppPalette {
  static const quantumCharcoal = Color(0xFF161B22);
  static const vibrantTeal = Color(0xFF14B8A6);
  static const interfaceGray = Color(0xFF30363D);
  static const lightText = Color(0xFFCED5DE);
  static const successGreen = Color(0xFF22C55E);
  static const dangerRed = Color(0xFFFF3B30);
}

class CustomColors extends ThemeExtension<CustomColors> {
  final Color background;
  final Color surface;
  final Color accent;
  final Color onAccent;
  final Color danger;
  final Color success;
  final Color lightText;
  final Color textMain;
  final Color textSecondary;
  final Color border;
  final Color borderStrong;

  const CustomColors({
    required this.background,
    required this.surface,
    required this.accent,
    required this.onAccent,
    required this.danger,
    required this.success,
    required this.lightText,
    required this.textMain,
    required this.textSecondary,
    required this.border,
    required this.borderStrong,
  });

  @override
  CustomColors copyWith({
    Color? background,
    Color? surface,
    Color? accent,
    Color? onAccent,
    Color? danger,
    Color? success,
    Color? lightText,
    Color? textMain,
    Color? textSecondary,
    Color? border,
    Color? borderStrong,
  }) {
    return CustomColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      danger: danger ?? this.danger,
      success: success ?? this.success,
      lightText: lightText ?? this.lightText,
      textMain: textMain ?? this.textMain,
      textSecondary: textSecondary ?? this.textSecondary,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
    );
  }

  @override
  CustomColors lerp(ThemeExtension<CustomColors>? other, double t) {
    if (other is! CustomColors) return this;
    return CustomColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      success: Color.lerp(success, other.success, t)!,
      lightText: Color.lerp(lightText, other.lightText, t)!,
      textMain: Color.lerp(textMain, other.textMain, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
    );
  }

  static const dark = CustomColors(
    background: AppPalette.quantumCharcoal,
    surface: AppPalette.interfaceGray,
    accent: AppPalette.vibrantTeal,
    onAccent: Colors.white,
    danger: AppPalette.dangerRed,
    success: AppPalette.successGreen,
    lightText: AppPalette.lightText,
    textMain: Colors.white,
    textSecondary: Colors.white70,
    border: Colors.white12,
    borderStrong: Colors.white30,
  );

  static const light = CustomColors(
    background: Color(0xFFF9F6F0), // WhatsApp web light background
    surface: Colors.white,
    accent: AppPalette.vibrantTeal,
    onAccent: Colors.white,
    danger: AppPalette.dangerRed,
    success: AppPalette.successGreen,
    lightText: Color(0xFF1C1C1E),
    textMain: Colors.black87,
    textSecondary: Colors.black54,
    border: Colors.black12,
    borderStrong: Colors.black38,
  );
}

ThemeData buildAppTheme({bool isDark = true}) {
  return isDark
    ? ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppPalette.quantumCharcoal,
        primaryColor: AppPalette.vibrantTeal,
        extensions: const [CustomColors.dark],
      )
    : ThemeData.light().copyWith(
        scaffoldBackgroundColor: const Color(0xFFF9F6F0),
        primaryColor: AppPalette.vibrantTeal,
        extensions: const [CustomColors.light],
      );
}
