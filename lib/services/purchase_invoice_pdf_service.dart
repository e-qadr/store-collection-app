import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/models/purchase_invoice_model.dart';
import 'package:store_collection_app/models/purchase_invoice_price_model.dart';
import 'package:store_collection_app/services/pdf_print_format.dart';

class PurchaseInvoicePdfInput {
  final Map<String, dynamic> header;
  final List<Map<String, dynamic>> items;
  final bool showPrices;
  final String accountingReference;
  final double? total;

  const PurchaseInvoicePdfInput({
    required this.header,
    required this.items,
    required this.showPrices,
    this.accountingReference = '',
    this.total,
  });
}

class PurchaseInvoicePdfService {
  static PurchaseInvoicePdfInput prepare({
    required PurchaseInvoiceRead invoice,
    required UserRole audienceRole,
    PurchaseInvoicePriceSnapshot? protectedPrices,
  }) {
    final authorized = const {
      UserRole.collector,
      UserRole.accountant,
      UserRole.admin,
    }.contains(audienceRole);
    final verified =
        authorized &&
            protectedPrices != null &&
            protectedPrices.matches(invoice)
        ? protectedPrices
        : null;
    final safeHeader = <String, dynamic>{
      'purchase_number': invoice.purchaseNumber,
      'receiving_branch_name': invoice.receivingBranchName,
      'supplier_name': invoice.supplierName,
      'supplier_invoice_number': invoice.supplierInvoiceNumber,
      'supplier_invoice_date': invoice.supplierInvoiceDate,
      'currency': invoice.currency,
      'created_at': invoice.createdAt,
      'status': invoice.status.label,
    };
    final items = invoice.items
        .map((item) {
          final price = verified?.itemById(item.id);
          return <String, dynamic>{
            'name': item.displayName,
            'original_name': item.originalMaterialName,
            'unit': item.displayUnit,
            'ordered_quantity': item.orderedQuantity,
            if (item.receivedQuantity != null)
              'received_quantity': item.receivedQuantity,
            'review_status': item.reviewLabel,
            if (price != null) 'unit_price': price.unitPrice,
            if (price != null) 'line_total': price.lineTotal,
          };
        })
        .toList(growable: false);
    return PurchaseInvoicePdfInput(
      header: safeHeader,
      items: items,
      showPrices: verified != null,
      accountingReference: verified?.accountingReference ?? '',
      total: verified?.invoiceTotal,
    );
  }

  static Future<Uint8List> build(
    PurchaseInvoicePdfInput input, {
    PdfPrintFormat format = PdfPrintFormat.a4,
  }) async {
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Cairo-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Cairo-Bold.ttf'),
    );
    final document = pw.Document();
    final header = input.header;
    if (format == PdfPrintFormat.receipt80mm) {
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.roll80,
          theme: pw.ThemeData.withFont(base: regular, bold: bold),
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.all(14),
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Text(
                'فاتورة مشتريات',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'رقم الفاتورة: ${header['purchase_number']}',
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.Text(
                'الفرع: ${header['receiving_branch_name']}',
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 9),
              ),
              _divider(),
              _pair('المورد', _fallback(header['supplier_name'])),
              _pair(
                'فاتورة المورد',
                _fallback(header['supplier_invoice_number']),
              ),
              _pair('التاريخ', _fallback(header['supplier_invoice_date'])),
              _pair('الحالة', _fallback(header['status'])),
              _divider(),
              pw.Text(
                'المواد',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              ...input.items.map(
                (item) => pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 6),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      pw.Text(
                        item['name']?.toString() ?? '-',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text(
                        '${_number(item['ordered_quantity'])} ${item['unit'] ?? ''}'
                        '${item['received_quantity'] == null ? '' : ' | المستلم: ${_number(item['received_quantity'])}'}',
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                      if (input.showPrices)
                        pw.Text(
                          '${_number(item['line_total'])} ${header['currency']}',
                          textAlign: pw.TextAlign.left,
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                    ],
                  ),
                ),
              ),
              if (input.showPrices) ...[
                _divider(),
                pw.Text(
                  'الإجمالي: ${_number(input.total)} ${header['currency']}',
                  textAlign: pw.TextAlign.left,
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
              _divider(),
              pw.Text(
                'طُبع في ${DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now())}',
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(
                  fontSize: 7,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
        ),
      );
      return document.save();
    }
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.all(28),
        build: (_) => [
          pw.Text(
            'فاتورة مشتريات',
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 12),
          pw.Text('رقم الفاتورة (النظام): ${header['purchase_number']}'),
          pw.Text('الفرع المستلم: ${header['receiving_branch_name']}'),
          pw.Text('المورد: ${_fallback(header['supplier_name'])}'),
          pw.Text(
            'رقم فاتورة المورد / الورقية: ${_fallback(header['supplier_invoice_number'])}',
          ),
          pw.Text(
            'تاريخ فاتورة المورد: ${_fallback(header['supplier_invoice_date'])}',
          ),
          pw.Text('الحالة: ${header['status']}'),
          if (input.showPrices)
            pw.Text('المرجع المحاسبي: ${_fallback(input.accountingReference)}'),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: [
              'المادة',
              'الوحدة',
              'الكمية المطلوبة',
              'الكمية المستلمة',
              'حالة المطابقة',
              if (input.showPrices) 'السعر (${header['currency']})',
              if (input.showPrices) 'الإجمالي',
            ],
            data: input.items
                .map(
                  (item) => [
                    item['name'],
                    item['unit'],
                    _number(item['ordered_quantity']),
                    _number(item['received_quantity']),
                    item['review_status'],
                    if (input.showPrices) _number(item['unit_price']),
                    if (input.showPrices) _number(item['line_total']),
                  ],
                )
                .toList(),
            border: pw.TableBorder.all(color: PdfColors.grey300),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColors.indigo700,
            ),
            headerStyle: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
              fontSize: 8,
            ),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignment: pw.Alignment.centerRight,
          ),
          if (input.showPrices) ...[
            pw.SizedBox(height: 12),
            pw.Text(
              'الإجمالي: ${_number(input.total)} ${header['currency']}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ],
          pw.SizedBox(height: 18),
          pw.Text(
            'أُنشئ المستند في ${DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ),
    );
    return document.save();
  }

  static Future<void> printInvoice({
    required PurchaseInvoiceRead invoice,
    required UserRole audienceRole,
    PurchaseInvoicePriceSnapshot? protectedPrices,
    PdfPrintFormat format = PdfPrintFormat.a4,
  }) async {
    final input = prepare(
      invoice: invoice,
      audienceRole: audienceRole,
      protectedPrices: protectedPrices,
    );
    final bytes = await build(input, format: format);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'purchase_${invoice.purchaseNumber}_${format.fileSuffix}.pdf',
    );
  }

  static String _number(dynamic value) {
    final number = value is num ? value.toDouble() : null;
    if (number == null) return '-';
    return number == number.roundToDouble()
        ? number.toInt().toString()
        : number.toStringAsFixed(2);
  }

  static String _fallback(dynamic value) {
    final clean = value?.toString().trim() ?? '';
    return clean.isEmpty ? '-' : clean;
  }

  static pw.Widget _divider() => pw.Container(
    margin: const pw.EdgeInsets.symmetric(vertical: 7),
    decoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey500)),
    ),
  );

  static pw.Widget _pair(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 3),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: 2,
          child: pw.Text(
            label,
            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.Expanded(
          flex: 3,
          child: pw.Text(value, style: const pw.TextStyle(fontSize: 8)),
        ),
      ],
    ),
  );
}
