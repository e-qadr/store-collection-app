import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

Future<void> confirmAndSignOut(BuildContext context) async {
  final confirmed =
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('تأكيد تسجيل الخروج'),
          content: const Text('هل تريد تسجيل الخروج من التطبيق؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('تسجيل الخروج'),
            ),
          ],
        ),
      ) ??
      false;

  if (!confirmed || !context.mounted) return;
  await FirebaseAuth.instance.signOut();
  if (context.mounted) {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}
