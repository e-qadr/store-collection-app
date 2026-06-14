import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/models/transaction_model.dart';
import 'package:store_collection_app/services/database_service.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:flutter/services.dart';
import 'package:store_collection_app/theme/app_theme.dart';

class NewTransactionScreen extends StatefulWidget {
  final String branchId;
  final String branchName;

  const NewTransactionScreen({
    super.key,
    required this.branchId,
    required this.branchName,
  });

  @override
  State<NewTransactionScreen> createState() => _NewTransactionScreenState();
}

class _NewTransactionScreenState extends State<NewTransactionScreen> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _cashierAmountController =
      TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  DateTime? _dateFrom;
  DateTime? _dateTo;
  bool _isLoading = false;
  String _selectedCurrency = 'YER';
  bool _amountMatches = true;

  // دالة اختيار التاريخ بذكاء لمنع التواريخ المتعارضة
  Future<void> _selectDate(BuildContext context, bool isFromDate) async {
    DateTime initialDate = DateTime.now();
    DateTime firstDate = DateTime(2020);
    DateTime lastDate = DateTime.now().add(const Duration(days: 365));

    if (isFromDate) {
      if (_dateTo != null) lastDate = _dateTo!;
      initialDate = _dateFrom ?? DateTime.now();
      if (initialDate.isAfter(lastDate)) initialDate = lastDate;
    } else {
      if (_dateFrom != null) firstDate = _dateFrom!;
      initialDate = _dateTo ?? _dateFrom ?? DateTime.now();
      if (initialDate.isBefore(firstDate)) initialDate = firstDate;
    }

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.collectorColor,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isFromDate) {
          _dateFrom = picked;
        } else {
          _dateTo = picked;
        }
      });
    }
  }

  // دالة حفظ السند
  Future<void> _saveTransaction() async {
    if (_amountController.text.isEmpty ||
        _dateFrom == null ||
        _dateTo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الرجاء إدخال المبلغ وتحديد فترة التحصيل (من - إلى)'),
        ),
      );
      return;
    }

    if (_dateTo!.isBefore(_dateFrom!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تاريخ (إلى) يجب أن يكون بعد أو يساوي تاريخ (من)'),
        ),
      );
      return;
    }

    if (!_amountMatches && _cashierAmountController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الرجاء إدخال المبلغ الموجود على الكاشير'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final String uid = FirebaseAuth.instance.currentUser!.uid;
      final docRef = FirebaseFirestore.instance
          .collection('transactions')
          .doc();
      final DateTime now = DateTime.now();

      final transaction = TransactionModel(
        id: docRef.id,
        transactionNumber: '',
        branchId: widget.branchId,
        collectorId: uid,
        amount: double.parse(_amountController.text.trim().replaceAll(',', '')),
        currency: _selectedCurrency,
        amountMatches: _amountMatches,
        cashierAmount: _amountMatches
            ? null
            : double.parse(
                _cashierAmountController.text.trim().replaceAll(',', ''),
              ),
        dateFrom: _dateFrom!,
        dateTo: _dateTo!,
        transactionDate: now,
        notes: _notesController.text.trim(),
        status: TransactionStatus.pending,
        timestamp: now,
        history: [],
      );

      final trnNumber = await DatabaseService().addTransaction(transaction);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تسجيل السند رقم $trnNumber بنجاح!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تعذر حفظ السند: ${e.toString().replaceFirst('Exception: ', '')}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _cashierAmountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(
          title: const Text(
            'إضافة سند تحصيل',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          backgroundColor: AppTheme.collectorColor,
          elevation: 0,
        ),
        body: Column(
          children: [
            // Decorative Header Background
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
              decoration: const BoxDecoration(
                color: AppTheme.collectorColor,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
              ),
              child: Text(
                'الفرع: ${widget.branchName}',
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // --- Amount & Currency Section ---
                    Container(
                      decoration: AppTheme.cardShadow(),
                      child: Material(
                        color: AppTheme.cardColor,
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'المبلغ المحصل',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: TextField(
                                      controller: _amountController,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      inputFormatters: [
                                        ThousandsSeparatorInputFormatter(),
                                      ],
                                      decoration: const InputDecoration(
                                        hintText: '0.00',
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.all(
                                            Radius.circular(12),
                                          ),
                                        ),
                                        prefixIcon: Icon(
                                          Icons.attach_money_rounded,
                                          color: AppTheme.collectorColor,
                                        ),
                                      ),
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 1,
                                    child: InputDecorator(
                                      decoration: const InputDecoration(
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.all(
                                            Radius.circular(12),
                                          ),
                                        ),
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 15,
                                        ),
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String>(
                                          value: _selectedCurrency,
                                          isExpanded: true,
                                          icon: const Icon(
                                            Icons.keyboard_arrow_down_rounded,
                                            color: AppTheme.textSecondary,
                                          ),
                                          style: const TextStyle(
                                            fontSize: 16,
                                            color: AppTheme.textPrimary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          items: const [
                                            DropdownMenuItem(
                                              value: 'YER',
                                              child: Text('ر.ي'),
                                            ),
                                            DropdownMenuItem(
                                              value: 'SAR',
                                              child: Text('ر.س'),
                                            ),
                                            DropdownMenuItem(
                                              value: 'USD',
                                              child: Text('دولار'),
                                            ),
                                          ],
                                          onChanged: (value) => setState(
                                            () => _selectedCurrency = value!,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

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
                              const Text(
                                'مطابقة مبلغ الكاشير',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 16),
                              DropdownButtonFormField<bool>(
                                initialValue: _amountMatches,
                                decoration: const InputDecoration(
                                  labelText: 'حالة مطابقة المبلغ',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(12),
                                    ),
                                  ),
                                  prefixIcon: Icon(
                                    Icons.compare_arrows_rounded,
                                    color: AppTheme.collectorColor,
                                  ),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: true,
                                    child: Text('المبلغ مطابق'),
                                  ),
                                  DropdownMenuItem(
                                    value: false,
                                    child: Text('المبلغ غير مطابق'),
                                  ),
                                ],
                                onChanged: (value) => setState(() {
                                  _amountMatches = value ?? true;
                                  if (_amountMatches)
                                    _cashierAmountController.clear();
                                }),
                              ),
                              if (!_amountMatches) ...[
                                const SizedBox(height: 16),
                                TextField(
                                  controller: _cashierAmountController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  inputFormatters: [
                                    ThousandsSeparatorInputFormatter(),
                                  ],
                                  decoration: const InputDecoration(
                                    labelText: 'المبلغ الموجود على الكاشير',
                                    hintText: '0.00',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.all(
                                        Radius.circular(12),
                                      ),
                                    ),
                                    prefixIcon: Icon(
                                      Icons.point_of_sale_rounded,
                                      color: Colors.orange,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // --- Date Period Section ---
                    Container(
                      decoration: AppTheme.cardShadow(),
                      child: Material(
                        color: AppTheme.cardColor,
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'فترة المبيعات المحصلة',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () =>
                                          _selectDate(context, true),
                                      icon: const Icon(
                                        Icons.calendar_today_rounded,
                                        size: 18,
                                        color: AppTheme.collectorColor,
                                      ),
                                      label: Text(
                                        _dateFrom == null
                                            ? 'من تاريخ'
                                            : DateFormat(
                                                'yyyy/MM/dd',
                                              ).format(_dateFrom!),
                                        style: const TextStyle(
                                          color: AppTheme.textPrimary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        side: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () =>
                                          _selectDate(context, false),
                                      icon: const Icon(
                                        Icons.calendar_today_rounded,
                                        size: 18,
                                        color: AppTheme.collectorColor,
                                      ),
                                      label: Text(
                                        _dateTo == null
                                            ? 'إلى تاريخ'
                                            : DateFormat(
                                                'yyyy/MM/dd',
                                              ).format(_dateTo!),
                                        style: const TextStyle(
                                          color: AppTheme.textPrimary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        side: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // --- Notes Section ---
                    Container(
                      decoration: AppTheme.cardShadow(),
                      child: Material(
                        color: AppTheme.cardColor,
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'ملاحظات إضافية',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _notesController,
                                maxLines: 3,
                                decoration: const InputDecoration(
                                  hintText: 'اكتب أي ملاحظات هنا (اختياري)...',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(12),
                                    ),
                                  ),
                                  prefixIcon: Icon(
                                    Icons.notes_rounded,
                                    color: AppTheme.textHint,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // --- Submit Button ---
                    SizedBox(
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _saveTransaction,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.collectorColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 2,
                        ),
                        icon: _isLoading
                            ? const SizedBox.shrink()
                            : const Icon(
                                Icons.check_circle_outline_rounded,
                                size: 22,
                              ),
                        label: _isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Text(
                                'تسجيل واعتماد السند',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// منسق أرقام ذكي يحافظ على موقع المؤشر عند التعديل في المنتصف
class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;

    String selectionText = newValue.text.replaceAll(',', '');
    final parts = selectionText.split('.');

    String formatted = parts[0].replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );

    if (parts.length > 1) {
      formatted += '.${parts[1]}';
    }

    int commasBefore = 0;
    for (
      int i = 0;
      i < newValue.selection.end && i < newValue.text.length;
      i++
    ) {
      if (newValue.text[i] == ',') commasBefore++;
    }

    int rawCharsBefore = newValue.selection.end - commasBefore;
    int newSelectionIndex = 0;
    int count = 0;

    while (newSelectionIndex < formatted.length && count < rawCharsBefore) {
      if (formatted[newSelectionIndex] != ',') {
        count++;
      }
      newSelectionIndex++;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: newSelectionIndex),
    );
  }
}
