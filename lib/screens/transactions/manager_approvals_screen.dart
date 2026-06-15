import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:store_collection_app/services/database_service.dart';
import 'package:store_collection_app/theme/app_theme.dart';
import 'package:store_collection_app/utils/transaction_records.dart';
import 'package:store_collection_app/utils/firestore_refresh.dart';

class ManagerApprovalsScreen extends StatefulWidget {
  final String branchId;
  final String branchName;

  const ManagerApprovalsScreen({
    super.key,
    required this.branchId,
    required this.branchName,
  });

  @override
  State<ManagerApprovalsScreen> createState() => _ManagerApprovalsScreenState();
}

class _ManagerApprovalsScreenState extends State<ManagerApprovalsScreen> {
  final DatabaseService _dbService = DatabaseService();

  // --- دوال تبويبة الطلبات الجديدة ---

  Future<void> _approveNewTransaction(
    String transactionId,
    String trnNumber,
  ) async {
    _showLoadingDialog();
    try {
      await _dbService.updateTransactionStatus(
        transactionId: transactionId,
        newStatus: 'approvedByManager',
      );
      _closeLoadingAndShowSnackBar(
        'تم اعتماد السند رقم $trnNumber بنجاح',
        Colors.green,
      );
    } catch (e) {
      _closeLoadingAndShowSnackBar('حدث خطأ أثناء الاعتماد', Colors.red);
    }
  }

  Future<void> _rejectTransaction(
    String transactionId,
    String trnNumber,
    String actionType,
  ) async {
    TextEditingController notesController = TextEditingController();

    // actionType: 'reject' (رفض نهائي) أو 'edit' (طلب تعديل من المحصل)
    bool isReject = actionType == 'reject';

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                isReject ? Icons.cancel_rounded : Icons.edit_note_rounded,
                color: isReject ? Colors.red : Colors.orange,
              ),
              const SizedBox(width: 8),
              Text(
                isReject ? 'رفض السند' : 'طلب تعديل السند',
                style: TextStyle(
                  color: isReject ? Colors.red : Colors.orange,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          content: TextField(
            controller: notesController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: isReject
                  ? 'اكتب سبب الرفض هنا...'
                  : 'اكتب التعديلات المطلوبة...',
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: isReject ? Colors.red : Colors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () async {
                if (notesController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('الرجاء إدخال السبب/الملاحظة'),
                    ),
                  );
                  return;
                }

                Navigator.pop(context);
                _showLoadingDialog();

                try {
                  await _dbService.updateTransactionStatus(
                    transactionId: transactionId,
                    newStatus: isReject
                        ? 'rejectedByManager'
                        : 'editRequestedByCollector',
                    managerNotes: notesController.text.trim(),
                  );
                  _closeLoadingAndShowSnackBar(
                    isReject
                        ? 'تم رفض السند $trnNumber'
                        : 'تم إرسال طلب تعديل للسند $trnNumber',
                    isReject ? Colors.red : Colors.orange,
                  );
                } catch (e) {
                  _closeLoadingAndShowSnackBar(
                    'حدث خطأ أثناء تنفيذ العملية',
                    Colors.red,
                  );
                }
              },
              icon: Icon(
                isReject ? Icons.block_rounded : Icons.send_rounded,
                size: 18,
              ),
              label: Text(isReject ? 'تأكيد الرفض' : 'إرسال للمحصل'),
            ),
          ],
        );
      },
    );
  }

  // --- دوال تبويبة طلبات التعديل ---

  Future<void> _approveEdit(
    String transactionId,
    String trnNumber,
    Map<String, dynamic> pendingData,
  ) async {
    _showLoadingDialog();
    try {
      await _dbService.approveEditRequest(
        transactionId: transactionId,
        pendingData: pendingData,
      );
      _closeLoadingAndShowSnackBar(
        'تم اعتماد التعديلات للسند $trnNumber بنجاح',
        Colors.green,
      );
    } catch (e) {
      _closeLoadingAndShowSnackBar(
        'حدث خطأ أثناء اعتماد التعديلات',
        Colors.red,
      );
    }
  }

  Future<void> _rejectEdit(String transactionId, String trnNumber) async {
    _showLoadingDialog();
    try {
      await _dbService.updateTransactionStatus(
        transactionId: transactionId,
        newStatus: 'editRequestedByCollector',
        managerNotes:
            'تم رفض التعديل الأخير، يرجى مراجعة البيانات وإعادة الإرسال بدقة.',
      );
      _closeLoadingAndShowSnackBar(
        'تم رفض التعديل وإعادته للمحصل',
        Colors.orange,
      );
    } catch (e) {
      _closeLoadingAndShowSnackBar('حدث خطأ أثناء الرفض', Colors.red);
    }
  }

  // --- دوال مساعدة ---

  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const CircularProgressIndicator(color: AppTheme.managerColor),
        ),
      ),
    );
  }

  void _closeLoadingAndShowSnackBar(String message, Color color) {
    if (mounted) {
      Navigator.pop(context); // إغلاق التحميل
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: AppTheme.surfaceColor,
          appBar: AppBar(
            title: Text(
              'الاعتمادات - ${widget.branchName}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            backgroundColor: AppTheme.managerColor,
            elevation: 0,
            bottom: const TabBar(
              indicatorColor: Colors.white,
              indicatorWeight: 4,
              labelStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              unselectedLabelStyle: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
              ),
              tabs: [
                Tab(
                  text: 'سندات جديدة',
                  icon: Icon(Icons.new_releases_rounded),
                ),
                Tab(
                  text: 'طلبات تعديل',
                  icon: Icon(Icons.edit_notifications_rounded),
                ),
              ],
            ),
          ),
          body: TabBarView(
            children: [_buildNewTransactionsTab(), _buildEditRequestsTab()],
          ),
        ),
      ),
    );
  }

  // 1. تبويبة السندات الجديدة
  Widget _buildNewTransactionsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _dbService.getBranchTransactions(branchId: widget.branchId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.managerColor),
          );
        if (snapshot.hasError)
          return const Center(
            child: Text(
              'حدث خطأ في جلب البيانات.',
              style: TextStyle(color: Colors.red),
            ),
          );
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.done_all_rounded,
                  size: 64,
                  color: AppTheme.textHint.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 16),
                const Text(
                  'لا توجد طلبات اعتماد معلقة حالياً!',
                  style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
                ),
              ],
            ),
          );
        }

        final transactions = filterAndSortTransactionRecords(
          records: snapshot.data!.docs,
          dataOf: (doc) => doc.data() as Map<String, dynamic>,
          filters: const TransactionRecordFilters(status: 'pending'),
        );

        if (transactions.isEmpty) {
          return const Center(
            child: Text('لا توجد طلبات اعتماد معلقة حالياً!'),
          );
        }

        return RefreshIndicator(
          onRefresh: () => refreshFirestoreQueries([
            FirebaseFirestore.instance
                .collection('transactions')
                .where('branchId', isEqualTo: widget.branchId),
          ]),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: transactions.length,
            itemBuilder: (context, index) {
              final doc = transactions[index];
              final data = doc.data() as Map<String, dynamic>;

              final double amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
              final String currency = data['currency'] ?? 'YER';
              final String trnNumber = data['transaction_number'] ?? '#';
              final DateTime? dateFrom = (data['dateFrom'] as Timestamp?)
                  ?.toDate();
              final DateTime? dateTo = (data['dateTo'] as Timestamp?)?.toDate();

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: AppTheme.cardShadow(),
                child: Material(
                  color: AppTheme.cardColor,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'سند #$trnNumber',
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.managerColor.withValues(
                                  alpha: 0.1,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'جديد',
                                style: TextStyle(
                                  color: AppTheme.managerColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${NumberFormat('#,##0.##', 'en_US').format(amount)} $currency',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildDatePeriod(
                          title: 'فترة التحصيل',
                          dateFrom: dateFrom,
                          dateTo: dateTo,
                          color: AppTheme.managerColor,
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Divider(height: 1, thickness: 1),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () =>
                                    _approveNewTransaction(doc.id, trnNumber),
                                icon: const Icon(
                                  Icons.check_circle_rounded,
                                  size: 18,
                                ),
                                label: const Text('اعتماد'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _rejectTransaction(
                                  doc.id,
                                  trnNumber,
                                  'reject',
                                ),
                                icon: const Icon(
                                  Icons.cancel_rounded,
                                  size: 18,
                                ),
                                label: const Text('رفض'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  side: BorderSide(
                                    color: Colors.red.withValues(alpha: 0.5),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                _rejectTransaction(doc.id, trnNumber, 'edit'),
                            icon: const Icon(Icons.edit_note_rounded, size: 18),
                            label: const Text('طلب تعديل من المحصل'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.orange,
                              side: BorderSide(
                                color: Colors.orange.withValues(alpha: 0.5),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  // 2. تبويبة طلبات التعديل
  Widget _buildEditRequestsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _dbService.getBranchTransactions(branchId: widget.branchId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.managerColor),
          );
        if (snapshot.hasError)
          return const Center(
            child: Text(
              'حدث خطأ في جلب البيانات.',
              style: TextStyle(color: Colors.red),
            ),
          );
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.fact_check_outlined,
                  size: 64,
                  color: AppTheme.textHint.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 16),
                const Text(
                  'لا توجد طلبات تعديل للمراجعة.',
                  style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
                ),
              ],
            ),
          );
        }

        final transactions = filterAndSortTransactionRecords(
          records: snapshot.data!.docs,
          dataOf: (doc) => doc.data() as Map<String, dynamic>,
          filters: const TransactionRecordFilters(
            status: 'pendingApprovalOfEdit',
          ),
        );

        if (transactions.isEmpty) {
          return const Center(child: Text('لا توجد طلبات تعديل للمراجعة.'));
        }

        return RefreshIndicator(
          onRefresh: () => refreshFirestoreQueries([
            FirebaseFirestore.instance
                .collection('transactions')
                .where('branchId', isEqualTo: widget.branchId),
          ]),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: transactions.length,
            itemBuilder: (context, index) {
              final doc = transactions[index];
              final data = doc.data() as Map<String, dynamic>;
              final pendingData =
                  data['pending_edit_data'] as Map<String, dynamic>? ?? {};

              final String trnNumber = data['transaction_number'] ?? '#';

              // البيانات القديمة
              final double oldAmount =
                  (data['amount'] as num?)?.toDouble() ?? 0.0;
              final String oldCurrency = data['currency'] ?? 'YER';

              // البيانات الجديدة
              final double newAmount =
                  (pendingData['amount'] as num?)?.toDouble() ?? 0.0;
              final String newCurrency = pendingData['currency'] ?? oldCurrency;
              final String newNotes =
                  pendingData['notes'] ?? 'لا توجد ملاحظات للتعديل';
              final DateTime? oldDateFrom = (data['dateFrom'] as Timestamp?)
                  ?.toDate();
              final DateTime? oldDateTo = (data['dateTo'] as Timestamp?)
                  ?.toDate();
              final DateTime? newDateFrom =
                  (pendingData['dateFrom'] as Timestamp?)?.toDate();
              final DateTime? newDateTo = (pendingData['dateTo'] as Timestamp?)
                  ?.toDate();

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppTheme.cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'سند #$trnNumber',
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'مراجعة تعديل',
                              style: TextStyle(
                                color: Colors.orange,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Divider(height: 1, thickness: 1),
                      ),

                      // المقارنة بين القديم والجديد
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.red.withValues(alpha: 0.1),
                                ),
                              ),
                              child: Column(
                                children: [
                                  const Text(
                                    'المبلغ القديم',
                                    style: TextStyle(
                                      color: Colors.red,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${NumberFormat('#,##0.##', 'en_US').format(oldAmount)} $oldCurrency',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textSecondary,
                                      decoration: TextDecoration.lineThrough,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10.0,
                            ),
                            child: Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.grey.shade400,
                              size: 20,
                            ),
                          ),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.green.withValues(alpha: 0.1),
                                ),
                              ),
                              child: Column(
                                children: [
                                  const Text(
                                    'المبلغ المقترح',
                                    style: TextStyle(
                                      color: Colors.green,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${NumberFormat('#,##0.##', 'en_US').format(newAmount)} $newCurrency',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildDatePeriod(
                              title: 'الفترة الحالية',
                              dateFrom: oldDateFrom,
                              dateTo: oldDateTo,
                              color: Colors.red,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildDatePeriod(
                              title: 'الفترة المقترحة',
                              dateFrom: newDateFrom,
                              dateTo: newDateTo,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.notes_rounded,
                              color: Colors.grey.shade600,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'ملاحظات المحصل: $newNotes',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: ElevatedButton.icon(
                              onPressed: () =>
                                  _approveEdit(doc.id, trnNumber, pendingData),
                              icon: const Icon(
                                Icons.check_circle_rounded,
                                size: 18,
                              ),
                              label: const Text('اعتماد التعديل'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: OutlinedButton.icon(
                              onPressed: () => _rejectEdit(doc.id, trnNumber),
                              icon: const Icon(Icons.cancel_rounded, size: 18),
                              label: const Text('رفض وإعادة'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: BorderSide(
                                  color: Colors.red.withValues(alpha: 0.5),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildDatePeriod({
    required String title,
    required DateTime? dateFrom,
    required DateTime? dateTo,
    required Color color,
  }) {
    final formatter = DateFormat('yyyy/MM/dd');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.date_range_rounded, color: color, size: 17),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'من: ${dateFrom == null ? 'غير محدد' : formatter.format(dateFrom)}',
            style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 3),
          Text(
            'إلى: ${dateTo == null ? 'غير محدد' : formatter.format(dateTo)}',
            style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
          ),
        ],
      ),
    );
  }
}
