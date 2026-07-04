import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Centralized design system for the Store Collection App.
/// Provides colors, gradients, typography, and shared style helpers.
class AppTheme {
  AppTheme._();

  // ── Role Brand Colors ──────────────────────────────────────────────
  static const Color managerColor = Color(0xFF1565C0);
  static const Color collectorColor = Color(0xFF00695C);
  static const Color accountantColor = Color(0xFF4527A0);
  static const Color adminColor = Color(0xFF6A1B9A);

  // ── Semantic Colors ────────────────────────────────────────────────
  static const Color successColor = Color(0xFF2E7D32);
  static const Color warningColor = Color(0xFFE65100);
  static const Color errorColor = Color(0xFFC62828);
  static const Color pendingColor = Color(0xFFF57C00);

  // ── Surface & Background ──────────────────────────────────────────
  static const Color surfaceColor = Color(0xFFF0F4FF);
  static const Color cardColor = Color(0xFFFFFFFF);
  static const Color dividerColor = Color(0xFFEEF2FF);

  // ── Text Colors ───────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF0D1117);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textHint = Color(0xFF94A3B8);

  // ── Role Gradients ─────────────────────────────────────────────────
  static const List<Color> managerGradient = [
    Color(0xFF0D47A1),
    Color(0xFF1565C0),
    Color(0xFF1E88E5),
  ];
  static const List<Color> collectorGradient = [
    Color(0xFF004D40),
    Color(0xFF00695C),
    Color(0xFF00897B),
  ];
  static const List<Color> accountantGradient = [
    Color(0xFF311B92),
    Color(0xFF4527A0),
    Color(0xFF5E35B1),
  ];
  static const List<Color> adminGradient = [
    Color(0xFF4A148C),
    Color(0xFF6A1B9A),
    Color(0xFF7B1FA2),
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
    const seed = managerColor;
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.light,
        surface: surfaceColor,
      ),
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
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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
