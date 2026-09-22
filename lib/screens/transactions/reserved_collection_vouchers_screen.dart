// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/services/database_service.dart';
import 'package:store_collection_app/theme/app_theme.dart';
import 'package:store_collection_app/widgets/notification_bell.dart';

class ReservedCollectionVouchersScreen extends StatefulWidget {
  final UserRole role;
  final String branchId;
  final String branchName;

  const ReservedCollectionVouchersScreen({
    super.key,
    required this.role,
    required this.branchId,
    required this.branchName,
  });

  @override
  State<ReservedCollectionVouchersScreen> createState() =>
      _ReservedCollectionVouchersScreenState();
}

class _ReservedCollectionVouchersScreenState
    extends State<ReservedCollectionVouchersScreen> {
  final _database = DatabaseService();
  final _number = NumberFormat('#,##0.##');
  final _date = DateFormat('yyyy/MM/dd');

  bool get _isAccountant => widget.role == UserRole.accountant;
  bool get _isCollector => widget.role == UserRole.collector;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        floatingActionButton: _isAccountant
            ? FloatingActionButton.extended(
                key: const Key('reserve-collection-voucher'),
                onPressed: () => _showReservationForm(),
                backgroundColor: AppTheme.accountantColor,
                icon: const Icon(Icons.bookmark_add_rounded),
                label: const Text('حجز سند مراجع'),
              )
            : null,
        appBar: AppBar(
          backgroundColor: _roleColor,
          title: Text(
            _isAccountant ? 'مراجعة وحجز سندات التحصيل' : 'سندات جاهزة للتحصيل',
          ),
          actions: const [NotificationBell()],
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('transactions')
              .where('branchId', isEqualTo: widget.branchId)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError)
              return _empty('تعذر تحميل السندات المحجوزة.');
            final vouchers =
                (snapshot.data?.docs ?? const [])
                    .where((doc) => _isReservedWorkflow(doc.data()))
                    .toList()
                  ..sort(
                    (a, b) => _reservedOrder(
                      a.data(),
                    ).compareTo(_reservedOrder(b.data())),
                  );
            if (vouchers.isEmpty) {
              return _empty(
                _isAccountant
                    ? 'لا توجد مسودات محجوزة لهذا الفرع. يمكنك مراجعة دخل الفرع وحجز رقم جديد.'
                    : 'لا توجد سندات مراجعـة بانتظار التحصيل في هذا الفرع.',
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 92),
              children: [
                _notice(),
                const SizedBox(height: 12),
                ...vouchers.map((doc) => _voucherCard(doc.id, doc.data())),
              ],
            );
          },
        ),
      ),
    );
  }

  Color get _roleColor => switch (widget.role) {
    UserRole.accountant => AppTheme.accountantColor,
    UserRole.collector => AppTheme.collectorColor,
    UserRole.manager => AppTheme.managerColor,
    UserRole.admin => AppTheme.adminColor,
  };

  bool _isReservedWorkflow(Map<String, dynamic> data) =>
      data['collection_workflow'] == 'accountant_reserved';

  int _reservedOrder(Map<String, dynamic> data) => switch (data['status']) {
    'reservedForCollection' => 0,
    'collectionDifferencePendingReview' => 1,
    'reservedCancelled' => 2,
    _ => 3,
  };

  Widget _notice() => Card(
    color: _roleColor.withValues(alpha: .08),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Text(
        _isAccountant
            ? 'حجز الرقم لا يعني استلام المال. يبقى السند بانتظار التحصيل الفعلي من المدير العام.'
            : _isCollector
            ? 'اختر السند بعد الاستلام الفعلي. لن يتم توليد رقم جديد عند إكمال السند المحجوز.'
            : 'هذه السندات مراجعـة من المحاسب. يمكنك استخدام رقمها، ولا يمكنك إنهاء التحصيل.',
      ),
    ),
  );

  Widget _empty(String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );

  Widget _voucherCard(String id, Map<String, dynamic> data) {
    final status = data['status']?.toString() ?? '';
    final reviewed =
        (data['reviewed_amount'] as num?)?.toDouble() ??
        (data['amount'] as num?)?.toDouble() ??
        0;
    final physical = (data['physical_collection_amount'] as num?)?.toDouble();
    final currency = data['currency']?.toString() ?? 'YER';
    return Card(
      key: Key('reserved-voucher-$id'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    data['transaction_number']?.toString() ?? '#',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _statusChip(status),
              ],
            ),
            const SizedBox(height: 8),
            Text('المبلغ المراجع: ${_number.format(reviewed)} $currency'),
            if (physical != null)
              Text(
                'المبلغ المحصل فعلياً: ${_number.format(physical)} $currency',
              ),
            if ((data['reservation_reference']?.toString() ?? '').isNotEmpty)
              Text('المرجع: ${data['reservation_reference']}'),
            if ((data['reservation_cancellation_reason']?.toString() ?? '')
                .isNotEmpty)
              Text('سبب الإلغاء: ${data['reservation_cancellation_reason']}'),
            const SizedBox(height: 10),
            Text(
              'فترة التحصيل: ${_dateOf(data['dateFrom'])} - ${_dateOf(data['dateTo'])}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            _actions(id, data),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    final (label, color) = switch (status) {
      'reservedForCollection' => (
        'مراجع من المحاسب - بانتظار التحصيل',
        AppTheme.pendingColor,
      ),
      'collectionDifferencePendingReview' => (
        'فرق تحصيل بانتظار المراجعة',
        AppTheme.errorColor,
      ),
      'reservedCancelled' => ('مسودة ملغاة', AppTheme.textSecondary),
      _ => (status, AppTheme.primaryOlive),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _actions(String id, Map<String, dynamic> data) {
    final status = data['status']?.toString();
    if (_isCollector && status == 'reservedForCollection') {
      return FilledButton.icon(
        onPressed: () => _showPhysicalReceipt(id, data),
        icon: const Icon(Icons.payments_rounded),
        label: const Text('تسجيل التحصيل الفعلي'),
      );
    }
    if (_isAccountant && status == 'reservedForCollection') {
      return Wrap(
        spacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: () => _showReservationForm(id: id, existing: data),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('تعديل'),
          ),
          OutlinedButton.icon(
            onPressed: () => _cancelReservation(id),
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('إلغاء'),
          ),
        ],
      );
    }
    if (_isAccountant && status == 'collectionDifferencePendingReview') {
      return FilledButton.icon(
        onPressed: () => _approveDifference(id),
        icon: const Icon(Icons.rule_rounded),
        label: const Text('مراجعة فرق التحصيل'),
      );
    }
    return const SizedBox.shrink();
  }

  Future<void> _showReservationForm({
    String? id,
    Map<String, dynamic>? existing,
  }) async {
    final amount = TextEditingController(
      text: existing?['reviewed_amount']?.toString() ?? '',
    );
    final reference = TextEditingController(
      text: existing?['reservation_reference']?.toString() ?? '',
    );
    final note = TextEditingController(
      text: existing?['notes']?.toString() ?? '',
    );
    var currency = existing?['currency']?.toString() ?? 'YER';
    var from = _asDate(existing?['dateFrom']) ?? DateTime.now();
    var to = _asDate(existing?['dateTo']) ?? DateTime.now();
    var saving = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  id == null ? 'حجز سند تحصيل مراجع' : 'تعديل السند المحجوز',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 14),
                Text('الفرع: ${widget.branchName}'),
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'المبلغ المراجع',
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: currency,
                  decoration: const InputDecoration(labelText: 'العملة'),
                  items: const ['YER', 'SAR', 'USD']
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: saving
                      ? null
                      : (value) => setSheetState(() => currency = value!),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('من: ${_date.format(from)}'),
                  trailing: const Icon(Icons.date_range_outlined),
                  onTap: () async {
                    final picked = await _pickDate(context, from);
                    if (picked != null) setSheetState(() => from = picked);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('إلى: ${_date.format(to)}'),
                  trailing: const Icon(Icons.date_range_outlined),
                  onTap: () async {
                    final picked = await _pickDate(context, to);
                    if (picked != null) setSheetState(() => to = picked);
                  },
                ),
                TextField(
                  controller: reference,
                  decoration: const InputDecoration(
                    labelText: 'مرجع المراجعة (اختياري)',
                  ),
                ),
                TextField(
                  controller: note,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظة (اختيارية)',
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          final value = double.tryParse(
                            amount.text.trim().replaceAll(',', ''),
                          );
                          if (value == null ||
                              value <= 0 ||
                              to.isBefore(from)) {
                            _message('تحقق من المبلغ وفترة التحصيل.');
                            return;
                          }
                          setSheetState(() => saving = true);
                          try {
                            if (id == null) {
                              final number = await _database
                                  .reserveReviewedCollectionVoucher(
                                    branchId: widget.branchId,
                                    reviewedAmount: value,
                                    currency: currency,
                                    dateFrom: from,
                                    dateTo: to,
                                    reference: reference.text,
                                    note: note.text,
                                  );
                              if (context.mounted) Navigator.pop(context);
                              if (mounted)
                                _message(
                                  'تم حجز السند رقم $number بانتظار التحصيل.',
                                );
                            } else {
                              await _database.updateReservedCollectionVoucher(
                                transactionId: id,
                                reviewedAmount: value,
                                currency: currency,
                                dateFrom: from,
                                dateTo: to,
                                reference: reference.text,
                                note: note.text,
                              );
                              if (context.mounted) Navigator.pop(context);
                              if (mounted)
                                _message('تم تعديل المسودة المحجوزة.');
                            }
                          } catch (error) {
                            _message(
                              'تعذر حفظ المسودة: ${error.toString().replaceFirst('Exception: ', '')}',
                            );
                            setSheetState(() => saving = false);
                          }
                        },
                  icon: const Icon(Icons.bookmark_added_rounded),
                  label: Text(id == null ? 'حجز الرقم الرسمي' : 'حفظ التعديل'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    amount.dispose();
    reference.dispose();
    note.dispose();
  }

  Future<void> _showPhysicalReceipt(
    String id,
    Map<String, dynamic> data,
  ) async {
    final amount = TextEditingController(
      text:
          ((data['reviewed_amount'] as num?) ?? (data['amount'] as num?))
              ?.toString() ??
          '',
    );
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تسجيل التحصيل الفعلي'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('سيبقى الرقم المحجوز كما هو، ولن يتم إنشاء سند جديد.'),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'المبلغ المحصل فعلياً',
              ),
            ),
            TextField(
              controller: reason,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'سبب الفرق عند اختلاف المبلغ',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تأكيد التحصيل'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        final value = double.tryParse(amount.text.trim().replaceAll(',', ''));
        if (value == null) throw Exception('أدخل مبلغاً صحيحاً.');
        await _database.collectReservedCollectionVoucher(
          transactionId: id,
          physicalAmount: value,
          differenceReason: reason.text,
        );
        if (mounted) _message('تم تسجيل التحصيل الفعلي للسند المحجوز.');
      } catch (error) {
        if (mounted)
          _message(
            'تعذر تسجيل التحصيل: ${error.toString().replaceFirst('Exception: ', '')}',
          );
      }
    }
    amount.dispose();
    reason.dispose();
  }

  Future<void> _cancelReservation(String id) async {
    final reason = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إلغاء السند المحجوز'),
        content: TextField(
          controller: reason,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'سبب الإلغاء'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, reason.text),
            child: const Text('إلغاء السند'),
          ),
        ],
      ),
    );
    reason.dispose();
    if (value == null) return;
    try {
      await _database.cancelReservedCollectionVoucher(
        transactionId: id,
        reason: value,
      );
      if (mounted) _message('تم إلغاء السند مع الاحتفاظ برقمه في السجل.');
    } catch (error) {
      if (mounted)
        _message(
          'تعذر إلغاء السند: ${error.toString().replaceFirst('Exception: ', '')}',
        );
    }
  }

  Future<void> _approveDifference(String id) async {
    final note = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('مراجعة فرق التحصيل'),
        content: TextField(
          controller: note,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'ملاحظة المراجعة'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, note.text),
            child: const Text('اعتماد التصحيح'),
          ),
        ],
      ),
    );
    note.dispose();
    if (value == null) return;
    try {
      await _database.approveReservedCollectionDifference(
        transactionId: id,
        note: value,
      );
      if (mounted)
        _message('تمت مراجعة فرق التحصيل وإدخال السند لمساره المعتاد.');
    } catch (error) {
      if (mounted)
        _message(
          'تعذر مراجعة الفرق: ${error.toString().replaceFirst('Exception: ', '')}',
        );
    }
  }

  Future<DateTime?> _pickDate(BuildContext context, DateTime initial) =>
      showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 365)),
      );

  DateTime? _asDate(dynamic value) => value is Timestamp
      ? value.toDate()
      : value is DateTime
      ? value
      : null;
  String _dateOf(dynamic value) =>
      _asDate(value) == null ? '-' : _date.format(_asDate(value)!);
  void _message(String value) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(value)));
}
