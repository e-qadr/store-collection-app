import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store_collection_app/services/pdf_print_format.dart';
import 'package:store_collection_app/widgets/pdf_print_format_picker.dart';

void main() {
  testWidgets('PDF menu shows a format choice before allowing a print action', (
    tester,
  ) async {
    PdfPrintFormat? selectedFormat;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.picture_as_pdf_rounded),
                onSelected: (action) async {
                  selectedFormat = await showPdfPrintFormatPicker(
                    tester.element(find.byType(Scaffold)),
                  );
                },
                itemBuilder: (_) => const [
                  PopupMenuItem<String>(
                    value: 'print',
                    child: Text('معاينة وطباعة'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.picture_as_pdf_rounded));
      await tester.pumpAndSettle();
    await tester.tap(find.text('معاينة وطباعة'));
      await tester.pumpAndSettle();

    expect(find.text('اختيار قالب الطباعة'), findsOneWidget);
    expect(find.text('ورقة A4'), findsOneWidget);
    expect(find.text('إيصال كاشير 80 مم'), findsOneWidget);
    expect(selectedFormat, isNull);

    await tester.tap(find.text('إيصال كاشير 80 مم'));
      await tester.pumpAndSettle();
    expect(selectedFormat, PdfPrintFormat.receipt80mm);
  });
}
