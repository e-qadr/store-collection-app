import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:store_collection_app/theme/app_theme.dart';
import 'package:store_collection_app/utils/transaction_records.dart';

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
    final amountMatches = data['amount_matches'] != false;
    final cashierAmount = (data['cashier_amount'] as num?)?.toDouble();
    final history =
        ((data['history'] as List?) ?? [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
          ..sort((a, b) {
            final aDate = transactionDate(a['timestamp']) ?? DateTime(2000);
            final bDate = transactionDate(b['timestamp']) ?? DateTime(2000);
            return aDate.compareTo(bDate);
          });

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
            ['المحصل', _actor(data)],
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
            amountMatches: amountMatches,
            cashierAmount: cashierAmount == null
                ? null
                : _amount(cashierAmount),
          ),
          pw.SizedBox(height: 14),
          _sectionTitle('الملاحظات'),
          _noteBox('ملاحظات المحصل', data['notes']?.toString()),
          if ((data['manager_notes']?.toString() ?? '').isNotEmpty)
            _noteBox('ملاحظات الإدارة', data['manager_notes']?.toString()),
          if (history.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            _sectionTitle('مراحل السند وسجل الحركات'),
            pw.TableHelper.fromTextArray(
              headers: const ['التاريخ', 'الدور', 'المستخدم', 'الإجراء'],
              data: history
                  .map(
                    (item) => [
                      _date(item['timestamp'], withTime: true),
                      _role(item['actor_role']),
                      item['actor_name']?.toString() ?? 'غير محدد',
                      item['message']?.toString() ?? 'تحديث السند',
                    ],
                  )
                  .toList(),
              border: pw.TableBorder.all(color: PdfColors.grey300),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.blueGrey700,
              ),
              headerStyle: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
                fontSize: 9,
              ),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellAlignment: pw.Alignment.centerRight,
              cellPadding: const pw.EdgeInsets.all(5),
            ),
          ],
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
              'المحصل',
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
                    data['amount_matches'] == false ? 'غير مطابق' : 'مطابق',
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
                'نظام سندات التحصيل',
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
    required bool amountMatches,
    required String? cashierAmount,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
          color: amountMatches ? PdfColors.green300 : PdfColors.orange400,
        ),
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
              pw.Text(
                amountMatches ? 'مبلغ الكاشير مطابق' : 'مبلغ الكاشير غير مطابق',
              ),
              if (!amountMatches && cashierAmount != null)
                pw.Text('الموجود على الكاشير: $cashierAmount $currency'),
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
        'توقيع المحصل\n........................',
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

  static String _role(dynamic role) {
    switch (role) {
      case 'admin':
        return 'مسؤول النظام';
      case 'collector':
        return 'المحصل';
      case 'manager':
        return 'مدير الفرع';
      case 'accountant':
        return 'المحاسب';
      default:
        return 'غير محدد';
    }
  }
}
