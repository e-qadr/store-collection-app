import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PdfService {
  // دالة جلب الخط العربي
  static Future<pw.Font> _getArabicFont() async {
    return await PdfGoogleFonts.cairoRegular();
  }

  static Future<pw.Font> _getArabicBoldFont() async {
    return await PdfGoogleFonts.cairoBold();
  }

  // 1. طباعة سند مفرد
  static Future<void> printSingleTransaction({
    required Map<String, dynamic> data,
    required String branchName,
  }) async {
    final font = await _getArabicFont();
    final fontBold = await _getArabicBoldFont();

    final pdf = pw.Document();

    final double amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
    final String currency = data['currency'] ?? 'YER';
    final String trnNumber = data['transaction_number'] ?? '#';
    final String notes = data['notes'] ?? 'لا توجد ملاحظات';
    
    final dateFrom = (data['dateFrom'] as Timestamp?)?.toDate();
    final dateTo = (data['dateTo'] as Timestamp?)?.toDate();
    final creationDate = (data['timestamp'] as Timestamp?)?.toDate();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        textDirection: pw.TextDirection.rtl, // تحديد اتجاه النص للعربية
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // الترويسة
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey)),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('مؤسسة المتجر الإلكتروني', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                        pw.Text('فرع: $branchName', style: const pw.TextStyle(fontSize: 16)),
                      ]
                    ),
                    pw.Text('سند تحصيل مالي', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
                  ]
                )
              ),
              pw.SizedBox(height: 30),

              // التفاصيل
              _buildPdfRow('رقم السند:', trnNumber),
              _buildPdfRow('تاريخ الإدخال:', creationDate != null ? DateFormat('yyyy/MM/dd').format(creationDate) : ''),
              _buildPdfRow('المبلغ:', '${NumberFormat('#,##0.##', 'en_US').format(amount)} $currency'),
              _buildPdfRow('فترة التحصيل:', '${dateFrom != null ? DateFormat('yyyy/MM/dd').format(dateFrom) : ''} إلى ${dateTo != null ? DateFormat('yyyy/MM/dd').format(dateTo) : ''}'),
              _buildPdfRow('ملاحظات المحصل:', notes),
              
              pw.SizedBox(height: 50),
              
              // التواقيع
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  pw.Text('توقيع المحصل\n......................', textAlign: pw.TextAlign.center),
                  pw.Text('توقيع مدير الفرع\n......................', textAlign: pw.TextAlign.center),
                  pw.Text('اعتماد المحاسب\n......................', textAlign: pw.TextAlign.center),
                ]
              )
            ],
          );
        },
      ),
    );

    // عرض معاينة السند للطباعة أو الحفظ
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Transaction_$trnNumber.pdf',
    );
  }

  // 2. طباعة تقرير جدول السندات لفترة معينة
  static Future<void> printTransactionsReport({
    required List<QueryDocumentSnapshot> transactions,
    required String branchName,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final font = await _getArabicFont();
    final fontBold = await _getArabicBoldFont();

    final pdf = pw.Document();

    // إعداد بيانات الجدول
    final headers = ['الحالة', 'الملاحظات', 'إلى تاريخ', 'من تاريخ', 'العملة', 'المبلغ', 'رقم السند'];
    
    final data = transactions.map((doc) {
      final t = doc.data() as Map<String, dynamic>;
      final amount = (t['amount'] as num?)?.toDouble() ?? 0.0;
      final currency = t['currency'] ?? '';
      final dFrom = (t['dateFrom'] as Timestamp?)?.toDate();
      final dTo = (t['dateTo'] as Timestamp?)?.toDate();
      
      String status = 'غير معروف';
      if(t['status'] == 'approvedByAccountant') {
        status = 'معتمد محاسب';
      } else if(t['status'] == 'approvedByManager') status = 'معتمد مدير';
      else if(t['status'] == 'pending') status = 'قيد الانتظار';
      else status = 'مراجعة/تعديل';

      return [
        status,
        t['notes']?.toString() ?? '',
        dTo != null ? DateFormat('yyyy/MM/dd').format(dTo) : '',
        dFrom != null ? DateFormat('yyyy/MM/dd').format(dFrom) : '',
        currency,
        NumberFormat('#,##0.##', 'en_US').format(amount),
        t['transaction_number'] ?? '',
      ];
    }).toList();

    pdf.addPage(
      pw.MultiPage( // MultiPage يسمح بتقسيم الجدول على عدة صفحات إذا كان طويلاً
        pageFormat: PdfPageFormat.a4.landscape, // صفحة بالعرض لتسع الجدول
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        textDirection: pw.TextDirection.rtl,
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('تقرير سندات التحصيل - فرع $branchName', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo)),
            pw.Text('للفترة من ${DateFormat('yyyy/MM/dd').format(startDate)} إلى ${DateFormat('yyyy/MM/dd').format(endDate)}', style: const pw.TextStyle(fontSize: 14)),
            pw.SizedBox(height: 20),
          ]
        ),
        build: (pw.Context context) {
          return [
            pw.TableHelper.fromTextArray(
              headers: headers,
              data: data,
              border: pw.TableBorder.all(color: PdfColors.grey),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo300),
              cellAlignment: pw.Alignment.center,
              cellStyle: const pw.TextStyle(fontSize: 10),
              cellPadding: const pw.EdgeInsets.all(5),
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Report_${branchName}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  // أداة مساعدة لرسم صفوف السند المفرد
  static pw.Widget _buildPdfRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 8),
      child: pw.Row(
        children: [
          pw.Text(label, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
          pw.SizedBox(width: 15),
          pw.Text(value, style: const pw.TextStyle(fontSize: 14)),
        ]
      )
    );
  }
}