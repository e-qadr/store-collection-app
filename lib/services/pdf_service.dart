import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/models/inter_branch_invoice_model.dart';
import 'package:store_collection_app/models/inter_branch_invoice_price_model.dart';
import 'package:store_collection_app/theme/app_theme.dart';
import 'package:store_collection_app/utils/transaction_records.dart';

class SecureInterBranchInvoicePdfInput {
  final Map<String, dynamic> data;
  final bool showPrices;

  const SecureInterBranchInvoicePdfInput({
    required this.data,
    required this.showPrices,
  });
}

class PdfService {
  static Future<pw.ThemeData> _theme() async {
    final regularData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final boldData = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
    final regular = pw.Font.ttf(regularData);
    final bold = pw.Font.ttf(boldData);
    return pw.ThemeData.withFont(base: regular, bold: bold);
  }

  static String _date(dynamic value, {bool withTime = false}) {
    final date = transactionDate(value);
    if (date == null) return 'غير محدد';
    return DateFormat(
      withTime ? 'yyyy/MM/dd - HH:mm' : 'yyyy/MM/dd',
    ).format(date);
  }

  static String _amount(dynamic value) =>
      NumberFormat('#,##0.##', 'en_US').format((value as num?) ?? 0);

  static String _status(dynamic value) =>
      AppTheme.statusLabel(value?.toString() ?? '');

  static String _cashExpenseStatus(dynamic value) {
    switch (value?.toString()) {
      case 'pendingGeneralManagerReview':
        return 'بانتظار المدير العام';
      case 'rejectedByGeneralManager':
        return 'مرفوض من المدير العام';
      case 'pendingInvoiceAttachment':
        return 'بانتظار إرفاق الفاتورة';
      case 'pendingAccountingApproval':
        return 'بانتظار اعتماد المحاسب';
      case 'editPendingApprovals':
        return 'طلب تعديل بانتظار الموافقات';
      case 'approvedByAccountant':
        return 'معتمد نهائياً';
      default:
        return 'غير معروف';
    }
  }

  static String _amountMatchStatus(dynamic value) {
    if (value == true) return 'matched';
    if (value == false) return 'unmatched';
    return 'unreviewed';
  }

  static String _amountMatchLabel(dynamic value) {
    switch (_amountMatchStatus(value)) {
      case 'matched':
        return 'مطابق';
      case 'unmatched':
        return 'غير مطابق';
      default:
        return 'غير مراجع';
    }
  }

  static String _actor(Map<String, dynamic> data) {
    final history = (data['history'] as List?)?.cast<Map>() ?? [];
    for (final item in history) {
      if (item['action'] == 'created' && item['actor_name'] != null) {
        return item['actor_name'].toString();
      }
    }
    return 'غير محدد';
  }

  static String _safeName(String value) =>
      value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

  static Future<Uint8List> buildSingleTransaction({
    required Map<String, dynamic> data,
    required String branchName,
  }) async {
    final pdf = pw.Document();
    final theme = await _theme();
    final currency = data['currency']?.toString() ?? 'YER';
    final transactionNumber = data['transaction_number']?.toString() ?? '-';
    final amountMatchStatus = _amountMatchStatus(data['amount_matches']);
    final amount = (data['amount'] as num?)?.toDouble() ?? 0;
    final cashierAmount = (data['cashier_amount'] as num?)?.toDouble();
    final amountDifference =
        amountMatchStatus == 'unmatched' && cashierAmount != null
        ? (amount - cashierAmount).abs()
        : null;
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: theme,
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.all(32),
        footer: _footer,
        build: (_) => [
          _documentHeader(
            title: 'سند تحصيل مالي',
            subtitle: 'رقم السند: $transactionNumber',
            branchName: branchName,
          ),
          pw.SizedBox(height: 18),
          _sectionTitle('بيانات السند الأساسية'),
          _detailsGrid([
            ['رقم السند', transactionNumber],
            ['الفرع', branchName],
            ['حالة السند', _status(data['status'])],
            ['المدير العام', _actor(data)],
            ['تاريخ ووقت الإدخال', _date(data['timestamp'], withTime: true)],
            [
              'فترة التحصيل',
              '${_date(data['dateFrom'])} إلى ${_date(data['dateTo'])}',
            ],
          ]),
          pw.SizedBox(height: 14),
          _amountSummary(
            amount: _amount(data['amount']),
            currency: currency,
            amountMatchStatus: amountMatchStatus,
            cashierAmount: cashierAmount == null
                ? null
                : _amount(cashierAmount),
            amountDifference: amountDifference == null
                ? null
                : _amount(amountDifference),
          ),
          pw.SizedBox(height: 14),
          _sectionTitle('الملاحظات'),
          _noteBox('ملاحظات المدير العام', data['notes']?.toString()),
          if ((data['manager_notes']?.toString() ?? '').isNotEmpty)
            _noteBox('ملاحظات الإدارة', data['manager_notes']?.toString()),
          if ((data['accountant_notes']?.toString() ?? '').isNotEmpty)
            _noteBox(
              'ملاحظات المحاسب بعد الاعتماد',
              data['accountant_notes']?.toString(),
            ),
          pw.SizedBox(height: 28),
          _signatures(),
        ],
      ),
    );
    return pdf.save();
  }

  static Future<Uint8List> buildTransactionsReport({
    required List<QueryDocumentSnapshot> transactions,
    required String branchName,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    return buildTransactionsReportFromData(
      records: transactions
          .map((doc) => doc.data() as Map<String, dynamic>)
          .toList(),
      branchName: branchName,
      startDate: startDate,
      endDate: endDate,
    );
  }

  static Future<Uint8List> buildTransactionsReportFromData({
    required List<Map<String, dynamic>> records,
    required String branchName,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final pdf = pw.Document();
    final theme = await _theme();
    final totals = totalsByCurrency(records);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        theme: theme,
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.all(24),
        footer: _footer,
        build: (_) => [
          _documentHeader(
            title: 'تقرير سندات التحصيل',
            subtitle:
                'من ${DateFormat('yyyy/MM/dd').format(startDate)} إلى ${DateFormat('yyyy/MM/dd').format(endDate)}',
            branchName: branchName,
          ),
          pw.SizedBox(height: 14),
          pw.Row(
            children: [
              _summaryCard('عدد السندات', '${records.length}'),
              ...totals.entries.map(
                (entry) =>
                    _summaryCard('إجمالي ${entry.key}', _amount(entry.value)),
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: const [
              'رقم السند',
              'المبلغ',
              'العملة',
              'المدير العام',
              'من',
              'إلى',
              'تاريخ الإدخال',
              'المطابقة',
              'الحالة',
              'الملاحظات',
            ],
            data: records
                .map(
                  (data) => [
                    data['transaction_number']?.toString() ?? '-',
                    _amount(data['amount']),
                    data['currency']?.toString() ?? '-',
                    _actor(data),
                    _date(data['dateFrom']),
                    _date(data['dateTo']),
                    _date(data['timestamp'], withTime: true),
                    _amountMatchLabel(data['amount_matches']),
                    _status(data['status']),
                    data['notes']?.toString() ?? '',
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
            cellStyle: const pw.TextStyle(fontSize: 7),
            cellAlignment: pw.Alignment.centerRight,
            cellPadding: const pw.EdgeInsets.all(4),
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            'تم إنشاء التقرير في ${DateFormat('yyyy/MM/dd - HH:mm').format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ),
    );
    return pdf.save();
  }

  static Future<Uint8List> buildInterBranchInvoice({
    required Map<String, dynamic> data,
    bool showPrices = false,
  }) async {
    final pdf = pw.Document();
    final theme = await _theme();
    final invoiceNumber = data['invoice_number']?.toString() ?? '-';
    final priceCurrency = data['_protected_price_currency']?.toString() ?? '';
    final rawItems = data['items'];
    final items = rawItems is List && rawItems.isNotEmpty
        ? rawItems.whereType<Map>().toList()
        : [
            {
              'name': data['item_name'],
              'unit': data['unit'],
              'requested_quantity': data['requested_quantity'],
              'approved_quantity': data['approved_quantity'],
              'received_quantity': data['received_quantity'],
              'unit_price': data['unit_price'],
              'total_price': data['total_price'],
            },
          ];

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: theme,
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.all(32),
        footer: _footer,
        build: (_) => [
          _documentHeader(
            title: 'فاتورة بين الفروع',
            subtitle: 'رقم الفاتورة: $invoiceNumber',
            branchName: data['sending_branch_name']?.toString() ?? '-',
          ),
          pw.SizedBox(height: 18),
          _sectionTitle('بيانات الفاتورة'),
          _detailsGrid([
            ['رقم الفاتورة', invoiceNumber],
            ['التاريخ', _date(data['invoice_created_at'], withTime: true)],
            ['من الفرع', data['sending_branch_name']?.toString() ?? '-'],
            ['إلى الفرع', data['receiving_branch_name']?.toString() ?? '-'],
            [
              'المرجع المحاسبي',
              data['accounting_reference']?.toString().isEmpty ?? true
                  ? '-'
                  : data['accounting_reference'].toString(),
            ],
          ]),
          pw.SizedBox(height: 14),
          _sectionTitle('الأصناف'),
          pw.TableHelper.fromTextArray(
            headers: [
              'الصنف',
              'الكمية المطلوبة',
              'الكمية المعتمدة',
              'الكمية المستلمة',
              'الوحدة',
              if (showPrices) ...[
                priceCurrency.isEmpty ? 'السعر' : 'السعر ($priceCurrency)',
                'الإجمالي',
              ],
            ],
            data: items.map((item) {
              final row = [
                item['name']?.toString() ??
                    item['item_name']?.toString() ??
                    '-',
                _amount(item['requested_quantity']),
                _amount(
                  item['approved_quantity'] ?? item['requested_quantity'],
                ),
                _amount(
                  item['received_quantity'] ??
                      item['approved_quantity'] ??
                      item['requested_quantity'],
                ),
                item['unit']?.toString() ?? '-',
              ];
              if (showPrices) {
                row.addAll([
                  item['unit_price'] == null
                      ? '-'
                      : _amount(item['unit_price']),
                  item['total_price'] == null
                      ? '-'
                      : _amount(item['total_price']),
                ]);
              }
              return row;
            }).toList(),
            border: pw.TableBorder.all(color: PdfColors.grey300),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColors.indigo700,
            ),
            headerStyle: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
              fontSize: 9,
            ),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignment: pw.Alignment.centerRight,
            cellPadding: const pw.EdgeInsets.all(6),
          ),
          pw.SizedBox(height: 20),
          _signatures(),
        ],
      ),
    );
    return pdf.save();
  }

  /// Builds an inter-branch PDF without trusting public price fields.
  ///
  /// Workflow-v2 prices are included only for an authorized audience and only
  /// after the restricted snapshot is structurally matched to the public
  /// invoice. Product names and units always come from the public snapshot.
  static Future<Uint8List> buildSecureInterBranchInvoice({
    required String invoiceId,
    required Map<String, dynamic> publicData,
    required UserRole audienceRole,
    InterBranchInvoicePriceSnapshot? priceSnapshot,
    List<Map<String, dynamic>>? itemDocuments,
  }) {
    final input = prepareSecureInterBranchInvoicePdfInput(
      invoiceId: invoiceId,
      publicData: publicData,
      audienceRole: audienceRole,
      priceSnapshot: priceSnapshot,
      itemDocuments: itemDocuments,
    );
    return buildInterBranchInvoice(
      data: input.data,
      showPrices: input.showPrices,
    );
  }

  static SecureInterBranchInvoicePdfInput
  prepareSecureInterBranchInvoicePdfInput({
    required String invoiceId,
    required Map<String, dynamic> publicData,
    required UserRole audienceRole,
    InterBranchInvoicePriceSnapshot? priceSnapshot,
    List<Map<String, dynamic>>? itemDocuments,
  }) {
    final invoice = InterBranchInvoiceRead(
      id: invoiceId,
      data: publicData,
      itemDocuments: itemDocuments,
    );
    final mayReadPrices =
        audienceRole == UserRole.collector ||
        audienceRole == UserRole.accountant ||
        audienceRole == UserRole.admin;
    if (!invoice.isVersion2) {
      return SecureInterBranchInvoicePdfInput(
        data: publicData,
        showPrices: mayReadPrices,
      );
    }

    final verifiedPrices =
        mayReadPrices &&
            priceSnapshot != null &&
            priceSnapshot.matchesPublicInvoice(invoice)
        ? priceSnapshot
        : null;
    final safeData = Map<String, dynamic>.from(publicData)
      ..remove('unit_price')
      ..remove('total_price')
      ..['_protected_price_currency'] = verifiedPrices?.currency ?? ''
      ..['invoice_created_at'] =
          publicData['invoice_created_at'] ?? publicData['created_at']
      ..['items'] = invoice.items
          .map((item) {
            final protectedItem = verifiedPrices?.itemById(item.itemId);
            return <String, dynamic>{
              'name': item.name,
              'unit': item.unit,
              'requested_quantity': item.suppliedQuantity,
              'approved_quantity': item.suppliedQuantity,
              if (item.hasReceivedQuantity)
                'received_quantity': item.receivedQuantity,
              if (protectedItem != null) 'unit_price': protectedItem.unitPrice,
              if (protectedItem != null) 'total_price': protectedItem.lineTotal,
            };
          })
          .toList(growable: false);
    return SecureInterBranchInvoicePdfInput(
      data: safeData,
      showPrices: verifiedPrices != null,
    );
  }

  static Future<Uint8List> buildCashExpenseRequest({
    required Map<String, dynamic> data,
    required String branchName,
  }) async {
    final pdf = pw.Document();
    final theme = await _theme();
    final requestNumber = data['request_number']?.toString() ?? '-';
    final currency = data['currency']?.toString() ?? 'YER';
    final attachment = data['invoice_attachment'];
    final invoice = attachment is Map ? attachment : const {};
    final invoiceName = invoice['name']?.toString() ?? '';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: theme,
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.all(32),
        footer: _footer,
        build: (_) => [
          _documentHeader(
            title: 'سند صرف نقدي',
            subtitle: 'رقم السند: $requestNumber',
            branchName: branchName,
          ),
          pw.SizedBox(height: 18),
          _sectionTitle('بيانات السند'),
          _detailsGrid([
            ['رقم السند', requestNumber],
            ['الفرع', branchName],
            ['تاريخ الطلب', _date(data['created_at'], withTime: true)],
            ['عنوان المصروف', data['title']?.toString() ?? '-'],
            ['حالة السند', _cashExpenseStatus(data['status'])],
            [
              'المرجع المحاسبي',
              (data['accounting_reference']?.toString() ?? '').isEmpty
                  ? '-'
                  : data['accounting_reference'].toString(),
            ],
          ]),
          pw.SizedBox(height: 14),
          _cashExpenseAmountSummary(
            requestedAmount: _amount(data['requested_amount']),
            approvedAmount: _amount(data['approved_amount']),
            currency: currency,
          ),
          pw.SizedBox(height: 14),
          _sectionTitle('تفاصيل المصروف'),
          _noteBox('وصف المصروف', data['description']?.toString()),
          pw.SizedBox(height: 8),
          _sectionTitle('المرفق'),
          _detailsGrid([
            [
              'حالة الملف',
              (invoice['url']?.toString() ?? '').isEmpty
                  ? 'بدون ملف مرفق'
                  : 'ملف مرفق',
            ],
            ['اسم الملف', invoiceName.isEmpty ? '-' : invoiceName],
          ]),
          pw.SizedBox(height: 14),
          _sectionTitle('الملاحظات'),
          _noteBox('ملاحظات مدير الفرع', data['manager_notes']?.toString()),
          _noteBox(
            'ملاحظات المدير العام',
            data['general_manager_notes']?.toString(),
          ),
          _noteBox('ملاحظات الفاتورة', data['invoice_notes']?.toString()),
          _noteBox('ملاحظات المحاسب', data['accountant_notes']?.toString()),
          pw.SizedBox(height: 28),
          _signatures(),
        ],
      ),
    );
    return pdf.save();
  }

  static Future<void> printSecureInterBranchInvoice({
    required String invoiceId,
    required Map<String, dynamic> publicData,
    required UserRole audienceRole,
    InterBranchInvoicePriceSnapshot? priceSnapshot,
    List<Map<String, dynamic>>? itemDocuments,
  }) async {
    final bytes = await buildSecureInterBranchInvoice(
      invoiceId: invoiceId,
      publicData: publicData,
      audienceRole: audienceRole,
      priceSnapshot: priceSnapshot,
      itemDocuments: itemDocuments,
    );
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name:
          'فاتورة_فروع_${_safeName(publicData['invoice_number']?.toString() ?? 'جديدة')}.pdf',
    );
  }

  static Future<void> printInterBranchInvoice({
    required Map<String, dynamic> data,
    bool showPrices = false,
  }) async {
    final bytes = await buildInterBranchInvoice(
      data: data,
      showPrices: showPrices,
    );
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name:
          'فاتورة_فروع_${_safeName(data['invoice_number']?.toString() ?? 'جديدة')}.pdf',
    );
  }

  static Future<String?> saveInterBranchInvoice({
    required Map<String, dynamic> data,
    bool showPrices = false,
  }) async {
    final bytes = await buildInterBranchInvoice(
      data: data,
      showPrices: showPrices,
    );
    return FileSaver.instance.saveFile(
      name:
          'فاتورة_فروع_${_safeName(data['invoice_number']?.toString() ?? 'جديدة')}',
      bytes: bytes,
      fileExtension: 'pdf',
      mimeType: MimeType.pdf,
    );
  }

  static Future<void> printCashExpenseRequest({
    required Map<String, dynamic> data,
    required String branchName,
  }) async {
    final bytes = await buildCashExpenseRequest(
      data: data,
      branchName: branchName,
    );
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name:
          'سند_صرف_${_safeName(data['request_number']?.toString() ?? 'جديد')}.pdf',
    );
  }

  static Future<String?> saveCashExpenseRequest({
    required Map<String, dynamic> data,
    required String branchName,
  }) async {
    final bytes = await buildCashExpenseRequest(
      data: data,
      branchName: branchName,
    );
    return FileSaver.instance.saveFile(
      name:
          'سند_صرف_${_safeName(data['request_number']?.toString() ?? 'جديد')}',
      bytes: bytes,
      fileExtension: 'pdf',
      mimeType: MimeType.pdf,
    );
  }

  static Future<void> printSingleTransaction({
    required Map<String, dynamic> data,
    required String branchName,
  }) async {
    final bytes = await buildSingleTransaction(
      data: data,
      branchName: branchName,
    );
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name:
          'سند_${_safeName(data['transaction_number']?.toString() ?? 'جديد')}.pdf',
    );
  }

  static Future<String?> saveSingleTransaction({
    required Map<String, dynamic> data,
    required String branchName,
  }) async {
    final bytes = await buildSingleTransaction(
      data: data,
      branchName: branchName,
    );
    return FileSaver.instance.saveFile(
      name:
          'سند_${_safeName(data['transaction_number']?.toString() ?? 'جديد')}',
      bytes: bytes,
      fileExtension: 'pdf',
      mimeType: MimeType.pdf,
    );
  }

  static Future<void> printTransactionsReport({
    required List<QueryDocumentSnapshot> transactions,
    required String branchName,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final bytes = await buildTransactionsReport(
      transactions: transactions,
      branchName: branchName,
      startDate: startDate,
      endDate: endDate,
    );
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: _reportName(branchName, startDate, endDate),
    );
  }

  static Future<String?> saveTransactionsReport({
    required List<QueryDocumentSnapshot> transactions,
    required String branchName,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final bytes = await buildTransactionsReport(
      transactions: transactions,
      branchName: branchName,
      startDate: startDate,
      endDate: endDate,
    );
    return FileSaver.instance.saveFile(
      name: _reportName(branchName, startDate, endDate).replaceAll('.pdf', ''),
      bytes: bytes,
      fileExtension: 'pdf',
      mimeType: MimeType.pdf,
    );
  }

  static String _reportName(
    String branchName,
    DateTime startDate,
    DateTime endDate,
  ) =>
      'تقرير_${_safeName(branchName)}_${DateFormat('yyyyMMdd').format(startDate)}_${DateFormat('yyyyMMdd').format(endDate)}.pdf';

  static pw.Widget _documentHeader({
    required String title,
    required String subtitle,
    required String branchName,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: PdfColors.blueGrey50,
        border: pw.Border.all(color: PdfColors.blueGrey200),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                title,
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blueGrey900,
                ),
              ),
              pw.Text(subtitle, style: const pw.TextStyle(fontSize: 10)),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'تحصيل الكاشير',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text('الفرع: $branchName'),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _sectionTitle(String title) => pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    margin: const pw.EdgeInsets.only(bottom: 8),
    color: PdfColors.blueGrey100,
    child: pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
  );

  static pw.Widget _detailsGrid(List<List<String>> rows) => pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey300),
    children: rows
        .map(
          (row) => pw.TableRow(
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.all(7),
                child: pw.Text(
                  row[0],
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(7),
                child: pw.Text(row[1]),
              ),
            ],
          ),
        )
        .toList(),
  );

  static pw.Widget _amountSummary({
    required String amount,
    required String currency,
    required String amountMatchStatus,
    required String? cashierAmount,
    required String? amountDifference,
  }) {
    final isMatched = amountMatchStatus == 'matched';
    final isUnmatched = amountMatchStatus == 'unmatched';
    final borderColor = isMatched
        ? PdfColors.green300
        : isUnmatched
        ? PdfColors.orange400
        : PdfColors.grey500;
    final matchText = isMatched
        ? 'مبلغ الكاشير مطابق'
        : isUnmatched
        ? 'مبلغ الكاشير غير مطابق'
        : 'مبلغ الكاشير غير مراجع';
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: borderColor),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            '$amount $currency',
            style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(matchText),
              if (isUnmatched && cashierAmount != null)
                pw.Text('الموجود على الكاشير: $cashierAmount $currency'),
              if (isUnmatched && amountDifference != null)
                pw.Text('الفرق: $amountDifference $currency'),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _cashExpenseAmountSummary({
    required String requestedAmount,
    required String approvedAmount,
    required String currency,
  }) {
    final changed = requestedAmount != approvedAmount;
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
          color: changed ? PdfColors.orange400 : PdfColors.green300,
        ),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('المبلغ المطلوب'),
              pw.Text(
                '$requestedAmount $currency',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('المبلغ المعتمد'),
              pw.Text(
                '$approvedAmount $currency',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(changed ? 'تم تعديل المبلغ' : 'بدون تعديل'),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _noteBox(String title, String? note) => pw.Container(
    width: double.infinity,
    margin: const pw.EdgeInsets.only(bottom: 7),
    padding: const pw.EdgeInsets.all(9),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey300),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.Text(
          (note == null || note.trim().isEmpty) ? 'لا توجد ملاحظات' : note,
        ),
      ],
    ),
  );

  static pw.Widget _summaryCard(String label, String value) => pw.Expanded(
    child: pw.Container(
      margin: const pw.EdgeInsets.symmetric(horizontal: 3),
      padding: const pw.EdgeInsets.all(9),
      decoration: pw.BoxDecoration(
        color: PdfColors.indigo50,
        border: pw.Border.all(color: PdfColors.indigo100),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      ),
      child: pw.Column(
        children: [
          pw.Text(value, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
        ],
      ),
    ),
  );

  static pw.Widget _signatures() => pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
    children: [
      pw.Text(
        'توقيع المدير العام\n........................',
        textAlign: pw.TextAlign.center,
      ),
      pw.Text(
        'توقيع مدير الفرع\n........................',
        textAlign: pw.TextAlign.center,
      ),
      pw.Text(
        'اعتماد المحاسب\n........................',
        textAlign: pw.TextAlign.center,
      ),
    ],
  );

  static pw.Widget _footer(pw.Context context) => pw.Container(
    alignment: pw.Alignment.center,
    margin: const pw.EdgeInsets.only(top: 10),
    child: pw.Text(
      'صفحة ${context.pageNumber} من ${context.pagesCount}',
      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
    ),
  );
}
