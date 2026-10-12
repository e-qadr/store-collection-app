import 'package:flutter/material.dart';
import 'package:store_collection_app/services/pdf_print_format.dart';
import 'package:store_collection_app/theme/app_theme.dart';

/// Shows the same deliberate paper-size choice everywhere a document prints.
Future<PdfPrintFormat?> showPdfPrintFormatPicker(
  BuildContext context, {
  String title = 'اختيار قالب الطباعة',
}) {
  return showModalBottomSheet<PdfPrintFormat>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
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
                    onTap: () => Navigator.pop(sheetContext, format),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
