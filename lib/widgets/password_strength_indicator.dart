import 'package:flutter/material.dart';
import 'package:store_collection_app/theme/app_theme.dart';
import 'package:store_collection_app/utils/password_policy.dart';

class PasswordStrengthIndicator extends StatelessWidget {
  final String password;

  const PasswordStrengthIndicator({super.key, required this.password});

  @override
  Widget build(BuildContext context) {
    final strength = PasswordPolicy.strength(password);
    final (fraction, color, label) = switch (strength) {
      PasswordStrength.weak => (0.33, AppTheme.errorColor, 'ضعيفة'),
      PasswordStrength.fair => (0.66, AppTheme.warningColor, 'متوسطة'),
      PasswordStrength.strong => (1.0, AppTheme.successColor, 'قوية'),
    };
    final messages = PasswordPolicy.validationMessages(password);
    return Semantics(
      label: 'قوة كلمة المرور: $label',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('قوة كلمة المرور', style: TextStyle(fontSize: 12)),
              const Spacer(),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: password.isEmpty ? 0 : fraction,
            minHeight: 6,
            borderRadius: BorderRadius.circular(6),
            color: color,
            backgroundColor: AppTheme.dividerColor,
          ),
          if (password.isNotEmpty && messages.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              messages.first,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
