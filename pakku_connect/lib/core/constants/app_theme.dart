import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Connecto Brand Palette
// Extracted from the official Connecto logo gradient:
//   Left arc  → Indigo-Blue  (#4F6EF7)
//   Center    → Teal         (#14B8A6)
//   Right arc → Pink/Magenta (#E91E8C)
// ---------------------------------------------------------------------------
class AppPalette {
  const AppPalette._();

  // Brand primaries — use for primary actions, highlights, branding elements.
  static const connectoBlue = Color(0xFF4F6EF7);
  static const connectoTeal = Color(0xFF14B8A6);
  static const connectoPink = Color(0xFFE91E8C);

  // Semantic
  static const successGreen = Color(0xFF22C55E);
  static const dangerRed    = Color(0xFFFF3B30);
  static const warningAmber = Color(0xFFF59E0B);

  // Dark-mode neutrals
  static const darkBg       = Color(0xFF0F0F12); // near-black canvas
  static const darkSurface  = Color(0xFF1C1C22); // card / panel surface
  static const darkSurface2 = Color(0xFF26262F); // elevated surface
  static const darkBorder   = Color(0xFF2E2E3A); // subtle separator

  // Light-mode neutrals
  static const lightBg      = Color(0xFFF4F4F8); // iOS/macOS-style light canvas
  static const lightSurface = Color(0xFFFFFFFF); // card / panel
  static const lightBorder  = Color(0xFFE4E4EF); // separator
}

// ---------------------------------------------------------------------------
// Custom theme extension — semantic tokens consumed by all widgets.
// ---------------------------------------------------------------------------
class CustomColors extends ThemeExtension<CustomColors> {
  final Color background;
  final Color surface;
  final Color surface2;
  final Color border;
  final Color primary;
  final Color accent;
  final Color secondary;
  final Color onPrimary;
  final Color onAccent;
  final Color danger;
  final Color success;
  final Color warning;
  /// Primary text colour (high emphasis).
  final Color textPrimary;
  /// Secondary text colour (medium emphasis — labels, hints).
  final Color textSecondary;
  /// Disabled / placeholder text (low emphasis).
  final Color textDisabled;

  const CustomColors({
    required this.background,
    required this.surface,
    required this.surface2,
    required this.border,
    required this.primary,
    required this.accent,
    required this.secondary,
    required this.onPrimary,
    required this.onAccent,
    required this.danger,
    required this.success,
    required this.warning,
    required this.textPrimary,
    required this.textSecondary,
    required this.textDisabled,
  });

  // ── Convenience getters ──────────────────────────────────────────────────
  /// Shorthand kept for backward compatibility with existing code that reads
  /// `colors.lightText` (maps to `textPrimary`).
  Color get lightText => textPrimary;

  // ── ThemeExtension boilerplate ───────────────────────────────────────────
  @override
  CustomColors copyWith({
    Color? background,
    Color? surface,
    Color? surface2,
    Color? border,
    Color? primary,
    Color? accent,
    Color? secondary,
    Color? onPrimary,
    Color? onAccent,
    Color? danger,
    Color? success,
    Color? warning,
    Color? textPrimary,
    Color? textSecondary,
    Color? textDisabled,
  }) {
    return CustomColors(
      background:    background    ?? this.background,
      surface:       surface       ?? this.surface,
      surface2:      surface2      ?? this.surface2,
      border:        border        ?? this.border,
      primary:       primary       ?? this.primary,
      accent:        accent        ?? this.accent,
      secondary:     secondary     ?? this.secondary,
      onPrimary:     onPrimary     ?? this.onPrimary,
      onAccent:      onAccent      ?? this.onAccent,
      danger:        danger        ?? this.danger,
      success:       success       ?? this.success,
      warning:       warning       ?? this.warning,
      textPrimary:   textPrimary   ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textDisabled:  textDisabled  ?? this.textDisabled,
    );
  }

  @override
  CustomColors lerp(ThemeExtension<CustomColors>? other, double t) {
    if (other is! CustomColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return CustomColors(
      background:    l(background,    other.background),
      surface:       l(surface,       other.surface),
      surface2:      l(surface2,      other.surface2),
      border:        l(border,        other.border),
      primary:       l(primary,       other.primary),
      accent:        l(accent,        other.accent),
      secondary:     l(secondary,     other.secondary),
      onPrimary:     l(onPrimary,     other.onPrimary),
      onAccent:      l(onAccent,      other.onAccent),
      danger:        l(danger,        other.danger),
      success:       l(success,       other.success),
      warning:       l(warning,       other.warning),
      textPrimary:   l(textPrimary,   other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textDisabled:  l(textDisabled,  other.textDisabled),
    );
  }

  // ── Pre-built token sets ─────────────────────────────────────────────────
  static const dark = CustomColors(
    background:    AppPalette.darkBg,
    surface:       AppPalette.darkSurface,
    surface2:      AppPalette.darkSurface2,
    border:        AppPalette.darkBorder,
    primary:       AppPalette.connectoBlue,
    accent:        AppPalette.connectoTeal,
    secondary:     AppPalette.connectoPink,
    onPrimary:     Colors.white,
    onAccent:      Colors.white,
    danger:        AppPalette.dangerRed,
    success:       AppPalette.successGreen,
    warning:       AppPalette.warningAmber,
    textPrimary:   Color(0xFFECECF0),
    textSecondary: Color(0xFF9898A8),
    textDisabled:  Color(0xFF55555F),
  );

  static const light = CustomColors(
    background:    AppPalette.lightBg,
    surface:       AppPalette.lightSurface,
    surface2:      Color(0xFFF9F9FC),
    border:        AppPalette.lightBorder,
    primary:       AppPalette.connectoBlue,
    accent:        AppPalette.connectoTeal,
    secondary:     AppPalette.connectoPink,
    onPrimary:     Colors.white,
    onAccent:      Colors.white,
    danger:        AppPalette.dangerRed,
    success:       AppPalette.successGreen,
    warning:       AppPalette.warningAmber,
    textPrimary:   Color(0xFF111118),
    textSecondary: Color(0xFF5C5C6E),
    textDisabled:  Color(0xFFAAAAAF),
  );
}

// ---------------------------------------------------------------------------
// Theme builder — wires Material 3 ColorScheme from the Connecto palette.
// ---------------------------------------------------------------------------
ThemeData buildAppTheme({bool isDark = true}) {
  final colors   = isDark ? CustomColors.dark  : CustomColors.light;
  final scheme   = isDark ? _darkScheme        : _lightScheme;

  final base = isDark ? ThemeData.dark() : ThemeData.light();

  return base.copyWith(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: colors.background,
    primaryColor: colors.primary,

    // AppBar
    appBarTheme: AppBarTheme(
      backgroundColor: colors.surface,
      foregroundColor: colors.textPrimary,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
    ),

    // Cards
    cardTheme: CardThemeData(
      color: colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.border, width: 1),
      ),
    ),

    // Chips
    chipTheme: ChipThemeData(
      backgroundColor: colors.surface2,
      selectedColor: colors.primary.withAlpha(30),
      side: BorderSide(color: colors.border),
      labelStyle: TextStyle(color: colors.textPrimary),
    ),

    // Divider
    dividerTheme: DividerThemeData(
      color: colors.border,
      thickness: 1,
      space: 1,
    ),

    // NavigationBar (bottom nav)
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: colors.primary.withAlpha(26),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final active = states.contains(WidgetState.selected);
        return IconThemeData(
          color: active ? colors.primary : colors.textSecondary,
          size: 22,
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final active = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 11,
          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          color: active ? colors.primary : colors.textSecondary,
        );
      }),
    ),

    // Elevated buttons — primary brand blue
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),

    // Outlined buttons
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.primary,
        side: BorderSide(color: colors.primary.withAlpha(180)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),

    // Text buttons
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colors.primary,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),

    // Input decoration
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surface2,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colors.primary, width: 1.5),
      ),
      hintStyle: TextStyle(color: colors.textDisabled),
      labelStyle: TextStyle(color: colors.textSecondary),
    ),

    // Snack bars
    snackBarTheme: SnackBarThemeData(
      backgroundColor: isDark ? colors.surface2 : const Color(0xFF1C1C22),
      contentTextStyle: const TextStyle(color: Color(0xFFECECF0)),
      actionTextColor: AppPalette.connectoTeal,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),

    // Dialog
    dialogTheme: DialogThemeData(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.border),
      ),
    ),

    // List tiles
    listTileTheme: ListTileThemeData(
      tileColor: Colors.transparent,
      textColor: colors.textPrimary,
      iconColor: colors.textSecondary,
    ),

    // Checkbox
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return colors.primary;
        return Colors.transparent;
      }),
      checkColor: WidgetStateProperty.all(Colors.white),
      side: BorderSide(color: colors.border, width: 1.5),
    ),

    // Switch
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return colors.primary;
        return colors.textDisabled;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return colors.primary.withAlpha(80);
        return colors.border;
      }),
    ),

    // Progress indicator
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colors.primary,
      linearTrackColor: colors.border,
    ),

    extensions: [colors],
  );
}

// ---------------------------------------------------------------------------
// Material 3 ColorScheme definitions
// ---------------------------------------------------------------------------
const _darkScheme = ColorScheme(
  brightness:       Brightness.dark,
  primary:          AppPalette.connectoBlue,
  onPrimary:        Colors.white,
  primaryContainer: Color(0xFF1E2D6B),
  onPrimaryContainer: Color(0xFFB8C8FF),
  secondary:        AppPalette.connectoTeal,
  onSecondary:      Colors.white,
  secondaryContainer: Color(0xFF0D3D38),
  onSecondaryContainer: Color(0xFFA0EFE8),
  tertiary:         AppPalette.connectoPink,
  onTertiary:       Colors.white,
  tertiaryContainer: Color(0xFF5A0030),
  onTertiaryContainer: Color(0xFFFFB3D6),
  error:            AppPalette.dangerRed,
  onError:          Colors.white,
  errorContainer:   Color(0xFF4D0000),
  onErrorContainer: Color(0xFFFFB4AB),
  surface:          AppPalette.darkSurface,
  onSurface:        Color(0xFFECECF0),
  onSurfaceVariant: Color(0xFF9898A8),
  outline:          AppPalette.darkBorder,
  outlineVariant:   Color(0xFF2A2A35),
  shadow:           Colors.black,
  scrim:            Colors.black,
  inverseSurface:   Color(0xFFECECF0),
  onInverseSurface: Color(0xFF0F0F12),
  inversePrimary:   AppPalette.connectoBlue,
  surfaceTint:      Colors.transparent,
);

const _lightScheme = ColorScheme(
  brightness:       Brightness.light,
  primary:          AppPalette.connectoBlue,
  onPrimary:        Colors.white,
  primaryContainer: Color(0xFFDDE4FF),
  onPrimaryContainer: Color(0xFF0A1B5E),
  secondary:        AppPalette.connectoTeal,
  onSecondary:      Colors.white,
  secondaryContainer: Color(0xFFCCF5F0),
  onSecondaryContainer: Color(0xFF003733),
  tertiary:         AppPalette.connectoPink,
  onTertiary:       Colors.white,
  tertiaryContainer: Color(0xFFFFD9EA),
  onTertiaryContainer: Color(0xFF3A0020),
  error:            AppPalette.dangerRed,
  onError:          Colors.white,
  errorContainer:   Color(0xFFFFDAD6),
  onErrorContainer: Color(0xFF410002),
  surface:          AppPalette.lightSurface,
  onSurface:        Color(0xFF111118),
  onSurfaceVariant: Color(0xFF5C5C6E),
  outline:          AppPalette.lightBorder,
  outlineVariant:   Color(0xFFD0D0DC),
  shadow:           Colors.black,
  scrim:            Colors.black,
  inverseSurface:   Color(0xFF1C1C22),
  onInverseSurface: Color(0xFFF4F4F8),
  inversePrimary:   Color(0xFFB8C8FF),
  surfaceTint:      Colors.transparent,
);
