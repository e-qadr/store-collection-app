import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:store_collection_app/services/database_service.dart';
import 'package:store_collection_app/screens/transactions/transaction_details_screen.dart';
import 'package:store_collection_app/theme/app_theme.dart';
import 'package:store_collection_app/utils/transaction_records.dart';

class BranchTransactionsScreen extends StatefulWidget {
  final String branchId;
  final String branchName;

  const BranchTransactionsScreen({
    super.key,
    required this.branchId,
    required this.branchName,
  });

  @override
  State<BranchTransactionsScreen> createState() =>
      _BranchTransactionsScreenState();
}

class _BranchTransactionsScreenState extends State<BranchTransactionsScreen> {
  final DatabaseService _dbService = DatabaseService();
  String? _currentUserRole;
  bool _isLoadingRole = true;

  // الفلاتر الأساسية
  String? _selectedCurrency;
  String? _selectedStatus;

  // فلتر تاريخ الإدخال (Timestamp)
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;

  // فلتر فترة التحصيل (DateFrom - DateTo)
  DateTime? _periodStartDate;
  DateTime? _periodEndDate;

  @override
  void initState() {
    super.initState();
    _fetchUserRole();
  }

  Future<void> _fetchUserRole() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (mounted) {
        setState(() {
          _currentUserRole = doc.data()?['role'];
          _isLoadingRole = false;
        });
      }
    } else {
      if (mounted) setState(() => _isLoadingRole = false);
    }
  }

  // --- دوال التقويم الذكية للتعديل ---
  Future<void> _pickEditDate(
    BuildContext context,
    bool isFromDate,
    DateTime? currentFrom,
    DateTime? currentTo,
    Function(DateTime) onPicked,
  ) async {
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
          data: Theme.of(
            context,
          ).copyWith(colorScheme: ColorScheme.light(primary: _getRoleColor())),
          child: child!,
        );
      },
    );
    if (picked != null) onPicked(picked);
  }

  // --- طلب التعديل (المدير) ---
  Future<void> _managerRequestEdit(
    String transactionId,
    String trnNumber,
  ) async {
    TextEditingController notesController = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.edit_note_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text(
                'طلب تعديل السند',
                style: TextStyle(color: Colors.orange, fontSize: 18),
              ),
            ],
          ),
          content: TextField(
            controller: notesController,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'اكتب التعديلات المطلوبة...',
              border: OutlineInputBorder(
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
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () async {
                if (notesController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('الرجاء إدخال المطلوب')),
                  );
                  return;
                }
                Navigator.pop(context);
                try {
                  await _dbService.updateTransactionStatus(
                    transactionId: transactionId,
                    newStatus: 'editRequestedByCollector',
                    managerNotes: notesController.text.trim(),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('تم طلب التعديل للسند $trnNumber'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('حدث خطأ'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text('إرسال للمحصل'),
            ),
          ],
        );
      },
    );
  }

  // --- دوال المحاسب ---
  Future<void> _accountantRequestEdit(
    String transactionId,
    String trnNumber,
  ) async {
    TextEditingController notesController = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.edit_note_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text(
                'طلب تعديل (المحاسب)',
                style: TextStyle(color: Colors.orange, fontSize: 18),
              ),
            ],
          ),
          content: TextField(
            controller: notesController,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'اكتب سبب التعديل للمحصل...',
              border: OutlineInputBorder(
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
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () async {
                if (notesController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('الرجاء إدخال المطلوب')),
                  );
                  return;
                }
                Navigator.pop(context);
                try {
                  await _dbService.requestEditByAccountant(
                    transactionId: transactionId,
                    accountantNotes: notesController.text.trim(),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('تم طلب التعديل للسند $trnNumber'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('حدث خطأ'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text('إرسال للمحصل'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _accountantApprove(
    String transactionId,
    String trnNumber,
  ) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.verified_rounded, color: Colors.green),
            SizedBox(width: 8),
            Text(
              'اعتماد نهائي',
              style: TextStyle(color: Colors.green, fontSize: 18),
            ),
          ],
        ),
        content: Text(
          'هل أنت متأكد من الاعتماد النهائي للسند رقم $trnNumber؟ لا يمكن التراجع بعد الاعتماد.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () async {
              Navigator.pop(context);
              try {
                await _dbService.approveByAccountant(transactionId);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم الاعتماد النهائي بنجاح'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('حدث خطأ'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            icon: const Icon(Icons.check_circle_rounded, size: 18),
            label: const Text('تأكيد الاعتماد'),
          ),
        ],
      ),
    );
  }

  // --- التعديل المباشر (المحصل) ---
  Future<void> _collectorProposeEdit(
    String transactionId,
    Map<String, dynamic> currentData,
  ) async {
    final TextEditingController amountController = TextEditingController(
      text: currentData['amount'].toString(),
    );
    final TextEditingController notesController = TextEditingController(
      text: currentData['notes'] ?? '',
    );
    String selectedCurrency = currentData['currency'] ?? 'YER';
    DateTime dateFrom =
        (currentData['dateFrom'] as Timestamp?)?.toDate() ?? DateTime.now();
    DateTime dateTo =
        (currentData['dateTo'] as Timestamp?)?.toDate() ?? DateTime.now();
    bool isSaving = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Row(
                children: [
                  Icon(Icons.edit_rounded, color: AppTheme.collectorColor),
                  SizedBox(width: 8),
                  Text(
                    'تعديل بيانات السند',
                    style: TextStyle(
                      color: AppTheme.collectorColor,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'المبلغ',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'العملة',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedCurrency,
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(
                              value: 'YER',
                              child: Text('ريال يمني (YER)'),
                            ),
                            DropdownMenuItem(
                              value: 'SAR',
                              child: Text('ريال سعودي (SAR)'),
                            ),
                            DropdownMenuItem(
                              value: 'USD',
                              child: Text('دولار (USD)'),
                            ),
                          ],
                          onChanged: (val) {
                            if (val != null)
                              setDialogState(() => selectedCurrency = val);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      title: Text(
                        'من: ${DateFormat('yyyy/MM/dd').format(dateFrom)}',
                        style: const TextStyle(fontSize: 14),
                      ),
                      trailing: const Icon(
                        Icons.calendar_today_rounded,
                        size: 20,
                      ),
                      onTap: () => _pickEditDate(
                        context,
                        true,
                        dateFrom,
                        dateTo,
                        (picked) => setDialogState(() => dateFrom = picked),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      title: Text(
                        'إلى: ${DateFormat('yyyy/MM/dd').format(dateTo)}',
                        style: const TextStyle(fontSize: 14),
                      ),
                      trailing: const Icon(
                        Icons.calendar_today_rounded,
                        size: 20,
                      ),
                      onTap: () => _pickEditDate(
                        context,
                        false,
                        dateFrom,
                        dateTo,
                        (picked) => setDialogState(() => dateTo = picked),
                      ),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: notesController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'ملاحظات',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.collectorColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (amountController.text.trim().isEmpty) return;
                          final double? amount = double.tryParse(
                            amountController.text.trim(),
                          );
                          if (amount == null) return;

                          if (dateTo.isBefore(dateFrom)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'تاريخ (إلى) يجب أن يكون بعد أو يساوي تاريخ (من)',
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
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
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'تم إرسال التعديل للمدير للموافقة',
                                  ),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } catch (e) {
                            setDialogState(() => isSaving = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('حدث خطأ'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                  icon: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.save_rounded, size: 18),
                  label: Text(isSaving ? 'جاري الحفظ...' : 'حفظ وطلب موافقة'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- دوال المساعدة للواجهة ---
  Widget? _buildTrailingAction(
    String status,
    String transactionId,
    String trnNumber,
    Map<String, dynamic> data,
  ) {
    if (status == 'approvedByAccountant') {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.verified_rounded,
          color: Colors.green,
          size: 24,
        ),
      );
    }

    if (_currentUserRole == 'accountant' && status == 'approvedByManager') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(
              Icons.edit_note_rounded,
              color: Colors.orange,
              size: 24,
            ),
            tooltip: 'طلب تعديل من المحصل',
            onPressed: () => _accountantRequestEdit(transactionId, trnNumber),
          ),
          IconButton(
            icon: const Icon(
              Icons.check_circle_rounded,
              color: Colors.green,
              size: 24,
            ),
            tooltip: 'اعتماد نهائي',
            onPressed: () => _accountantApprove(transactionId, trnNumber),
          ),
        ],
      );
    }

    if (status == 'editRequestedByCollector' ||
        status == 'pendingApprovalOfEdit' ||
        status == 'rejectedByManager')
      return null;

    if (_currentUserRole == 'manager') {
      return IconButton(
        icon: const Icon(
          Icons.edit_note_rounded,
          color: Colors.orange,
          size: 24,
        ),
        tooltip: 'إرجاع للمحصل للتعديل',
        onPressed: () => _managerRequestEdit(transactionId, trnNumber),
      );
    } else if (_currentUserRole == 'collector') {
      return IconButton(
        icon: const Icon(
          Icons.edit_rounded,
          color: AppTheme.collectorColor,
          size: 22,
        ),
        tooltip: 'تعديل السند',
        onPressed: () => _collectorProposeEdit(transactionId, data),
      );
    }
    return null;
  }

  // أداة لاختيار التواريخ في شاشة الفلترة
  Widget _buildDateRangeFilter({
    required String title,
    required DateTime? start,
    required DateTime? end,
    required Function(DateTime?, DateTime?) onPicked,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppTheme.textSecondary,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: start ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                  );
                  onPicked(picked, end);
                },
                icon: const Icon(
                  Icons.date_range_rounded,
                  size: 16,
                  color: AppTheme.textHint,
                ),
                label: Text(
                  start != null
                      ? DateFormat('yyyy/MM/dd').format(start)
                      : 'من تاريخ',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: end ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                  );
                  onPicked(start, picked);
                },
                icon: const Icon(
                  Icons.date_range_rounded,
                  size: 16,
                  color: AppTheme.textHint,
                ),
                label: Text(
                  end != null
                      ? DateFormat('yyyy/MM/dd').format(end)
                      : 'إلى تاريخ',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Row(
                children: [
                  Icon(Icons.filter_alt_rounded, color: AppTheme.textSecondary),
                  SizedBox(width: 8),
                  Text('تصفية متقدمة', style: TextStyle(fontSize: 18)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'العملة',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedCurrency,
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(value: null, child: Text('الكل')),
                            DropdownMenuItem(
                              value: 'YER',
                              child: Text('ريال يمني (YER)'),
                            ),
                            DropdownMenuItem(
                              value: 'SAR',
                              child: Text('ريال سعودي (SAR)'),
                            ),
                            DropdownMenuItem(
                              value: 'USD',
                              child: Text('دولار (USD)'),
                            ),
                          ],
                          onChanged: (val) =>
                              setDialogState(() => _selectedCurrency = val),
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'الحالة',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedStatus,
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(value: null, child: Text('الكل')),
                            DropdownMenuItem(
                              value: 'pending',
                              child: Text('قيد الانتظار'),
                            ),
                            DropdownMenuItem(
                              value: 'pendingApprovalOfEdit',
                              child: Text('تعديلات بانتظار المدير'),
                            ),
                            DropdownMenuItem(
                              value: 'approvedByManager',
                              child: Text('معتمد من المدير'),
                            ),
                            DropdownMenuItem(
                              value: 'approvedByAccountant',
                              child: Text('معتمد من المحاسب'),
                            ),
                          ],
                          onChanged: (val) =>
                              setDialogState(() => _selectedStatus = val),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Divider(height: 1, thickness: 1),
                    ),
                    _buildDateRangeFilter(
                      title: 'تاريخ إدخال السند (متى تم الحفظ):',
                      start: _filterStartDate,
                      end: _filterEndDate,
                      onPicked: (s, e) => setDialogState(() {
                        _filterStartDate = s;
                        _filterEndDate = e;
                      }),
                    ),
                    const SizedBox(height: 15),
                    _buildDateRangeFilter(
                      title: 'فترة التحصيل (المبيعات من وإلى):',
                      start: _periodStartDate,
                      end: _periodEndDate,
                      onPicked: (s, e) => setDialogState(() {
                        _periodStartDate = s;
                        _periodEndDate = e;
                      }),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedCurrency = null;
                      _selectedStatus = null;
                      _filterStartDate = null;
                      _filterEndDate = null;
                      _periodStartDate = null;
                      _periodEndDate = null;
                    });
                    Navigator.pop(context);
                  },
                  child: const Text(
                    'مسح الفلاتر',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _getRoleColor(),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () {
                    setState(() {});
                    Navigator.pop(context);
                  },
                  child: const Text('تطبيق الفلترة'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Color _getRoleColor() {
    if (_currentUserRole == 'manager') return AppTheme.managerColor;
    if (_currentUserRole == 'accountant') return AppTheme.accountantColor;
    return AppTheme.collectorColor; // Default for collector or unknown
  }

  TransactionRecordFilters get _recordFilters => TransactionRecordFilters(
    currency: _selectedCurrency,
    status: _selectedStatus,
    createdFrom: _filterStartDate,
    createdTo: _filterEndDate,
    periodFrom: _periodStartDate,
    periodTo: _periodEndDate,
  );

  void _clearFilters() {
    setState(() {
      _selectedCurrency = null;
      _selectedStatus = null;
      _filterStartDate = null;
      _filterEndDate = null;
      _periodStartDate = null;
      _periodEndDate = null;
    });
  }

  String _currencyLabel(String currency) {
    switch (currency) {
      case 'YER':
        return 'ريال يمني';
      case 'SAR':
        return 'ريال سعودي';
      case 'USD':
        return 'دولار أمريكي';
      default:
        return currency;
    }
  }

  Widget _buildRecordsSummary(
    List<QueryDocumentSnapshot<Object?>> transactions,
  ) {
    final totals = totalsByCurrency(
      transactions.map((doc) => doc.data() as Map<String, dynamic>),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'نتائج السجل (${transactions.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              if (_recordFilters.isActive)
                TextButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                  label: const Text('مسح الفلاتر'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (totals.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: AppTheme.cardShadow(),
              child: const Text('لا توجد مبالغ لعرضها'),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: totals.entries.map((entry) {
                return Container(
                  constraints: const BoxConstraints(minWidth: 155),
                  padding: const EdgeInsets.all(14),
                  decoration: AppTheme.cardShadow(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _getRoleColor().withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.account_balance_wallet_rounded,
                          color: _getRoleColor(),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            NumberFormat(
                              '#,##0.##',
                              'en_US',
                            ).format(entry.value),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _currencyLabel(entry.key),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingRole)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(
          title: Text(
            'سجل السندات',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          backgroundColor: _getRoleColor(),
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.filter_list_rounded),
              tooltip: 'تصفية',
              onPressed: _showFilterDialog,
            ),
          ],
        ),
        body: Column(
          children: [
            // Decorative Header Background
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              decoration: BoxDecoration(
                color: _getRoleColor(),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
              ),
              child: Text(
                'الفرع: ${widget.branchName}',
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
            if (_recordFilters.isActive)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _getRoleColor().withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _getRoleColor().withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.filter_alt_rounded,
                      color: _getRoleColor(),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'تم تطبيق ${_recordFilters.activeCount} من خيارات التصفية',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    TextButton(
                      onPressed: _showFilterDialog,
                      child: const Text('تعديل'),
                    ),
                  ],
                ),
              ),

            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _dbService.getBranchTransactions(
                  branchId: widget.branchId,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting)
                    return const Center(child: CircularProgressIndicator());
                  if (snapshot.hasError)
                    return const Center(
                      child: Text(
                        'خطأ في جلب البيانات.',
                        style: TextStyle(color: Colors.red),
                      ),
                    );

                  final transactions = filterAndSortTransactionRecords(
                    records: snapshot.data!.docs,
                    dataOf: (doc) => doc.data() as Map<String, dynamic>,
                    filters: _recordFilters,
                  );

                  if (transactions.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off_rounded,
                            size: 64,
                            color: AppTheme.textHint.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'لا توجد سندات مطابقة',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: transactions.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _buildRecordsSummary(transactions);
                      }
                      final doc = transactions[index - 1];
                      final data = doc.data() as Map<String, dynamic>;

                      final double rawAmount =
                          (data['amount'] as num?)?.toDouble() ?? 0.0;
                      final String formattedAmount = NumberFormat(
                        '#,##0.##',
                        'en_US',
                      ).format(rawAmount);
                      final String currency = data['currency'] ?? 'YER';
                      final String trnNumber =
                          data['transaction_number'] ?? '#';
                      final String status = data['status'] ?? 'pending';

                      final dateFrom = (data['dateFrom'] as Timestamp?)
                          ?.toDate();
                      final dateTo = (data['dateTo'] as Timestamp?)?.toDate();
                      String dateRange = 'غير محدد';
                      if (dateFrom != null && dateTo != null) {
                        dateRange =
                            '${DateFormat('yyyy/MM/dd').format(dateFrom)} - ${DateFormat('yyyy/MM/dd').format(dateTo)}';
                      }

                      final statusColor = AppTheme.statusColor(status);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: AppTheme.cardShadow(),
                        child: Material(
                          color: AppTheme.cardColor,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      TransactionDetailsScreen(
                                        transactionData: data,
                                        transactionId: doc.id,
                                      ),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Icon
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: statusColor.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(
                                      Icons.receipt_outlined,
                                      color: statusColor,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 14),

                                  // Content
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '$formattedAmount $currency',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            color: AppTheme.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'رقم: $trnNumber',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: AppTheme.textSecondary,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: statusColor.withValues(
                                                  alpha: 0.1,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                AppTheme.statusLabel(status),
                                                style: TextStyle(
                                                  color: statusColor,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 10,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                dateRange,
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: AppTheme.textHint,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Trailing Action
                                  if (_buildTrailingAction(
                                        status,
                                        doc.id,
                                        trnNumber,
                                        data,
                                      ) !=
                                      null) ...[
                                    const SizedBox(width: 8),
                                    _buildTrailingAction(
                                      status,
                                      doc.id,
                                      trnNumber,
                                      data,
                                    )!,
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
