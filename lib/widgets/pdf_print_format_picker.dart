import 'package:flutter/material.dart';
import 'package:store_collection_app/services/pdf_print_format.dart';
import 'package:store_collection_app/theme/app_theme.dart';

/// Shows the same deliberate paper-size choice everywhere a document prints.
///
/// This uses a dialog rather than a bottom sheet. PDF actions can originate
/// from a popup menu, and a dialog is consistently displayed above that menu
/// on mobile and browser renderers. Returning `null` always means cancel; a
/// caller must never silently fall back to A4.
Future<PdfPrintFormat?> showPdfPrintFormatPicker(
  BuildContext context, {
  String title = 'اختيار قالب الطباعة',
}) {
  return showDialog<PdfPrintFormat>(
    context: context,
    useRootNavigator: true,
    builder: (dialogContext) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'اختر مقاس الورق قبل فتح معاينة الطباعة.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 18),
              for (final format in PdfPrintFormat.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: AppTheme.surfaceColor,
                    borderRadius: BorderRadius.circular(16),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: AppTheme.dividerColor),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: CircleAvatar(
                        backgroundColor: AppTheme.darkOlive.withValues(
                          alpha: .10,
                        ),
                        foregroundColor: AppTheme.darkOlive,
                        child: Icon(format.icon),
                      ),
                      title: Text(
                        format.label,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(format.description),
                      trailing: const Icon(Icons.chevron_left_rounded),
                      onTap: () => Navigator.of(
                        dialogContext,
                        rootNavigator: true,
                      ).pop(format),
                    ),
                  ),
                ),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext, rootNavigator: true).pop(),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    ),
  );
}
