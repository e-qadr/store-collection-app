import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/models/purchase_invoice_model.dart';
import 'package:store_collection_app/screens/purchase_invoices/purchase_invoice_details_screen.dart';
import 'package:store_collection_app/services/purchase_invoice_service.dart';
import 'package:store_collection_app/theme/app_theme.dart';

enum _HistorySort {
  newestCreated,
  oldestCreated,
  latestUpdated,
  supplierName,
  purchaseNumber,
}

enum _HistoryDateField { created, updated, supplier }

enum _HistoryDatePreset {
  all,
  today,
  last7Days,
  last30Days,
  thisMonth,
  thisYear,
  custom,
}

typedef PurchaseInvoiceDetailBuilder =
    Widget Function(BuildContext context, PurchaseInvoiceRead invoice);

class PurchaseInvoiceHistoryScreen extends StatefulWidget {
  final UserRole role;
  final String? branchId;
  final String branchName;
  final Stream<List<PurchaseInvoiceRead>>? invoiceStream;
  final PurchaseInvoiceDetailBuilder? detailBuilder;

  const PurchaseInvoiceHistoryScreen({
    super.key,
    required this.role,
    required this.branchName,
    this.branchId,
    this.invoiceStream,
    this.detailBuilder,
  });

  @override
  State<PurchaseInvoiceHistoryScreen> createState() =>
      _PurchaseInvoiceHistoryScreenState();
}

class _PurchaseInvoiceHistoryScreenState
    extends State<PurchaseInvoiceHistoryScreen> {
  final _search = TextEditingController();
  late final PurchaseInvoiceService _service = PurchaseInvoiceService();
  late final Stream<List<PurchaseInvoiceRead>> _invoiceStream =
      widget.invoiceStream ??
      _service.watchHistory(role: widget.role, branchId: widget.branchId);

  PurchaseInvoiceStatus? _status;
  bool _amendmentsOnly = false;
  String? _supplier;
  String? _currency;
  String? _supplierDocumentState;
  _HistoryDateField _dateField = _HistoryDateField.updated;
  _HistoryDatePreset _datePreset = _HistoryDatePreset.all;
  DateTimeRange? _customDateRange;
  _HistorySort _sort = _HistorySort.latestUpdated;

  @override
  void initState() {
    super.initState();
    _search.addListener(_refresh);
  }

  @override
  void dispose() {
    _search
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  String get _scopeName {
    final name = widget.branchName.trim();
    return name.isEmpty ? 'الفرع المحدد' : name;
  }

  bool get _hasAdvancedFilters =>
      _supplier != null ||
      _currency != null ||
      _supplierDocumentState != null ||
      _datePreset != _HistoryDatePreset.all ||
      _dateField != _HistoryDateField.updated;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      appBar: AppBar(title: const Text('سجل فواتير المشتريات')),
      body: StreamBuilder<List<PurchaseInvoiceRead>>(
        stream: _invoiceStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(
              child: Text('تعذر تحميل سجل فواتير المشتريات.'),
            );
          }
          final source = _scoped(snapshot.data ?? const []);
          final invoices = _filtered(source);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              _scopeHeader(source.length, invoices.length),
              const SizedBox(height: 12),
              _filters(source),
              const SizedBox(height: 16),
              if (invoices.isEmpty) _emptyState() else ...invoices.map(_card),
            ],
          );
        },
      ),
    ),
  );

  List<PurchaseInvoiceRead> _scoped(List<PurchaseInvoiceRead> source) {
    final branchId = widget.branchId?.trim() ?? '';
    if (branchId.isEmpty) return source;
    // Keep injected/test streams aligned with the branch-scoped server query.
    return source
        .where((invoice) => invoice.receivingBranchId == branchId)
        .toList(growable: false);
  }

  Widget _scopeHeader(int total, int visible) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          AppTheme.primaryOlive,
          AppTheme.primaryOlive.withValues(alpha: .82),
        ],
      ),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .16),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.storefront_rounded, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _scopeName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                widget.branchId?.trim().isNotEmpty == true
                    ? 'سجل هذا الفرع فقط'
                    : 'السجل المتاح حسب صلاحيتك',
                style: TextStyle(color: Colors.white.withValues(alpha: .82)),
              ),
            ],
          ),
        ),
        _countPill(visible, total),
      ],
    ),
  );

  Widget _countPill(int visible, int total) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .16),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [
        Text(
          '$visible',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        Text(
          total == visible ? 'فاتورة' : 'من $total',
          style: TextStyle(
            color: Colors.white.withValues(alpha: .82),
            fontSize: 11,
          ),
        ),
      ],
    ),
  );

  Widget _filters(List<PurchaseInvoiceRead> source) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('purchase-history-search'),
            controller: _search,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              hintText: 'ابحث بالرقم أو المورد أو رقم فاتورة المورد',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 12),
          const Text('الحالة', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 7),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('الكل'),
                  selected: _status == null,
                  onSelected: (_) => setState(() => _status = null),
                ),
                const SizedBox(width: 7),
                ...PurchaseInvoiceStatus.values
                    .where((status) => status != PurchaseInvoiceStatus.unknown)
                    .map(
                      (status) => Padding(
                        padding: const EdgeInsetsDirectional.only(end: 7),
                        child: ChoiceChip(
                          label: Text(status.label),
                          selected: _status == status,
                          selectedColor: status.color.withValues(alpha: .16),
                          onSelected: (_) => setState(() => _status = status),
                        ),
                      ),
                    ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilterChip(
                  key: const Key('purchase-history-amendments-filter'),
                  avatar: const Icon(Icons.edit_note_rounded, size: 18),
                  label: const Text('تعديل بانتظار الإجراء'),
                  selected: _amendmentsOnly,
                  onSelected: (value) =>
                      setState(() => _amendmentsOnly = value),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const Key('purchase-history-open-filters'),
                onPressed: () => _openFilterSheet(source),
                icon: Badge(
                  isLabelVisible: _hasAdvancedFilters,
                  smallSize: 8,
                  child: const Icon(Icons.tune_rounded),
                ),
                label: const Text('فلترة'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<_HistorySort>(
            key: const Key('purchase-history-sort'),
            initialValue: _sort,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'الترتيب',
              prefixIcon: Icon(Icons.sort_rounded),
            ),
            items: _HistorySort.values
                .map(
                  (sort) => DropdownMenuItem(
                    value: sort,
                    child: Text(_sortLabel(sort)),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value != null) setState(() => _sort = value);
            },
          ),
        ],
      ),
    ),
  );

  Future<void> _openFilterSheet(List<PurchaseInvoiceRead> source) async {
    final suppliers =
        source
            .map((invoice) => invoice.supplierName.trim())
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final currencies =
        source
            .map((invoice) => invoice.currency.trim().toUpperCase())
            .where((currency) => currency.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    var supplier = _supplier;
    var currency = _currency;
    var supplierDocumentState = _supplierDocumentState;
    var dateField = _dateField;
    var datePreset = _datePreset;
    var customRange = _customDateRange;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          padding: EdgeInsets.fromLTRB(
            20,
            14,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          decoration: const BoxDecoration(
            color: AppTheme.surfaceColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppTheme.textHint.withValues(alpha: .35),
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'فلترة متقدمة',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'تطبّق ضمن نطاق الفرع الظاهر فقط.',
                    style: TextStyle(color: AppTheme.textHint),
                  ),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String?>(
                    initialValue: supplier,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'المورد',
                      prefixIcon: Icon(Icons.business_rounded),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('كل الموردين'),
                      ),
                      ...suppliers.map(
                        (item) => DropdownMenuItem<String?>(
                          value: item,
                          child: Text(item, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                    onChanged: (value) => setSheetState(() => supplier = value),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: currency,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'العملة',
                      prefixIcon: Icon(Icons.payments_rounded),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('كل العملات'),
                      ),
                      ...currencies.map(
                        (item) => DropdownMenuItem<String?>(
                          value: item,
                          child: Text(item),
                        ),
                      ),
                    ],
                    onChanged: (value) => setSheetState(() => currency = value),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'بيانات فاتورة المورد',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('الكل'),
                        selected: supplierDocumentState == null,
                        onSelected: (_) =>
                            setSheetState(() => supplierDocumentState = null),
                      ),
                      ChoiceChip(
                        label: const Text('مكتملة البيانات'),
                        selected: supplierDocumentState == 'present',
                        onSelected: (_) => setSheetState(
                          () => supplierDocumentState = 'present',
                        ),
                      ),
                      ChoiceChip(
                        label: const Text('بيانات ناقصة'),
                        selected: supplierDocumentState == 'missing',
                        onSelected: (_) => setSheetState(
                          () => supplierDocumentState = 'missing',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'التاريخ',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<_HistoryDateField>(
                    initialValue: dateField,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.event_rounded),
                    ),
                    items: _HistoryDateField.values
                        .map(
                          (field) => DropdownMenuItem(
                            value: field,
                            child: Text(_dateFieldLabel(field)),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value != null) {
                        setSheetState(() => dateField = value);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _HistoryDatePreset.values
                        .map(
                          (preset) => ChoiceChip(
                            label: Text(_datePresetLabel(preset)),
                            selected: datePreset == preset,
                            onSelected: (_) async {
                              if (preset != _HistoryDatePreset.custom) {
                                setSheetState(() => datePreset = preset);
                                return;
                              }
                              final selected = await showDateRangePicker(
                                context: sheetContext,
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now().add(
                                  const Duration(days: 1),
                                ),
                                initialDateRange: customRange,
                                helpText: 'حدد الفترة الزمنية',
                              );
                              if (selected != null) {
                                setSheetState(() {
                                  customRange = selected;
                                  datePreset = _HistoryDatePreset.custom;
                                });
                              }
                            },
                          ),
                        )
                        .toList(growable: false),
                  ),
                  if (datePreset == _HistoryDatePreset.custom &&
                      customRange != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '${_date(customRange!.start)} — ${_date(customRange!.end)}',
                        style: const TextStyle(color: AppTheme.oliveGreen),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => setSheetState(() {
                          supplier = null;
                          currency = null;
                          supplierDocumentState = null;
                          dateField = _HistoryDateField.updated;
                          datePreset = _HistoryDatePreset.all;
                          customRange = null;
                        }),
                        child: const Text('مسح الفلاتر'),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              _supplier = supplier;
                              _currency = currency;
                              _supplierDocumentState = supplierDocumentState;
                              _dateField = dateField;
                              _datePreset = datePreset;
                              _customDateRange = customRange;
                            });
                            Navigator.pop(sheetContext);
                          },
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('تطبيق الفلترة'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<PurchaseInvoiceRead> _filtered(List<PurchaseInvoiceRead> source) {
    final query = _search.text.trim().toLowerCase();
    final range = _selectedDateRange();
    final result = source
        .where((invoice) {
          final matchesQuery =
              query.isEmpty ||
              [
                invoice.purchaseNumber,
                invoice.supplierName,
                invoice.supplierInvoiceNumber,
                invoice.receivingBranchName,
                invoice.currency,
                invoice.status.label,
                invoice.currentResponsibleParty,
              ].any((value) => value.toLowerCase().contains(query));
          final hasSupplierDocument =
              invoice.supplierInvoiceNumber.trim().isNotEmpty &&
              invoice.supplierInvoiceDate.trim().isNotEmpty;
          final invoiceDate = _invoiceDate(invoice, _dateField);
          final matchesDate =
              range == null ||
              (invoiceDate != null &&
                  !invoiceDate.isBefore(range.start) &&
                  invoiceDate.isBefore(range.end));
          return matchesQuery &&
              (_status == null || invoice.status == _status) &&
              (!_amendmentsOnly || invoice.hasPendingAmendment) &&
              (_supplier == null || invoice.supplierName.trim() == _supplier) &&
              (_currency == null ||
                  invoice.currency.trim().toUpperCase() == _currency) &&
              (_supplierDocumentState == null ||
                  (_supplierDocumentState == 'present') ==
                      hasSupplierDocument) &&
              matchesDate;
        })
        .toList(growable: false);
    result.sort(
      (left, right) => switch (_sort) {
        _HistorySort.newestCreated =>
          (right.createdAt ?? DateTime(0)).compareTo(
            left.createdAt ?? DateTime(0),
          ),
        _HistorySort.oldestCreated => (left.createdAt ?? DateTime(0)).compareTo(
          right.createdAt ?? DateTime(0),
        ),
        _HistorySort.latestUpdated =>
          (right.lastUpdated ?? DateTime(0)).compareTo(
            left.lastUpdated ?? DateTime(0),
          ),
        _HistorySort.supplierName => left.supplierName.compareTo(
          right.supplierName,
        ),
        _HistorySort.purchaseNumber => left.purchaseNumber.compareTo(
          right.purchaseNumber,
        ),
      },
    );
    return result;
  }

  _HistoryRange? _selectedDateRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (_datePreset) {
      _HistoryDatePreset.all => null,
      _HistoryDatePreset.today => _HistoryRange(
        today,
        today.add(const Duration(days: 1)),
      ),
      _HistoryDatePreset.last7Days => _HistoryRange(
        today.subtract(const Duration(days: 6)),
        today.add(const Duration(days: 1)),
      ),
      _HistoryDatePreset.last30Days => _HistoryRange(
        today.subtract(const Duration(days: 29)),
        today.add(const Duration(days: 1)),
      ),
      _HistoryDatePreset.thisMonth => _HistoryRange(
        DateTime(now.year, now.month),
        DateTime(now.year, now.month + 1),
      ),
      _HistoryDatePreset.thisYear => _HistoryRange(
        DateTime(now.year),
        DateTime(now.year + 1),
      ),
      _HistoryDatePreset.custom =>
        _customDateRange == null
            ? null
            : _HistoryRange(
                DateTime(
                  _customDateRange!.start.year,
                  _customDateRange!.start.month,
                  _customDateRange!.start.day,
                ),
                DateTime(
                  _customDateRange!.end.year,
                  _customDateRange!.end.month,
                  _customDateRange!.end.day + 1,
                ),
              ),
    };
  }

  DateTime? _invoiceDate(
    PurchaseInvoiceRead invoice,
    _HistoryDateField field,
  ) => switch (field) {
    _HistoryDateField.created => invoice.createdAt,
    _HistoryDateField.updated => invoice.lastUpdated,
    _HistoryDateField.supplier => _parseSupplierDate(
      invoice.supplierInvoiceDate,
    ),
  };

  DateTime? _parseSupplierDate(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final normalized = value.replaceAll('/', '-');
    return DateTime.tryParse(normalized) ??
        _tryDateFormat('dd-MM-yyyy', normalized) ??
        _tryDateFormat('yyyy-MM-dd HH:mm', normalized);
  }

  DateTime? _tryDateFormat(String format, String value) {
    try {
      return DateFormat(format).parseStrict(value);
    } catch (_) {
      return null;
    }
  }

  Widget _emptyState() => Card(
    margin: const EdgeInsets.only(top: 42),
    child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        children: [
          const Icon(
            Icons.receipt_long_outlined,
            size: 52,
            color: AppTheme.textHint,
          ),
          const SizedBox(height: 12),
          const Text(
            'لا توجد فواتير مطابقة',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
          ),
          const SizedBox(height: 5),
          const Text(
            'غيّر البحث أو الفلاتر للوصول إلى الفواتير المطلوبة.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textHint),
          ),
        ],
      ),
    ),
  );

  Widget _card(PurchaseInvoiceRead invoice) {
    final supplierDate = invoice.supplierInvoiceDate.trim();
    final visibleDate = supplierDate.isNotEmpty
        ? supplierDate
        : (invoice.createdAt == null
              ? 'بدون تاريخ'
              : _date(invoice.createdAt!));
    return Card(
      key: Key('purchase-history-${invoice.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (detailContext) =>
                widget.detailBuilder?.call(detailContext, invoice) ??
                PurchaseInvoiceDetailsScreen(
                  invoiceId: invoice.documentId,
                  role: widget.role,
                  branchId: widget.branchId,
                ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: invoice.status.color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.receipt_long_rounded,
                  color: invoice.status.color,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            invoice.purchaseNumber,
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (invoice.hasPendingAmendment)
                          const Tooltip(
                            message: 'يوجد طلب تعديل بانتظار الإجراء',
                            child: Icon(
                              Icons.edit_note_rounded,
                              color: AppTheme.warningColor,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      invoice.supplierName.trim().isEmpty
                          ? 'مورد غير محدد'
                          : invoice.supplierName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Wrap(
                      spacing: 7,
                      runSpacing: 6,
                      children: [
                        _statusPill(invoice.status),
                        _factPill(Icons.calendar_today_rounded, visibleDate),
                        _factPill(
                          Icons.inventory_2_outlined,
                          '${invoice.itemCount} مادة',
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(
                          Icons.update_rounded,
                          size: 15,
                          color: AppTheme.textHint,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            invoice.lastUpdated == null
                                ? 'لم يحدّث بعد'
                                : 'آخر تحديث ${_dateTime(invoice.lastUpdated!)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.textHint,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              const Padding(
                padding: EdgeInsets.only(top: 14),
                child: Icon(
                  Icons.chevron_left_rounded,
                  color: AppTheme.textHint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusPill(PurchaseInvoiceStatus status) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: status.color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      status.label,
      style: TextStyle(
        color: status.color,
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  Widget _factPill(IconData icon, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
    decoration: BoxDecoration(
      color: AppTheme.oliveSurface.withValues(alpha: .58),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppTheme.textSecondary),
        const SizedBox(width: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
        ),
      ],
    ),
  );

  String _sortLabel(_HistorySort sort) => switch (sort) {
    _HistorySort.latestUpdated => 'آخر تحديث',
    _HistorySort.newestCreated => 'الأحدث إنشاءً',
    _HistorySort.oldestCreated => 'الأقدم إنشاءً',
    _HistorySort.supplierName => 'اسم المورد',
    _HistorySort.purchaseNumber => 'رقم الفاتورة',
  };

  String _dateFieldLabel(_HistoryDateField field) => switch (field) {
    _HistoryDateField.created => 'تاريخ إنشاء الفاتورة',
    _HistoryDateField.updated => 'تاريخ آخر تحديث',
    _HistoryDateField.supplier => 'تاريخ فاتورة المورد',
  };

  String _datePresetLabel(_HistoryDatePreset preset) => switch (preset) {
    _HistoryDatePreset.all => 'كل الفترات',
    _HistoryDatePreset.today => 'اليوم',
    _HistoryDatePreset.last7Days => 'آخر 7 أيام',
    _HistoryDatePreset.last30Days => 'آخر 30 يومًا',
    _HistoryDatePreset.thisMonth => 'هذا الشهر',
    _HistoryDatePreset.thisYear => 'هذه السنة',
    _HistoryDatePreset.custom => 'فترة مخصصة',
  };

  String _date(DateTime value) => DateFormat('yyyy/MM/dd').format(value);
  String _dateTime(DateTime value) =>
      DateFormat('yyyy/MM/dd HH:mm').format(value);
}

class _HistoryRange {
  final DateTime start;
  final DateTime end;

  const _HistoryRange(this.start, this.end);
}
