import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../model/console_log.dart';
import '../../model/http_call.dart';

/// Brand & semantic colors for Samseer UI.
class SamseerColors {
  static const Color seed = Color(0xFF5B6BFF); // indigo-violet

  // Status colors (work in light & dark mode).
  static const Color success = Color(0xFF22C55E);
  static const Color redirect = Color(0xFF3B82F6);
  static const Color clientError = Color(0xFFF59E0B);
  static const Color serverError = Color(0xFFEF4444);
  static const Color loading = Color(0xFF94A3B8);
  static const Color generalError = Color(0xFFE11D48);

  static Color forState(SamseerCallState state) {
    switch (state) {
      case SamseerCallState.success:
        return success;
      case SamseerCallState.redirect:
        return redirect;
      case SamseerCallState.clientError:
        return clientError;
      case SamseerCallState.serverError:
        return serverError;
      case SamseerCallState.loading:
        return loading;
      case SamseerCallState.error:
        return generalError;
    }
  }

  static Color forLogLevel(SamseerLogLevel level) {
    switch (level) {
      case SamseerLogLevel.error:
        return serverError;
      case SamseerLogLevel.warn:
        return clientError;
      case SamseerLogLevel.info:
        return redirect;
      case SamseerLogLevel.debug:
        return loading;
      case SamseerLogLevel.log:
        return loading;
    }
  }
}

class SamseerTheme {
  static ThemeData theme() => _build();

  static ThemeData _build() {
    const brightness = Brightness.dark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: SamseerColors.seed,
      brightness: brightness,
    );

    final baseText = GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme);

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: colorScheme.surface,
      textTheme: baseText,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        titleTextStyle: baseText.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: colorScheme.onSurface,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerHighest,
        selectedColor: colorScheme.primary,
        side: BorderSide.none,
        labelStyle: baseText.labelMedium,
        showCheckmark: false,
        elevation: 0,
        pressElevation: 0,
        shadowColor: Colors.transparent,
        selectedShadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: const StadiumBorder(side: BorderSide.none),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        indicatorSize: TabBarIndicatorSize.label,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: colorScheme.primary, width: 2.5),
        ),
        labelStyle: baseText.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        unselectedLabelStyle: baseText.labelLarge,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        thickness: 1,
        space: 1,
      ),
    );
  }

  static TextStyle mono(BuildContext context,
      {double size = 13, FontWeight? weight, Color? color}) {
    return GoogleFonts.jetBrainsMono(
      fontSize: size,
      fontWeight: weight ?? FontWeight.w400,
      color: color ?? Theme.of(context).colorScheme.onSurface,
      height: 1.4,
    );
  }
}
