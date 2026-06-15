import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:store_collection_app/services/database_service.dart';
import 'package:store_collection_app/theme/app_theme.dart';
import 'package:store_collection_app/utils/transaction_records.dart';

class CollectorEditRequestsScreen extends StatefulWidget {
  final String branchId;
  final String branchName;

  const CollectorEditRequestsScreen({super.key, required this.branchId, required this.branchName});

  @override
  State<CollectorEditRequestsScreen> createState() => _CollectorEditRequestsScreenState();
}

class _CollectorEditRequestsScreenState extends State<CollectorEditRequestsScreen> {
  final DatabaseService _dbService = DatabaseService();

  // دالة التقويم الذكي
  Future<void> _pickDate(BuildContext context, bool isFromDate, DateTime? currentFrom, DateTime? currentTo, Function(DateTime) onPicked) async {
    DateTime initialDate = DateTime.now();
    DateTime firstDate = DateTime(2020);
    DateTime lastDate = DateTime.now().add(const Duration(days: 365));

    if (isFromDate) {
      if (currentTo != null) lastDate = currentTo;
      initialDate = currentFrom ?? DateTime.now();
      if (initialDate.isAfter(lastDate)) initialDate = lastDate;
    } else {
      if (currentFrom != null) firstDate = currentFrom;
      initialDate = currentTo ?? currentFrom ?? DateTime.now();
      if (initialDate.isBefore(firstDate)) initialDate = firstDate;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.orange,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) onPicked(picked);
  }

  // 1. دالة تعديل السند
  void _showEditDialog(BuildContext context, String transactionId, Map<String, dynamic> currentData) {
    final TextEditingController amountController = TextEditingController(text: currentData['amount'].toString());
    final TextEditingController notesController = TextEditingController(text: currentData['notes'] ?? '');
    String selectedCurrency = currentData['currency'] ?? 'YER';
    DateTime dateFrom = (currentData['dateFrom'] as Timestamp?)?.toDate() ?? DateTime.now();
    DateTime dateTo = (currentData['dateTo'] as Timestamp?)?.toDate() ?? DateTime.now();
    
    bool isSaving = false; 

    showDialog(
      context: context,
      barrierDismissible: false, 
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.edit_document, color: Colors.teal),
                  SizedBox(width: 8),
                  Text('تعديل السند', style: TextStyle(color: Colors.teal, fontSize: 18)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'المبلغ',
                        border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                      )
                    ),
                    const SizedBox(height: 15),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'العملة',
                        border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedCurrency,
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(value: 'YER', child: Text('ريال يمني (YER)')),
                            DropdownMenuItem(value: 'SAR', child: Text('ريال سعودي (SAR)')),
                            DropdownMenuItem(value: 'USD', child: Text('دولار (USD)')),
                          ],
                          onChanged: (val) { if (val != null) setDialogState(() => selectedCurrency = val); },
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade300)),
                      title: Text('من: ${DateFormat('yyyy/MM/dd').format(dateFrom)}', style: const TextStyle(fontSize: 14)),
                      trailing: const Icon(Icons.calendar_today_rounded, size: 20),
                      onTap: () => _pickDate(context, true, dateFrom, dateTo, (picked) => setDialogState(() => dateFrom = picked)),
                    ),
                    const SizedBox(height: 10),
                    ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade300)),
                      title: Text('إلى: ${DateFormat('yyyy/MM/dd').format(dateTo)}', style: const TextStyle(fontSize: 14)),
                      trailing: const Icon(Icons.calendar_today_rounded, size: 20),
                      onTap: () => _pickDate(context, false, dateFrom, dateTo, (picked) => setDialogState(() => dateTo = picked)),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: notesController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'ملاحظات المحصل',
                        border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                      )
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: isSaving ? null : () => Navigator.pop(context), child: const Text('إلغاء', style: TextStyle(color: Colors.red))),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: isSaving ? null : () async {
                    if (amountController.text.trim().isEmpty) return;
                    
                    final double? amount = double.tryParse(amountController.text.trim());
                    if (amount == null) return;

                    if (dateTo.isBefore(dateFrom)) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تاريخ (إلى) يجب أن يكون بعد أو يساوي تاريخ (من)'), backgroundColor: Colors.red));
                      return;
                    }

                    setDialogState(() => isSaving = true); 

                    try {
                      await _dbService.submitEditedTransaction(
                        transactionId: transactionId,
                        newAmount: amount,
                        newCurrency: selectedCurrency,
                        newDateFrom: dateFrom,
                        newDateTo: dateTo,
                        newNotes: notesController.text.trim(),
                      );
                      
                      if (context.mounted) {
                        Navigator.pop(context); 
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تعديل السند وإعادة إرساله بنجاح'), backgroundColor: Colors.green));
                      }
                    } catch (e) {
                      setDialogState(() => isSaving = false); 
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حدث خطأ أثناء التعديل'), backgroundColor: Colors.red));
                    }
                  },
                  icon: isSaving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.send_rounded, size: 18),
                  label: const Text('حفظ وإرسال'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // 2. دالة رفض طلب التعديل
  Future<void> _rejectEditRequest(String transactionId, Map<String, dynamic> data) async {
    TextEditingController reasonController = TextEditingController();
    bool isSubmitting = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.warning_rounded, color: Colors.red),
                  SizedBox(width: 8),
                  Text('رفض طلب التعديل', style: TextStyle(color: Colors.red, fontSize: 18)),
                ],
              ),
              content: TextField(
                controller: reasonController,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'اكتب سبب رفضك (مثلاً: السند والمبلغ صحيح)...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(context), 
                  child: const Text('إلغاء')
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: isSubmitting ? null : () async {
                    if (reasonController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الرجاء كتابة السبب')));
                      return;
                    }
                    
                    setDialogState(() => isSubmitting = true);
                    
                    // العودة للحالة السابقة
                    String returnStatus = data['previous_status'] ?? 'pending'; 
                    
                    try {
                      await _dbService.rejectEditRequestByCollector(
                        transactionId: transactionId,
                        rejectReason: reasonController.text.trim(),
                        returnToStatus: returnStatus,
                      );
                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال الرد بنجاح'), backgroundColor: Colors.green));
                      }
                    } catch (e) {
                      setDialogState(() => isSubmitting = false);
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حدث خطأ'), backgroundColor: Colors.red));
                    }
                  },
                  icon: isSubmitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.close_rounded, size: 18),
                  label: const Text('تأكيد الرفض'),
                )
              ]
            );
          }
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(
          title: const Text('سندات تتطلب تعديلاً', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          backgroundColor: Colors.orange.shade700,
          elevation: 0,
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: _dbService.getBranchTransactions(branchId: widget.branchId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return Center(child: CircularProgressIndicator(color: Colors.orange.shade700));
            if (snapshot.hasError) return const Center(child: Text('حدث خطأ في جلب البيانات.', style: TextStyle(color: Colors.red)));
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.task_alt_rounded, size: 80, color: Colors.green.shade300),
                    const SizedBox(height: 16),
                    const Text('عمل ممتاز!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                    const SizedBox(height: 8),
                    const Text('لا توجد أي سندات تتطلب التعديل حالياً.', style: TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
                  ],
                ),
              );
            }

            final transactions = filterAndSortTransactionRecords(
              records: snapshot.data!.docs,
              dataOf: (doc) => doc.data() as Map<String, dynamic>,
              filters: const TransactionRecordFilters(
                status: 'editRequestedByCollector',
              ),
            );

            if (transactions.isEmpty) {
              return const Center(
                child: Text('لا توجد أي سندات تتطلب التعديل حالياً.'),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: transactions.length,
              itemBuilder: (context, index) {
                final doc = transactions[index];
                final data = doc.data() as Map<String, dynamic>;

                final double rawAmount = (data['amount'] as num?)?.toDouble() ?? 0.0;
                final String formattedAmount = NumberFormat('#,##0.##', 'en_US').format(rawAmount);
                final String currency = data['currency'] ?? 'YER';
                final String trnNumber = data['transaction_number'] ?? '#';
                final String managerNotes = data['manager_notes'] ?? 'لا توجد ملاحظات مرفقة';
                
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.4), width: 1.5),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4)),
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
                            Text('سند #$trnNumber', style: const TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.bold, fontSize: 13)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text('مطلوب تعديل', style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$formattedAmount $currency',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                        const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1, thickness: 1)),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.info_outline_rounded, color: Colors.orange.shade800, size: 18),
                                  const SizedBox(width: 8),
                                  Text('ملاحظات الإدارة:', style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.bold, fontSize: 13)),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(managerNotes, style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary, height: 1.4)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // أزرار الإجراءات
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: ElevatedButton.icon(
                                onPressed: () => _showEditDialog(context, doc.id, data),
                                icon: const Icon(Icons.edit_rounded, size: 18),
                                label: const Text('تعديل وإرسال'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.teal,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: OutlinedButton.icon(
                                onPressed: () => _rejectEditRequest(doc.id, data),
                                icon: const Icon(Icons.close_rounded, size: 18),
                                label: const Text('السند صحيح'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  side: BorderSide(color: Colors.red.withValues(alpha: 0.5)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
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
            );
          },
        ),
      ),
    );
  }
}
