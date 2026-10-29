import 'package:flutter/material.dart';
import 'package:store_collection_app/theme/app_theme.dart';

class ModuleBadge extends StatelessWidget {
  const ModuleBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.goldSurface,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppTheme.primaryOlive,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }
}
