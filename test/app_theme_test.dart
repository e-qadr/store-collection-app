import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store_collection_app/theme/app_theme.dart';

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  test('Al-Asalah palette keeps important text combinations readable', () {
    expect(
      _contrastRatio(Colors.white, AppTheme.primaryOlive),
      greaterThan(4.5),
    );
    expect(
      _contrastRatio(AppTheme.textPrimary, AppTheme.goldSurface),
      greaterThan(4.5),
    );
    expect(
      _contrastRatio(AppTheme.textPrimary, AppTheme.brandGold),
      greaterThan(4.5),
    );
    expect(
      _contrastRatio(AppTheme.textSecondary, AppTheme.cardColor),
      greaterThan(4.5),
    );
  });

  test(
    'central theme uses the Al-Asalah primary, gold accent, and olive chips',
    () {
      final theme = AppTheme.lightTheme;
      expect(theme.colorScheme.primary, AppTheme.primaryOlive);
      expect(theme.colorScheme.secondary, AppTheme.brandGold);
      expect(theme.colorScheme.primaryContainer, AppTheme.oliveSurface);
      expect(theme.appBarTheme.backgroundColor, AppTheme.primaryOlive);
      expect(theme.chipTheme.selectedColor, AppTheme.oliveSurface);
    },
  );
}
