import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:store_collection_app/services/pdf_service.dart';
import 'package:store_collection_app/theme/app_theme.dart';

class TransactionDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> transactionData;
  final String transactionId;

  const TransactionDetailsScreen({
    super.key,
    required this.transactionData,
    required this.transactionId,
  });

  String _getStatusText(String status) {
    switch (status) {
      case 'pending': return 'قيد الانتظار (سند جديد)';
      case 'approvedByCollector': return 'معتمد من المحصل';
      case 'approvedByManager': return 'تم الاعتماد من المدير';
      case 'approvedByAccountant': return 'تم الاعتماد النهائي (المحاسب)';
      case 'editRequestedByCollector': return 'معلق - مطلوب تعديله من المحصل';
      case 'pendingApprovalOfEdit': return 'تعديل بانتظار موافقة المدير';
      case 'rejectedByManager': return 'مرفوض';
      default: return 'غير معروف';
    }
  }

  @override
  Widget build(BuildContext context) {
    final double amount = (transactionData['amount'] as num?)?.toDouble() ?? 0.0;
    final String currency = transactionData['currency'] ?? 'YER';
    final String trnNumber = transactionData['transaction_number'] ?? '#';
    final String status = transactionData['status'] ?? 'pending';
    final String notes = transactionData['notes'] ?? 'لا توجد ملاحظات';
    final String managerNotes = transactionData['manager_notes'] ?? '';
    
    final dateFrom = (transactionData['dateFrom'] as Timestamp?)?.toDate();
    final dateTo = (transactionData['dateTo'] as Timestamp?)?.toDate();
    final creationDate = (transactionData['timestamp'] as Timestamp?)?.toDate();

    List<dynamic> history = transactionData['history'] ?? [];
    List<Map<String, dynamic>> sortedHistory = List<Map<String, dynamic>>.from(history);
    sortedHistory.sort((a, b) {
      final tA = (a['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
      final tB = (b['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
      return tB.compareTo(tA);
    });

    final Color statusColor = AppTheme.statusColor(status);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(
          title: const Text('تفاصيل السند', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          backgroundColor: Colors.blueGrey.shade800,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.print_rounded),
              tooltip: 'طباعة السند كـ PDF',
              onPressed: () async {
                await PdfService.printSingleTransaction(
                  data: transactionData,
                  branchName: 'الفرع المختار',
                );
              },
            )
          ],
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
              decoration: BoxDecoration(
                color: Colors.blueGrey.shade800,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  Text('سند #$trnNumber', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                  const SizedBox(height: 8),
                  Text(
                    '${NumberFormat('#,##0.##', 'en_US').format(amount)} $currency',
                    style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _getStatusText(status),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // بطاقة التواريخ
                    const Text('التواريخ والفترة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                    const SizedBox(height: 12),
                    Container(
                      decoration: AppTheme.cardShadow(),
                      child: Material(
                        color: AppTheme.cardColor,
                        borderRadius: BorderRadius.circular(16),
                        child: Column(
                          children: [
                            ListTile(
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: Colors.teal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                                child: const Icon(Icons.date_range_rounded, color: Colors.teal, size: 20),
                              ),
                              title: const Text('فترة التحصيل (من - إلى)', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                              subtitle: Text(
                                '${dateFrom != null ? DateFormat('yyyy/MM/dd').format(dateFrom) : ''}  -  ${dateTo != null ? DateFormat('yyyy/MM/dd').format(dateTo) : ''}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textPrimary),
                              ),
                            ),
                            const Divider(height: 1, indent: 60),
                            ListTile(
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                                child: const Icon(Icons.access_time_rounded, color: Colors.grey, size: 20),
                              ),
                              title: const Text('تاريخ ووقت الإدخال في النظام', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                              subtitle: Text(
                                creationDate != null ? DateFormat('yyyy/MM/dd - hh:mm a').format(creationDate) : '',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.textPrimary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // بطاقة الملاحظات
                    const Text('الملاحظات', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                    const SizedBox(height: 12),
                    Container(
                      decoration: AppTheme.cardShadow(),
                      child: Material(
                        color: AppTheme.cardColor,
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.notes_rounded, color: AppTheme.textHint, size: 20),
                                  const SizedBox(width: 8),
                                  const Text('ملاحظات المحصل:', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(notes, style: const TextStyle(fontSize: 15, color: AppTheme.textPrimary, height: 1.4)),
                              
                              if (managerNotes.isNotEmpty) ...[
                                const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1)),
                                Row(
                                  children: [
                                    Icon(Icons.admin_panel_settings_rounded, color: Colors.red.shade400, size: 20),
                                    const SizedBox(width: 8),
                                    const Text('رد / ملاحظات الإدارة:', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(managerNotes, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary, height: 1.4)),
                              ]
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // القسم الجديد: سجل حركات السند (Audit Trail)
                    const Text('سجل الحركات (Audit Trail)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                    const SizedBox(height: 12),
                    if (sortedHistory.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(32),
                        alignment: Alignment.center,
                        child: Column(
                          children: [
                            Icon(Icons.history_rounded, size: 48, color: AppTheme.textHint.withValues(alpha: 0.5)),
                            const SizedBox(height: 8),
                            const Text('لا يوجد سجل حركات لهذا السند', style: TextStyle(color: AppTheme.textSecondary)),
                          ],
                        ),
                      )
                    else
                      ...sortedHistory.map((item) => _buildTimelineItem(item)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // بناء عنصر واحد في السجل الزمني
  Widget _buildTimelineItem(Map<String, dynamic> item) {
    final action = item['action'] as String?;
    final message = item['message'] as String? ?? '';
    final timestamp = (item['timestamp'] as Timestamp?)?.toDate();
    final changes = item['changes'] as Map<String, dynamic>?;

    IconData icon;
    Color color;
    
    switch(action) {
      case 'created': icon = Icons.add_circle_rounded; color = Colors.blue; break;
      case 'status_update': icon = Icons.sync_rounded; color = Colors.orange; break;
      case 'edit_requested': icon = Icons.edit_note_rounded; color = Colors.purple; break;
      case 'edit_approved': icon = Icons.check_circle_rounded; color = Colors.green; break;
      case 'edit_requested_by_accountant': icon = Icons.assignment_return_rounded; color = Colors.redAccent; break;
      case 'approved_by_accountant': icon = Icons.verified_user_rounded; color = Colors.green.shade800; break;
      case 'edit_request_rejected': icon = Icons.cancel_rounded; color = Colors.red; break;
      default: icon = Icons.info_outline_rounded; color = Colors.grey;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textPrimary)),
                  const SizedBox(height: 6),
                  if (timestamp != null)
                    Text(DateFormat('yyyy/MM/dd - hh:mm a').format(timestamp), style: const TextStyle(color: AppTheme.textHint, fontSize: 12)),
                  
                  if (changes != null)
                    _buildChangesDetails(changes),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // بناء مربع تفاصيل التعديل
  Widget _buildChangesDetails(Map<String, dynamic> changes) {
    final oldAmount = (changes['oldAmount'] as num?)?.toDouble() ?? 0.0;
    final newAmount = (changes['newAmount'] as num?)?.toDouble() ?? 0.0;
    final oldCur = changes['oldCurrency'] ?? '';
    final newCur = changes['newCurrency'] ?? '';

    final oldDateFrom = (changes['oldDateFrom'] as Timestamp?)?.toDate();
    final newDateFrom = (changes['newDateFrom'] as Timestamp?)?.toDate();
    
    final oldDateTo = (changes['oldDateTo'] as Timestamp?)?.toDate();
    final newDateTo = (changes['newDateTo'] as Timestamp?)?.toDate();

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.purple.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.purple.withValues(alpha: 0.15))
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('تفاصيل التعديل المقترح:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple, fontSize: 12)),
          const SizedBox(height: 6),
          const Divider(height: 1, color: Colors.black12),
          const SizedBox(height: 6),
          
          if (oldAmount != newAmount || oldCur != newCur)
            _buildChangeRow('المبلغ:', '${NumberFormat('#,##0.##', 'en_US').format(oldAmount)} $oldCur', '${NumberFormat('#,##0.##', 'en_US').format(newAmount)} $newCur'),
          
          if (oldDateFrom != newDateFrom)
            _buildChangeRow('من تاريخ:', oldDateFrom != null ? DateFormat('yyyy/MM/dd').format(oldDateFrom) : '', newDateFrom != null ? DateFormat('yyyy/MM/dd').format(newDateFrom) : ''),
            
          if (oldDateTo != newDateTo)
            _buildChangeRow('إلى تاريخ:', oldDateTo != null ? DateFormat('yyyy/MM/dd').format(oldDateTo) : '', newDateTo != null ? DateFormat('yyyy/MM/dd').format(newDateTo) : ''),
        ],
      ),
    );
  }

  Widget _buildChangeRow(String label, String oldVal, String newVal) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textSecondary)),
          const SizedBox(width: 8),
          Expanded(child: Text(oldVal, style: const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.red, fontSize: 12))),
          const Icon(Icons.arrow_back_rounded, size: 14, color: AppTheme.textHint),
          const SizedBox(width: 8),
          Expanded(child: Text(newVal, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12))),
        ],
      ),
    );
  }
}