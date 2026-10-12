import 'package:flutter/material.dart';

/// The physical paper layout used when producing a PDF.
///
/// [receipt80mm] uses the standard 80 mm thermal receipt roll used by most
/// cashier printers. The PDF has an automatic height, so long invoices are not
/// clipped to a fixed receipt length.
enum PdfPrintFormat { a4, receipt80mm }

extension PdfPrintFormatLabels on PdfPrintFormat {
  String get label => switch (this) {
    PdfPrintFormat.a4 => 'ورقة A4',
    PdfPrintFormat.receipt80mm => 'إيصال كاشير 80 مم',
  };

  String get description => switch (this) {
    PdfPrintFormat.a4 => 'نسخة كاملة مناسبة للأرشفة والمراسلات',
    PdfPrintFormat.receipt80mm => 'نسخة مختصرة مناسبة للطابعات الحرارية',
  };

  IconData get icon => switch (this) {
    PdfPrintFormat.a4 => Icons.description_outlined,
    PdfPrintFormat.receipt80mm => Icons.receipt_long_outlined,
  };

  String get fileSuffix => switch (this) {
    PdfPrintFormat.a4 => 'a4',
    PdfPrintFormat.receipt80mm => 'receipt_80mm',
  };
}
