import 'package:flutter/material.dart';
import 'package:store_collection_app/theme/app_theme.dart';
import 'package:store_collection_app/utils/logout_confirmation.dart';
import 'package:store_collection_app/widgets/notification_bell.dart';

class EmptySystemDashboard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String branchName;
  final IconData icon;
  final Color color;

  const EmptySystemDashboard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.branchName,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(
          title: Text(title),
          backgroundColor: color,
          actions: [
            const NotificationBell(),
            IconButton(
              icon: const Icon(Icons.logout_rounded),
              tooltip: 'تسجيل الخروج',
              onPressed: () => confirmAndSignOut(context),
            ),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 520),
              padding: const EdgeInsets.all(24),
              decoration: AppTheme.cardShadow(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(icon, size: 38, color: color),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    branchName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      height: 1.6,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
