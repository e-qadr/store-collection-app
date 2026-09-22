import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/services/database_service.dart';
import 'package:store_collection_app/theme/app_theme.dart';
import 'package:store_collection_app/utils/accountant_collection_review.dart';
import 'package:store_collection_app/widgets/collection_amount_input_formatter.dart';
import 'package:store_collection_app/widgets/notification_bell.dart';

/// Accountant-only preparation of a Collection voucher. This intentionally
/// stops at reserving the official number; physical collection remains a
/// collector-only action on the reserved-voucher screen.
class AccountantCollectionReviewScreen extends StatefulWidget {
  const AccountantCollectionReviewScreen({
    super.key,
    required this.role,
    required this.branchId,
    required this.branchName,
  });

  final UserRole role;
  final String branchId;
  final String branchName;

  static bool canOpenFor(UserRole role) => role == UserRole.accountant;

  @override
  State<AccountantCollectionReviewScreen> createState() =>
      _AccountantCollectionReviewScreenState();
}

class _AccountantCollectionReviewScreenState
    extends State<AccountantCollectionReviewScreen> {
  DatabaseService? _database;
  DatabaseService get _reservationService => _database ??= DatabaseService();
  final _reviewedAmount = TextEditingController();
  final _differenceReason = TextEditingController();
  final _reference = TextEditingController();
  final _note = TextEditingController();
  final _number = NumberFormat('#,##0.##');
  final _date = DateFormat('yyyy/MM/dd');

  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now();
  String _currency = 'YER';
  bool _reviewedAmountWasEdited = false;
  bool _saving = false;
  double? _lastReportedAmount;
  String? _reservedNumber;

  bool get _isAccountant =>
      AccountantCollectionReviewScreen.canOpenFor(widget.role);
  double? get _reviewedValue =>
      double.tryParse(_reviewedAmount.text.replaceAll(',', '').trim());

  @override
  void dispose() {
    _reviewedAmount.dispose();
    _differenceReason.dispose();
    _reference.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAccountant) return _accessDenied();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(
          backgroundColor: AppTheme.accountantColor,
          title: const Text('مراجعة وحجز سند تحصيل'),
          actions: const [NotificationBell()],
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('transactions')
              .where('branchId', isEqualTo: widget.branchId)
              .snapshots(),
          builder: (context, snapshot) {
            final reportedAmount = snapshot.hasData
                ? _reportedAmount(snapshot.data!.docs)
                : null;
            _syncSuggestedReviewedAmount(reportedAmount);
            return _reservedNumber == null
                ? _reviewForm(
                    reportedAmount: reportedAmount,
                    sourceLoading:
                        snapshot.connectionState == ConnectionState.waiting,
                    sourceError: snapshot.hasError,
                  )
                : _successState(reportedAmount);
          },
        ),
      ),
    );
  }

  Widget _accessDenied() => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      appBar: AppBar(
        backgroundColor: AppTheme.accountantColor,
        title: const Text('مراجعة وحجز سند تحصيل'),
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text(
            'هذه الصفحة متاحة للمحاسب فقط. لا تمنح صلاحية استلام أو تحصيل الأموال.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );

  Widget _reviewForm({
    required double? reportedAmount,
    required bool sourceLoading,
    required bool sourceError,
  }) {
    final comparison = AccountantCollectionReviewComparison(
      branchReportedAmount: reportedAmount,
      reviewedAmount: _reviewedValue,
    );
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            const SizedBox(height: 20),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('بيانات مراجعة دخل الفرع', style: _cardTitle),
                  const SizedBox(height: 16),
                  _readOnlyField(
                    label: 'الفرع',
                    value: widget.branchName,
                    icon: Icons.storefront_rounded,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _currency,
                    decoration: const InputDecoration(
                      labelText: 'العملة',
                      prefixIcon: Icon(Icons.currency_exchange_rounded),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'YER', child: Text('ر.ي')),
                      DropdownMenuItem(value: 'SAR', child: Text('ر.س')),
                      DropdownMenuItem(value: 'USD', child: Text('دولار')),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _currency = value!),
                  ),
                  const SizedBox(height: 14),
                  _periodFields(),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _reportedAmountCard(
              amount: reportedAmount,
              loading: sourceLoading,
              error: sourceError,
            ),
            const SizedBox(height: 16),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('المبلغ بعد مراجعة المحاسب', style: _cardTitle),
                  const SizedBox(height: 7),
                  const Text(
                    'هذا تأكيد للمراجعة فقط، ولا يعني استلام المبلغ.',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('accountant-reviewed-amount'),
                    controller: _reviewedAmount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [ThousandsSeparatorInputFormatter()],
                    onChanged: (_) =>
                        setState(() => _reviewedAmountWasEdited = true),
                    decoration: InputDecoration(
                      labelText: 'المبلغ بعد مراجعة المحاسب',
                      hintText: '0.00',
                      suffixText: _currency,
                      prefixIcon: const Icon(Icons.fact_check_rounded),
                    ),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _comparisonCard(comparison),
            if (comparison.hasDifference) ...[
              const SizedBox(height: 16),
              _card(
                child: TextField(
                  key: const Key('accountant-difference-reason'),
                  controller: _differenceReason,
                  maxLines: 3,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'سبب الفارق',
                    hintText: 'اشرح سبب الزيادة أو النقص قبل حجز الرقم',
                    prefixIcon: Icon(Icons.comment_bank_outlined),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            _card(
              child: Column(
                children: [
                  TextField(
                    controller: _reference,
                    decoration: const InputDecoration(
                      labelText: 'مرجع المراجعة (اختياري)',
                      prefixIcon: Icon(Icons.bookmark_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _note,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظة (اختيارية)',
                      prefixIcon: Icon(Icons.notes_rounded),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _summaryCard(reportedAmount, comparison),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('reserve-official-number'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accountantColor,
                padding: const EdgeInsets.symmetric(vertical: 17),
              ),
              onPressed: _saving ? null : () => _reserve(comparison),
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.bookmark_added_rounded),
              label: const Text(
                'حجز الرقم الرسمي',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
    decoration: const BoxDecoration(
      gradient: LinearGradient(colors: AppTheme.accountantGradient),
      borderRadius: BorderRadius.only(
        bottomLeft: Radius.circular(24),
        bottomRight: Radius.circular(24),
      ),
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'مراجعة دخل الفرع',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'حجز رقم رسمي فقط — التحصيل الفعلي من اختصاص المدير العام.',
          style: TextStyle(color: Colors.white70),
        ),
      ],
    ),
  );

  Widget _periodFields() => Row(
    children: [
      Expanded(child: _dateButton(true)),
      const SizedBox(width: 10),
      Expanded(child: _dateButton(false)),
    ],
  );

  Widget _dateButton(bool isFrom) {
    final value = isFrom ? _from : _to;
    return OutlinedButton.icon(
      onPressed: _saving ? null : () => _pickDate(isFrom),
      icon: const Icon(Icons.calendar_today_rounded, size: 17),
      label: Text('${isFrom ? 'من' : 'إلى'}: ${_date.format(value)}'),
    );
  }

  Widget _reportedAmountCard({
    required double? amount,
    required bool loading,
    required bool error,
  }) => _card(
    color: AppTheme.oliveSurface,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('المبلغ المسجل من الفرع', style: _cardTitle),
        const SizedBox(height: 6),
        if (loading)
          const LinearProgressIndicator()
        else if (amount == null)
          Text(
            error
                ? 'تعذر قراءة مبلغ الفرع من سجلات التحصيل الحالية.'
                : 'لا يوجد مبلغ كاشير مسجل للفترة المختارة في مصدر التحصيل الحالي.',
            style: const TextStyle(color: AppTheme.textSecondary),
          )
        else ...[
          Text(
            '${_number.format(amount)} $_currency',
            key: const Key('branch-reported-amount'),
            style: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.bold,
              color: AppTheme.accountantColor,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'قراءة فقط من مبلغ الكاشير المسجل في سندات التحصيل الحالية.',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ],
      ],
    ),
  );

  Widget _comparisonCard(AccountantCollectionReviewComparison comparison) {
    if (!comparison.canCompare) {
      return _card(
        color: AppTheme.goldSurface,
        child: const Text(
          'حالة المراجعة: أدخل مبلغ المراجعة. ستظهر المقارنة تلقائياً عند توفر مبلغ الفرع.',
        ),
      );
    }
    final color = comparison.isMatch
        ? AppTheme.successColor
        : AppTheme.warningColor;
    return _card(
      color: color.withValues(alpha: .08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                comparison.isMatch
                    ? Icons.check_circle_rounded
                    : Icons.warning_amber_rounded,
                color: color,
              ),
              const SizedBox(width: 8),
              Text(
                comparison.isMatch ? 'المبلغ مطابق' : 'يوجد فارق',
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          if (comparison.hasDifference) ...[
            const SizedBox(height: 12),
            Text(
              'مبلغ الفرع: ${_number.format(comparison.branchReportedAmount)} $_currency',
            ),
            Text(
              'مبلغ المراجعة: ${_number.format(comparison.reviewedAmount)} $_currency',
            ),
            Text(
              'قيمة الفارق: ${_number.format(comparison.differenceAmount)} $_currency',
            ),
            Text('نوع الفارق: ${comparison.differenceTypeLabel}'),
          ],
        ],
      ),
    );
  }

  Widget _summaryCard(
    double? reportedAmount,
    AccountantCollectionReviewComparison comparison,
  ) => _card(
    color: AppTheme.cardColor,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ملخص المراجعة قبل الحجز', style: _cardTitle),
        const Divider(height: 24),
        _summaryRow('الفرع', widget.branchName),
        _summaryRow('الفترة', '${_date.format(_from)} — ${_date.format(_to)}'),
        _summaryRow('العملة', _currency),
        _summaryRow(
          'مبلغ الفرع',
          reportedAmount == null
              ? 'غير متوفر'
              : '${_number.format(reportedAmount)} $_currency',
        ),
        _summaryRow(
          'مبلغ المراجعة',
          _reviewedValue == null
              ? '-'
              : '${_number.format(_reviewedValue)} $_currency',
        ),
        if (comparison.canCompare)
          _summaryRow(
            'نتيجة المراجعة',
            comparison.isMatch ? 'المبلغ مطابق' : 'يوجد فارق',
          ),
        if (comparison.hasDifference) ...[
          _summaryRow(
            'قيمة الفارق',
            '${_number.format(comparison.differenceAmount)} $_currency',
          ),
          _summaryRow(
            'سبب الفارق',
            _differenceReason.text.trim().isEmpty
                ? 'مطلوب'
                : _differenceReason.text.trim(),
          ),
        ],
      ],
    ),
  );

  Widget _successState(double? reportedAmount) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: _card(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.bookmark_added_rounded,
              size: 56,
              color: AppTheme.successColor,
            ),
            const SizedBox(height: 14),
            const Text(
              'تم حجز الرقم الرسمي',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              _reservedNumber!,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                color: AppTheme.accountantColor,
              ),
            ),
            const SizedBox(height: 14),
            _summaryRow('الفرع', widget.branchName),
            _summaryRow(
              'المبلغ بعد المراجعة',
              '${_number.format(_reviewedValue)} $_currency',
            ),
            if (reportedAmount != null)
              _summaryRow(
                'المبلغ المسجل من الفرع',
                '${_number.format(reportedAmount)} $_currency',
              ),
            const SizedBox(height: 12),
            const Text(
              'مراجع من المحاسب - بانتظار التحصيل',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppTheme.pendingColor,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'لم يتم تسجيل تحصيل فعلي أو أثر محاسبي نهائي.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.list_alt_rounded),
              label: const Text('العودة إلى سجل السندات'),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _card({required Widget child, Color color = AppTheme.cardColor}) =>
      Container(
        decoration: AppTheme.cardShadow(color: color),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: Padding(padding: const EdgeInsets.all(20), child: child),
        ),
      );

  Widget _readOnlyField({
    required String label,
    required String value,
    required IconData icon,
  }) => InputDecorator(
    decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
    child: Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
  );

  Widget _summaryRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.left,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );

  Future<void> _pickDate(bool isFrom) async {
    var firstDate = DateTime(2020);
    var lastDate = DateTime.now().add(const Duration(days: 365));
    var initial = isFrom ? _from : _to;
    if (isFrom) lastDate = _to;
    if (!isFrom) firstDate = _from;
    if (initial.isBefore(firstDate)) initial = firstDate;
    if (initial.isAfter(lastDate)) initial = lastDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: lastDate,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppTheme.accountantColor,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _from = picked;
        } else {
          _to = picked;
        }
      });
    }
  }

  double? _reportedAmount(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final values = docs
        .where((doc) {
          final data = doc.data();
          if (data['collection_workflow'] == 'accountant_reserved' ||
              data['currency'] != _currency) {
            return false;
          }
          final date =
              _asDate(data['dateTo']) ??
              _asDate(data['transaction_date']) ??
              _asDate(data['timestamp']);
          return date != null && !date.isBefore(_from) && !date.isAfter(_to);
        })
        .map((doc) {
          final data = doc.data();
          return (data['branch_reported_amount'] as num?)?.toDouble() ??
              (data['cashier_amount'] as num?)?.toDouble();
        })
        .whereType<double>()
        .toList();
    if (values.isEmpty) return null;
    return values.fold<double>(0, (total, amount) => total + amount);
  }

  DateTime? _asDate(dynamic value) => value is Timestamp
      ? value.toDate()
      : value is DateTime
      ? value
      : null;

  void _syncSuggestedReviewedAmount(double? reportedAmount) {
    if (_lastReportedAmount == reportedAmount) return;
    _lastReportedAmount = reportedAmount;
    if (reportedAmount == null || _reviewedAmountWasEdited) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _reviewedAmountWasEdited) return;
      _reviewedAmount.text = _number.format(reportedAmount);
      setState(() {});
    });
  }

  Future<void> _reserve(AccountantCollectionReviewComparison comparison) async {
    final reviewed = _reviewedValue;
    if (reviewed == null || reviewed <= 0 || _to.isBefore(_from)) {
      _message('تحقق من المبلغ بعد المراجعة وفترة المراجعة.');
      return;
    }
    if (comparison.hasDifference && _differenceReason.text.trim().isEmpty) {
      _message('سبب الفارق مطلوب قبل حجز الرقم الرسمي.');
      return;
    }
    setState(() => _saving = true);
    try {
      final differenceNote = comparison.hasDifference
          ? 'سبب فرق المراجعة: ${_differenceReason.text.trim()}'
          : '';
      final note = [
        differenceNote,
        _note.text.trim(),
      ].where((value) => value.isNotEmpty).join('\n');
      final number = await _reservationService.reserveReviewedCollectionVoucher(
        branchId: widget.branchId,
        reviewedAmount: reviewed,
        currency: _currency,
        dateFrom: _from,
        dateTo: _to,
        reference: _reference.text.trim(),
        note: note,
      );
      if (mounted) setState(() => _reservedNumber = number);
    } catch (error) {
      _message(
        'تعذر حجز الرقم: ${error.toString().replaceFirst('Exception: ', '')}',
      );
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String value) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(value)));
}

const _cardTitle = TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.bold,
  color: AppTheme.textPrimary,
);
