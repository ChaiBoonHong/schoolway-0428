import 'package:flutter/material.dart';

abstract final class SchoolWayTheme {
  static const primary = Color(0xFF0077B6);
  static const navy = Color(0xFF03045E);
  static const accent = Color(0xFF00B4D8);
  static const background = Color(0xFFCAF0F8);
  static const surface = Colors.white;
  static const border = Color(0xFF6BA8C7);
  static const text = Color(0xFF111827);
  static const muted = Color(0xFF64748B);
  static const success = Color(0xFF2E7D32);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFD32F2F);
  static const transparent = Colors.transparent;
  static const surface30 = Color(0x4DFFFFFF);
  static const surface70 = Color(0xB3FFFFFF);
  static const text12 = Color(0x1F000000);
  static const text26 = Color(0x42000000);
  static const text87 = Color(0xDE000000);
  static const info = Color(0xFF2196F3);
  static const successBright = Color(0xFF4CAF50);
  static const successDark = Color(0xFF0B8A6A);
  static const warningDark = Color(0xFFF57C00);
  static const dangerDark = Color(0xFFB71C1C);
  static const purple = Color(0xFF6A1B9A);
  static const purpleDark = Color(0xFF4A148C);
  static const violet = Color(0xFF7C3AED);
  static const violetDark = Color(0xFF5B21B6);
  static const pink = Color(0xFFE91E63);
  static const googleBlue = Color(0xFF4285F4);
  static const googleRed = Color(0xFFEA4335);
  static const googleYellow = Color(0xFFFBBC05);
  static const googleGreen = Color(0xFF34A853);
  static const textStrong = Color(0xFF1F2937);
  static const mutedStrong = Color(0xFF334155);
  static const mutedDark = Color(0xFF757575);
  static const disabled = Color(0xFF999999);
  static const neutral600 = Color(0xFF6B7280);
  static const blueGrey = Color(0xFF546E7A);
  static const borderStrong = Color(0xFF0077B6);
  static const borderSubtle = Color(0xFF90C2DE);
  static const neutralBorder = Color(0xFFD1D5DB);
  static const neutralDivider = Color(0xFFCCCCCC);
  static const neutralDisabled = Color(0xFF9E9E9E);
  static const neutralLabel = Color(0xFF8A8A8A);
  static const neutralSurface = Color(0xFFF5F5F5);
  static const googleSurface = Color(0xFFF8F9FA);
  static const surfaceSubtle = Color(0xFFF8FAFC);
  static const infoSurface = Color(0xFFE3F2FD);
  static const dangerSurface = Color(0xFFFFEBEE);
  static const purpleSurface = Color(0xFFF3E8FF);
  static const subtleBlueSurface = Color(0xFFF0F7FA);
  static const subtleCyanSurface = Color(0xFFEAF4F7);
  static const scrim = Color(0x88000000);
  static const darkBackground = Color(0xFF071521);
  static const darkSurface = Color(0xFF102636);
  static const darkBorder = Color(0xFF3B6782);
  static const darkText = Color(0xFFEAF7FC);
  static const darkMuted = Color(0xFFA8C2CE);
  static const radius = 12.0;
  static const radiusLarge = 20.0;
  static const spacing4 = 4.0;
  static const spacing8 = 8.0;
  static const spacing12 = 12.0;
  static const spacing16 = 16.0;
  static const spacing24 = 24.0;
  static const spacing32 = 32.0;
  static const contentMaxWidth = 1280.0;
  static const compactBreakpoint = 600.0;
  static const extendedBreakpoint = 1024.0;
  static const motionFast = Duration(milliseconds: 120);
  static const motionMedium = Duration(milliseconds: 240);
  static const motionSlow = Duration(milliseconds: 360);
  static const elevationLow = 1.0;
  static const elevationMedium = 3.0;

  static ThemeData get light {
    const scheme = ColorScheme.light(
      primary: primary,
      onPrimary: Colors.white,
      secondary: accent,
      onSecondary: navy,
      primaryContainer: subtleBlueSurface,
      onPrimaryContainer: navy,
      surface: surface,
      onSurface: text,
      error: danger,
      onError: Colors.white,
      outline: border,
    );
    const rounded = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(radius)),
    );
    const bordered = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(radius)),
      side: BorderSide(color: border, width: 1.5),
    );
    final baseText = ThemeData.light(useMaterial3: true).textTheme.apply(
      fontFamily: 'Lexend',
      bodyColor: text,
      displayColor: navy,
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Lexend',
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      textTheme: baseText.copyWith(
        titleLarge: baseText.titleLarge?.copyWith(
          color: navy,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: baseText.titleMedium?.copyWith(
          color: navy,
          fontWeight: FontWeight.w600,
        ),
        labelLarge: baseText.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        bodySmall: baseText.bodySmall?.copyWith(color: muted),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: navy,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Lexend',
          color: navy,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: const CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: bordered,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(radius)),
          borderSide: BorderSide(color: border, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(radius)),
          borderSide: BorderSide(color: border, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(radius)),
          borderSide: BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(radius)),
          borderSide: BorderSide(color: danger, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(radius)),
          borderSide: BorderSide(color: danger, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: rounded,
          textStyle: const TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: border, width: 1.5),
          minimumSize: const Size(48, 48),
          shape: rounded,
          textStyle: const TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: rounded,
          textStyle: const TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: rounded,
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: rounded,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: rounded,
        showDragHandle: true,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: rounded,
        contentTextStyle: TextStyle(fontFamily: 'Lexend', color: Colors.white),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: background,
        indicatorColor: Color(0x4D00B4D8),
        height: 72,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontFamily: 'Lexend', color: text),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        minTileHeight: 48,
        iconColor: primary,
        textColor: text,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primary
              : Colors.grey.shade500,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accent.withValues(alpha: 0.35)
              : Colors.grey.shade300,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: rounded,
        side: const BorderSide(color: border, width: 1.5),
        backgroundColor: surface,
        selectedColor: accent.withValues(alpha: 0.22),
        labelStyle: const TextStyle(fontFamily: 'Lexend'),
      ),
      dividerTheme: const DividerThemeData(color: border, thickness: 1.5),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: primary),
    );
  }

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: Color(0xFF48CAE4),
      onPrimary: Color(0xFF001F2A),
      secondary: Color(0xFF90E0EF),
      onSecondary: Color(0xFF001F2A),
      primaryContainer: Color(0xFF17394D),
      onPrimaryContainer: darkText,
      surface: darkSurface,
      onSurface: darkText,
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      outline: darkBorder,
    );
    final base = ThemeData.dark(useMaterial3: true);
    final textTheme = base.textTheme.apply(
      fontFamily: 'Lexend',
      bodyColor: darkText,
      displayColor: darkText,
    );
    const rounded = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(radius)),
    );
    const bordered = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(radius)),
      side: BorderSide(color: darkBorder, width: 1.5),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Lexend',
      colorScheme: scheme,
      scaffoldBackgroundColor: darkBackground,
      textTheme: textTheme.copyWith(
        titleLarge: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        titleMedium: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        labelLarge: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        bodySmall: textTheme.bodySmall?.copyWith(color: darkMuted),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkBackground,
        foregroundColor: darkText,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      cardTheme: const CardThemeData(
        color: darkSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: bordered,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: darkSurface,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(radius)),
          borderSide: BorderSide(color: darkBorder, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(radius)),
          borderSide: BorderSide(color: darkBorder, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(radius)),
          borderSide: BorderSide(color: Color(0xFF48CAE4), width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: rounded,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF48CAE4),
          side: const BorderSide(color: darkBorder, width: 1.5),
          minimumSize: const Size(48, 48),
          shape: rounded,
          textStyle: const TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: rounded,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: rounded,
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: darkSurface,
        shape: rounded,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: darkSurface,
        shape: rounded,
        showDragHandle: true,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: darkBackground,
        indicatorColor: Color(0x5548CAE4),
        height: 72,
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: darkBackground,
        indicatorColor: Color(0x5548CAE4),
      ),
      dividerTheme: const DividerThemeData(color: darkBorder, thickness: 1.5),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: Color(0xFF48CAE4),
      ),
      focusColor: const Color(0x6648CAE4),
    );
  }
}
