import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Centralized design system for the Store Collection App.
/// Provides colors, gradients, typography, and shared style helpers.
class AppTheme {
  AppTheme._();

  // ── Role Brand Colors ──────────────────────────────────────────────
  // Al-Asalah palette, taken from the live brand site:
  // primary #BCAE93, secondary #2B4D4D, success #627D47.
  static const Color brandGold = Color(0xFFBCAE93);
  static const Color lightGold = Color(0xFFC0BEA9);
  static const Color primaryOlive = Color(0xFF2B4D4D);
  static const Color darkOlive = Color(0xFF1A4D4A);
  static const Color oliveGreen = Color(0xFF627D47);
  static const Color oliveSurface = Color(0xFFE3EBE0);
  static const Color goldSurface = Color(0xFFFFF9F0);

  static const Color managerColor = primaryOlive;
  static const Color collectorColor = oliveGreen;
  static const Color accountantColor = darkOlive;
  static const Color adminColor = Color(0xFF405E45);

  // ── Semantic Colors ────────────────────────────────────────────────
  static const Color successColor = Color(0xFF2E7D32);
  static const Color warningColor = Color(0xFFE65100);
  static const Color errorColor = Color(0xFFC62828);
  static const Color pendingColor = Color(0xFFF57C00);

  // ── Surface & Background ──────────────────────────────────────────
  static const Color surfaceColor = goldSurface;
  static const Color cardColor = Color(0xFFFFFFFF);
  static const Color dividerColor = lightGold;

  // ── Text Colors ───────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF1F1F1F);
  static const Color textSecondary = Color(0xFF666666);
  static const Color textHint = Color(0xFF71716E);

  // ── Role Gradients ─────────────────────────────────────────────────
  static const List<Color> managerGradient = [
    darkOlive,
    primaryOlive,
    Color(0xFF3D6261),
  ];
  static const List<Color> collectorGradient = [
    Color(0xFF4D6537),
    oliveGreen,
    Color(0xFF718C55),
  ];
  static const List<Color> accountantGradient = [
    Color(0xFF133B39),
    darkOlive,
    primaryOlive,
  ];
  static const List<Color> adminGradient = [
    Color(0xFF304834),
    adminColor,
    oliveGreen,
  ];

  // ── Status Helpers ────────────────────────────────────────────────
  static Color statusColor(String status) {
    switch (status) {
      case 'pending':
        return pendingColor;
      case 'approvedByCollector':
        return managerColor;
      case 'approvedByManager':
        return collectorColor;
      case 'approvedByAccountant':
        return successColor;
      case 'editRequestedByCollector':
        return errorColor;
      case 'pendingApprovalOfEdit':
        return const Color(0xFFF9A825);
      case 'reviewRequestedByAccountant':
        return accountantColor;
      case 'reviewRequestedByManager':
        return managerColor;
      case 'rejectedByManager':
        return const Color(0xFFB71C1C);
      default:
        return textSecondary;
    }
  }

  static String statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'قيد الانتظار';
      case 'approvedByCollector':
        return 'معتمد من المدير العام';
      case 'approvedByManager':
        return 'معتمد من المدير';
      case 'approvedByAccountant':
        return 'مكتمل نهائياً';
      case 'editRequestedByCollector':
        return 'يتطلب تعديل';
      case 'pendingApprovalOfEdit':
        return 'تعديل بانتظار الموافقة';
      case 'reviewRequestedByAccountant':
        return 'مراجعة المحاسب';
      case 'reviewRequestedByManager':
        return 'مراجعة المدير';
      case 'rejectedByManager':
        return 'مرفوض';
      default:
        return 'غير معروف';
    }
  }

  // ── Card Box Decoration ───────────────────────────────────────────
  static BoxDecoration cardShadow({
    Color color = cardColor,
    double radius = 16,
    double shadowOpacity = 0.06,
    double blurRadius = 18,
  }) => BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: shadowOpacity),
        blurRadius: blurRadius,
        offset: const Offset(0, 4),
      ),
    ],
  );

  // ── Global Light Theme ────────────────────────────────────────────
  static ThemeData get lightTheme {
    const seed = primaryOlive;
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
          surface: surfaceColor,
        ).copyWith(
          primary: primaryOlive,
          onPrimary: Colors.white,
          primaryContainer: oliveSurface,
          onPrimaryContainer: darkOlive,
          secondary: brandGold,
          onSecondary: textPrimary,
          secondaryContainer: Color(0xFFE9E3D2),
          onSecondaryContainer: textPrimary,
          tertiary: oliveGreen,
          onTertiary: Colors.white,
          surface: surfaceColor,
          onSurface: textPrimary,
          surfaceContainerHighest: Color(0xFFF1EEE5),
          outline: dividerColor,
          outlineVariant: dividerColor,
          error: errorColor,
          onError: Colors.white,
        );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: surfaceColor,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        backgroundColor: managerColor,
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.2,
        ),
        iconTheme: IconThemeData(color: Colors.white),
        actionsIconTheme: IconThemeData(color: Colors.white),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: cardColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: seed,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: seed,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: seed,
          side: const BorderSide(color: seed, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: seed,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: primaryOlive),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: dividerColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: dividerColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: seed, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: errorColor),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: errorColor, width: 2),
        ),
        labelStyle: const TextStyle(color: textSecondary, fontSize: 14),
        hintStyle: const TextStyle(color: textHint, fontSize: 14),
        prefixIconColor: textSecondary,
        suffixIconColor: textSecondary,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: seed,
        foregroundColor: Colors.white,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primaryOlive,
        linearTrackColor: Color(0xFFE9E3D2),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: textSecondary,
        textColor: textPrimary,
        subtitleTextStyle: TextStyle(color: textSecondary, fontSize: 12),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: textPrimary,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.bold,
          color: textPrimary,
        ),
        contentTextStyle: const TextStyle(fontSize: 14, color: textSecondary),
        elevation: 6,
      ),
      dividerTheme: const DividerThemeData(
        color: dividerColor,
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: cardColor,
        selectedColor: oliveSurface,
        disabledColor: Color(0xFFE8E5DD),
        checkmarkColor: darkOlive,
        side: const BorderSide(color: dividerColor),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        labelStyle: const TextStyle(
          color: textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: const TextStyle(
          color: darkOlive,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cardColor,
        indicatorColor: Color(0xFFE9E3D2),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? primaryOlive
                : textSecondary,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? primaryOlive
                : textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: cardColor,
        selectedItemColor: primaryOlive,
        unselectedItemColor: textSecondary,
      ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        textStyle: TextStyle(color: textPrimary),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.bold,
          color: textPrimary,
        ),
        headlineMedium: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: textPrimary,
        ),
        headlineSmall: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleSmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textSecondary,
        ),
        bodyLarge: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.normal,
          color: textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.normal,
          color: textSecondary,
        ),
        bodySmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.normal,
          color: textHint,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
      ),
    );
  }
}
