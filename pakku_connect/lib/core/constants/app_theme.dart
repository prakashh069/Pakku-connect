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

  const CustomColors({
    required this.background,
    required this.surface,
    required this.accent,
    required this.onAccent,
    required this.danger,
    required this.success,
    required this.lightText,
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
  }) {
    return CustomColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      danger: danger ?? this.danger,
      success: success ?? this.success,
      lightText: lightText ?? this.lightText,
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
  );

  static const light = CustomColors(
    background: Color(0xFFF2F2F6), // iOS/OneUI light background
    surface: Colors.white,
    accent: AppPalette.vibrantTeal,
    onAccent: Colors.white,
    danger: AppPalette.dangerRed,
    success: AppPalette.successGreen,
    lightText: Color(0xFF1C1C1E), // Dark text for light mode
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
        scaffoldBackgroundColor: const Color(0xFFF2F2F6),
        primaryColor: AppPalette.vibrantTeal,
        extensions: const [CustomColors.light],
      );
}
