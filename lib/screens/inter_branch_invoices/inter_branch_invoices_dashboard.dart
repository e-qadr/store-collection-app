import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/models/inter_branch_invoice_model.dart';
import 'package:store_collection_app/screens/inter_branch_invoices/inter_branch_invoice_details_screen.dart';
import 'package:store_collection_app/screens/inter_branch_invoices/new_inter_branch_invoice_screen.dart';
import 'package:store_collection_app/services/inter_branch_invoice_service.dart';
import 'package:store_collection_app/theme/app_theme.dart';
import 'package:store_collection_app/utils/logout_confirmation.dart';
import 'package:store_collection_app/widgets/dashboard_widgets.dart';
import 'package:store_collection_app/widgets/notification_bell.dart';

enum _InvoiceBox { incoming, outgoing }

class _BranchFilterOption {
  final String id;
  final String name;

  const _BranchFilterOption({required this.id, required this.name});
}

class InterBranchInvoicesDashboard extends StatefulWidget {
  final UserRole role;
  final String? branchId;
  final String branchName;

  const InterBranchInvoicesDashboard({
    super.key,
    required this.role,
    required this.branchName,
    this.branchId,
  });

  @override
  State<InterBranchInvoicesDashboard> createState() =>
      _InterBranchInvoicesDashboardState();
}

class _InterBranchInvoicesDashboardState
    extends State<InterBranchInvoicesDashboard> {
  final _service = InterBranchInvoiceService();

  bool get _canCreateRequest =>
      widget.role == UserRole.manager &&
      widget.branchId != null &&
      widget.branchId!.isNotEmpty;

  bool get _hasBranch =>
      widget.branchId != null && widget.branchId!.trim().isNotEmpty;

  Color get _roleColor => _roleColorFor(widget.role);

  List<Color> get _roleGradient => _roleGradientFor(widget.role);

  String get _roleLabel => _roleLabelFor(widget.role);

  IconData get _roleIcon => _roleIconFor(widget.role);

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        floatingActionButton: _canCreateRequest
            ? FloatingActionButton.extended(
                onPressed: _openNewRequest,
                icon: const Icon(Icons.add_rounded),
                label: const Text('طلب جديد'),
                backgroundColor: AppTheme.managerColor,
              )
            : null,
        body: CustomScrollView(
          slivers: [
            _buildSliverAppBar(),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 92),
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _service.watchInvoices(
                    role: widget.role,
                    branchId: widget.branchId,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SizedBox(
                        height: 220,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snapshot.hasError) {
                      return _emptyState(
                        icon: Icons.error_outline_rounded,
                        title: 'تعذر تحميل الفواتير',
                        subtitle: 'تحقق من الاتصال ثم حاول مرة أخرى.',
                      );
                    }

                    final invoices = _invoiceList(snapshot.data);
                    final incoming = _incomingInvoices(invoices);
                    final outgoing = _outgoingInvoices(invoices);
                    final dashboardInvoices = widget.role == UserRole.manager
                        ? [...incoming, ...outgoing]
                        : outgoing;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildStats(dashboardInvoices),
                        const SizedBox(height: 24),
                        const SectionHeader(
                          title: 'لوحة فواتير الفروع',
                          icon: Icons.dashboard_customize_rounded,
                          color: Color(0xFF0277BD),
                        ),
                        const SizedBox(height: 14),
                        if (_canCreateRequest) ...[
                          _controlCard(
                            title: 'طلب فاتورة جديد',
                            subtitle:
                                'إنشاء طلب منتجات من فرع آخر وإضافتها كسطور فاتورة.',
                            countLabel: 'جديد',
                            icon: Icons.add_circle_outline_rounded,
                            color: AppTheme.managerColor,
                            onTap: _openNewRequest,
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (widget.role == UserRole.manager) ...[
                          _controlCard(
                            title: 'الوارد إلى فرعي',
                            subtitle:
                                'طلبات أرسلتها الفروع الأخرى إلى فرعك للموافقة أو الرفض.',
                            countLabel: '${incoming.length}',
                            icon: Icons.move_to_inbox_rounded,
                            color: AppTheme.managerColor,
                            onTap: () => _openBox(_InvoiceBox.incoming),
                          ),
                          const SizedBox(height: 12),
                        ],
                        _controlCard(
                          title: widget.role == UserRole.manager
                              ? 'طلبات فرعي الصادرة'
                              : 'فواتير الفرع الصادرة',
                          subtitle: widget.role == UserRole.manager
                              ? 'طلبات أنشأها فرعك وتنتظر متابعة الفروع الأخرى.'
                              : 'الفواتير التي خرجت من الفرع المختار فقط.',
                          countLabel: '${outgoing.length}',
                          icon: Icons.outbox_rounded,
                          color: const Color(0xFF0277BD),
                          onTap: () => _openBox(_InvoiceBox.outgoing),
                        ),
                        if (!_hasBranch) ...[
                          const SizedBox(height: 16),
                          _emptyState(
                            icon: Icons.storefront_outlined,
                            title: 'لا يوجد فرع محدد',
                            subtitle:
                                'اختر فرعاً من شاشة اختيار الفروع قبل فتح فواتير النظام.',
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  SliverAppBar _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 170,
      pinned: true,
      backgroundColor: _roleColor,
      actions: [
        const NotificationBell(),
        IconButton(
          icon: const Icon(Icons.logout_rounded),
          tooltip: 'تسجيل الخروج',
          onPressed: () => confirmAndSignOut(context),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: true,
        title: const Text(
          'فواتير الطلبات بين الفروع',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        background: RoleAppBarBackground(
          gradientColors: _roleGradient,
          title: widget.branchName,
          subtitle: _roleLabel,
          icon: _roleIcon,
        ),
      ),
    );
  }

  Widget _buildStats(List<InterBranchInvoiceRead> invoices) {
    final pending = invoices
        .where(
          (invoice) =>
              invoice.status == InterBranchInvoiceStatus.requestPending,
        )
        .length;
    final awaitingAccounting = invoices
        .where(
          (invoice) =>
              invoice.status == InterBranchInvoiceStatus.pendingAccountingEntry,
        )
        .length;
    final posted = invoices
        .where(
          (invoice) =>
              invoice.status == InterBranchInvoiceStatus.postedToAccounting,
        )
        .length;

    return Row(
      children: [
        Expanded(
          child: StatCard(
            label: 'الإجمالي',
            value: '${invoices.length}',
            icon: Icons.receipt_long_rounded,
            color: const Color(0xFF0277BD),
            bgColor: const Color(0xFFE1F5FE),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatCard(
            label: 'بانتظار قرار',
            value: '$pending',
            icon: Icons.pending_actions_rounded,
            color: AppTheme.warningColor,
            bgColor: const Color(0xFFFFF3E0),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatCard(
            label: widget.role == UserRole.manager ? 'مرحلة' : 'بانتظار ترحيل',
            value: widget.role == UserRole.manager
                ? '$posted'
                : '$awaitingAccounting',
            icon: widget.role == UserRole.manager
                ? Icons.verified_rounded
                : Icons.calculate_rounded,
            color: widget.role == UserRole.manager
                ? AppTheme.successColor
                : AppTheme.accountantColor,
            bgColor: widget.role == UserRole.manager
                ? const Color(0xFFE8F5E9)
                : const Color(0xFFEDE7F6),
          ),
        ),
      ],
    );
  }

  Widget _controlCard({
    required String title,
    required String subtitle,
    required String countLabel,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: AppTheme.cardShadow(),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: _hasBranch || title == 'طلب فاتورة جديد' ? onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    countLabel,
                    style: TextStyle(color: color, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_left_rounded, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openNewRequest() {
    final branchId = widget.branchId;
    if (branchId == null || branchId.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NewInterBranchInvoiceScreen(
          branchId: branchId,
          branchName: widget.branchName,
        ),
      ),
    );
  }

  void _openBox(_InvoiceBox box) {
    final branchId = widget.branchId;
    if (branchId == null || branchId.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _InterBranchInvoicesBoxScreen(
          role: widget.role,
          branchId: branchId,
          branchName: widget.branchName,
          box: box,
        ),
      ),
    );
  }

  List<InterBranchInvoiceRead> _incomingInvoices(
    List<InterBranchInvoiceRead> invoices,
  ) {
    final branchId = widget.branchId;
    if (branchId == null || branchId.isEmpty) return const [];
    return invoices
        .where((invoice) => invoice.sendingBranchId == branchId)
        .toList();
  }

  List<InterBranchInvoiceRead> _outgoingInvoices(
    List<InterBranchInvoiceRead> invoices,
  ) {
    final branchId = widget.branchId;
    if (branchId == null || branchId.isEmpty) return const [];
    if (widget.role == UserRole.manager) {
      return invoices
          .where((invoice) => invoice.receivingBranchId == branchId)
          .toList();
    }
    return invoices
        .where((invoice) => invoice.sendingBranchId == branchId)
        .toList();
  }

  List<InterBranchInvoiceRead> _invoiceList(
    QuerySnapshot<Map<String, dynamic>>? snapshot,
  ) {
    final invoices = (snapshot?.docs ?? [])
        .map((doc) => InterBranchInvoiceRead(id: doc.id, data: doc.data()))
        .toList();
    invoices.sort((a, b) {
      final aDate =
          a.invoiceCreatedAt ??
          a.requestDate ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bDate =
          b.invoiceCreatedAt ??
          b.requestDate ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    return invoices;
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 32),
      decoration: AppTheme.cardShadow(),
      child: Column(
        children: [
          Icon(icon, size: 52, color: AppTheme.textHint),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(color: AppTheme.textSecondary, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _InterBranchInvoicesBoxScreen extends StatefulWidget {
  final UserRole role;
  final String branchId;
  final String branchName;
  final _InvoiceBox box;

  const _InterBranchInvoicesBoxScreen({
    required this.role,
    required this.branchId,
    required this.branchName,
    required this.box,
  });

  @override
  State<_InterBranchInvoicesBoxScreen> createState() =>
      _InterBranchInvoicesBoxScreenState();
}

class _InterBranchInvoicesBoxScreenState
    extends State<_InterBranchInvoicesBoxScreen> {
  static const _allFilterValue = '__all__';

  final _service = InterBranchInvoiceService();
  final _numberFormat = NumberFormat('#,##0.##');
  final _dateFormat = DateFormat('yyyy/MM/dd');

  String _branchFilter = _allFilterValue;
  InterBranchInvoiceStatus? _statusFilter;
  DateTime? _fromDate;
  DateTime? _toDate;

  bool get _showsPrices =>
      widget.role == UserRole.accountant || widget.role == UserRole.collector;

  Color get _roleColor => _roleColorFor(widget.role);

  String get _boxTitle {
    if (widget.role == UserRole.manager && widget.box == _InvoiceBox.incoming) {
      return 'الوارد إلى فرعي';
    }
    if (widget.role == UserRole.manager) return 'طلبات فرعي الصادرة';
    return 'فواتير الفرع الصادرة';
  }

  String get _counterpartBranchLabel {
    if (widget.role == UserRole.manager && widget.box == _InvoiceBox.incoming) {
      return 'الفرع الطالب';
    }
    if (widget.role != UserRole.manager) return 'الفرع المستلم';
    return 'الفرع المورد';
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(
          title: Text(_boxTitle),
          backgroundColor: _roleColor,
          actions: const [NotificationBell()],
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _service.watchInvoices(
            role: widget.role,
            branchId: widget.branchId,
          ),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _emptyState(
                icon: Icons.error_outline_rounded,
                title: 'تعذر تحميل الفواتير',
                subtitle: 'تحقق من الاتصال ثم حاول مرة أخرى.',
              );
            }

            final invoices = _invoiceList(snapshot.data);
            final scoped = _scopedInvoices(invoices);
            final visibleInvoices = _visibleInvoices(scoped);

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
              children: [
                _boxSummary(scoped, visibleInvoices),
                const SizedBox(height: 14),
                _compactFilterBar(scoped, visibleInvoices),
                const SizedBox(height: 14),
                SectionHeader(
                  title: _boxTitle,
                  icon: widget.box == _InvoiceBox.incoming
                      ? Icons.move_to_inbox_rounded
                      : Icons.outbox_rounded,
                  color: _roleColor,
                ),
                const SizedBox(height: 12),
                if (visibleInvoices.isEmpty)
                  _emptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'لا توجد فواتير',
                    subtitle: 'لا توجد نتائج مطابقة لهذا الصندوق أو الفلاتر.',
                  )
                else
                  _buildInvoicesList(visibleInvoices),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _boxSummary(
    List<InterBranchInvoiceRead> scoped,
    List<InterBranchInvoiceRead> visible,
  ) {
    final pending = scoped
        .where(
          (invoice) =>
              invoice.status == InterBranchInvoiceStatus.requestPending,
        )
        .length;
    final posted = scoped
        .where(
          (invoice) =>
              invoice.status == InterBranchInvoiceStatus.postedToAccounting,
        )
        .length;

    return Row(
      children: [
        Expanded(
          child: StatCard(
            label: 'في الصندوق',
            value: '${scoped.length}',
            icon: Icons.all_inbox_rounded,
            color: const Color(0xFF0277BD),
            bgColor: const Color(0xFFE1F5FE),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatCard(
            label: 'ظاهرة',
            value: '${visible.length}',
            icon: Icons.filter_alt_rounded,
            color: AppTheme.warningColor,
            bgColor: const Color(0xFFFFF3E0),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatCard(
            label: 'مرحلة',
            value: '$posted',
            icon: pending > 0
                ? Icons.pending_actions_rounded
                : Icons.verified_rounded,
            color: pending > 0 ? AppTheme.warningColor : AppTheme.successColor,
            bgColor: pending > 0
                ? const Color(0xFFFFF3E0)
                : const Color(0xFFE8F5E9),
          ),
        ),
      ],
    );
  }

  List<InterBranchInvoiceRead> _visibleInvoices(
    List<InterBranchInvoiceRead> invoices,
  ) {
    final effectiveBranchFilter = _effectiveBranchFilter(invoices);
    return invoices.where((invoice) {
      final branchMatches =
          effectiveBranchFilter == _allFilterValue ||
          _counterpartBranchId(invoice) == effectiveBranchFilter;
      final statusMatches =
          _statusFilter == null || invoice.status == _statusFilter;
      final dateMatches = _dateMatches(invoice);
      return branchMatches && statusMatches && dateMatches;
    }).toList();
  }

  List<InterBranchInvoiceRead> _scopedInvoices(
    List<InterBranchInvoiceRead> invoices,
  ) {
    return invoices.where((invoice) {
      if (widget.role == UserRole.manager &&
          widget.box == _InvoiceBox.incoming) {
        return invoice.sendingBranchId == widget.branchId;
      }
      if (widget.role == UserRole.manager) {
        return invoice.receivingBranchId == widget.branchId;
      }
      return invoice.sendingBranchId == widget.branchId;
    }).toList();
  }

  String _counterpartBranchId(InterBranchInvoiceRead invoice) {
    if (widget.role == UserRole.manager && widget.box == _InvoiceBox.incoming) {
      return invoice.receivingBranchId;
    }
    if (widget.role != UserRole.manager) return invoice.receivingBranchId;
    return invoice.sendingBranchId;
  }

  String _counterpartBranchName(InterBranchInvoiceRead invoice) {
    if (widget.role == UserRole.manager && widget.box == _InvoiceBox.incoming) {
      return invoice.receivingBranchName;
    }
    if (widget.role != UserRole.manager) return invoice.receivingBranchName;
    return invoice.sendingBranchName;
  }

  String _effectiveBranchFilter(List<InterBranchInvoiceRead> invoices) {
    if (_branchFilter == _allFilterValue) return _allFilterValue;
    final hasBranch = _branchFilterOptions(
      invoices,
    ).any((option) => option.id == _branchFilter);
    return hasBranch ? _branchFilter : _allFilterValue;
  }

  List<_BranchFilterOption> _branchFilterOptions(
    List<InterBranchInvoiceRead> invoices,
  ) {
    final options = <String, String>{};
    for (final invoice in invoices) {
      final id = _counterpartBranchId(invoice);
      if (id.isEmpty) continue;
      options[id] = _counterpartBranchName(invoice);
    }

    final result =
        options.entries
            .map(
              (entry) => _BranchFilterOption(id: entry.key, name: entry.value),
            )
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  bool _dateMatches(InterBranchInvoiceRead invoice) {
    final date = invoice.invoiceCreatedAt ?? invoice.requestDate;
    if (date == null) return _fromDate == null && _toDate == null;

    final day = DateTime(date.year, date.month, date.day);
    if (_fromDate != null && day.isBefore(_fromDate!)) return false;
    if (_toDate != null && day.isAfter(_toDate!)) return false;
    return true;
  }

  Widget _compactFilterBar(
    List<InterBranchInvoiceRead> scoped,
    List<InterBranchInvoiceRead> visible,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.cardShadow(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _roleColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  Icons.filter_alt_rounded,
                  color: _roleColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _hasActiveFilters
                      ? 'تظهر ${visible.length} من ${scoped.length} فاتورة'
                      : 'تظهر كل فواتير هذا الصندوق',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _openFiltersSheet(scoped),
                icon: const Icon(Icons.tune_rounded),
                label: const Text('فلترة'),
              ),
            ],
          ),
          if (_hasActiveFilters) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _activeFilterChips(scoped),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _activeFilterChips(List<InterBranchInvoiceRead> invoices) {
    final chips = <Widget>[];
    if (_branchFilter != _allFilterValue) {
      chips.add(
        _filterChip(_selectedBranchFilterName(invoices), () {
          setState(() => _branchFilter = _allFilterValue);
        }),
      );
    }
    if (_statusFilter != null) {
      chips.add(
        _filterChip(_statusFilter!.label, () {
          setState(() => _statusFilter = null);
        }),
      );
    }
    if (_fromDate != null) {
      chips.add(
        _filterChip('من ${_formatDate(_fromDate)}', () {
          setState(() => _fromDate = null);
        }),
      );
    }
    if (_toDate != null) {
      chips.add(
        _filterChip('إلى ${_formatDate(_toDate)}', () {
          setState(() => _toDate = null);
        }),
      );
    }
    return chips;
  }

  Widget _filterChip(String label, VoidCallback onDeleted) {
    return InputChip(
      label: Text(label),
      onDeleted: onDeleted,
      deleteIcon: const Icon(Icons.close_rounded, size: 16),
      visualDensity: VisualDensity.compact,
      backgroundColor: _roleColor.withValues(alpha: 0.08),
      side: BorderSide(color: _roleColor.withValues(alpha: 0.18)),
    );
  }

  String _selectedBranchFilterName(List<InterBranchInvoiceRead> invoices) {
    final options = _branchFilterOptions(invoices);
    for (final option in options) {
      if (option.id == _branchFilter) return option.name;
    }
    return 'فرع محدد';
  }

  Future<void> _openFiltersSheet(List<InterBranchInvoiceRead> invoices) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final branchOptions = _branchFilterOptions(invoices);
            final effectiveBranchFilter = _effectiveBranchFilter(invoices);

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 18,
                  right: 18,
                  top: 16,
                  bottom: 18 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'فلترة الفواتير',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          tooltip: 'إغلاق',
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      key: ValueKey('sheet-branch-$effectiveBranchFilter'),
                      initialValue: effectiveBranchFilter,
                      isExpanded: true,
                      decoration: _filterDecoration(_counterpartBranchLabel),
                      items: [
                        const DropdownMenuItem(
                          value: _allFilterValue,
                          child: Text('كل الفروع'),
                        ),
                        ...branchOptions.map(
                          (option) => DropdownMenuItem(
                            value: option.id,
                            child: Text(
                              option.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _branchFilter = value ?? _allFilterValue;
                        });
                        setSheetState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey(
                        'sheet-status-${_statusFilter?.name ?? _allFilterValue}',
                      ),
                      initialValue: _statusFilter?.name ?? _allFilterValue,
                      isExpanded: true,
                      decoration: _filterDecoration('حالة الفاتورة'),
                      items: [
                        const DropdownMenuItem(
                          value: _allFilterValue,
                          child: Text('كل الحالات'),
                        ),
                        ...InterBranchInvoiceStatus.values.map(
                          (status) => DropdownMenuItem(
                            value: status.name,
                            child: Text(
                              status.label,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _statusFilter =
                              value == null || value == _allFilterValue
                              ? null
                              : InterBranchInvoiceStatus.values.firstWhere(
                                  (status) => status.name == value,
                                );
                        });
                        setSheetState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _sheetDateButton(
                            label: 'من تاريخ',
                            value: _fromDate,
                            onTap: () => _pickDate(
                              isFrom: true,
                              onPicked: () => setSheetState(() {}),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _sheetDateButton(
                            label: 'إلى تاريخ',
                            value: _toDate,
                            onTap: () => _pickDate(
                              isFrom: false,
                              onPicked: () => setSheetState(() {}),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _hasActiveFilters
                                ? () {
                                    _clearFilters();
                                    setSheetState(() {});
                                  }
                                : null,
                            icon: const Icon(Icons.filter_alt_off_rounded),
                            label: const Text('مسح'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => Navigator.pop(sheetContext),
                            icon: const Icon(Icons.done_rounded),
                            label: const Text('تم'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _roleColor,
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
    );
  }

  InputDecoration _filterDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
      ),
    );
  }

  bool get _hasActiveFilters =>
      _branchFilter != _allFilterValue ||
      _statusFilter != null ||
      _fromDate != null ||
      _toDate != null;

  Future<void> _pickDate({required bool isFrom, VoidCallback? onPicked}) async {
    final now = DateTime.now();
    final current = isFrom ? _fromDate : _toDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 2, 12, 31),
    );
    if (picked == null || !mounted) return;

    final selectedDay = DateTime(picked.year, picked.month, picked.day);
    setState(() {
      if (isFrom) {
        _fromDate = selectedDay;
        if (_toDate != null && _toDate!.isBefore(selectedDay)) {
          _toDate = selectedDay;
        }
      } else {
        _toDate = selectedDay;
        if (_fromDate != null && _fromDate!.isAfter(selectedDay)) {
          _fromDate = selectedDay;
        }
      }
    });
    onPicked?.call();
  }

  void _clearFilters() {
    setState(() {
      _branchFilter = _allFilterValue;
      _statusFilter = null;
      _fromDate = null;
      _toDate = null;
    });
  }

  Widget _sheetDateButton({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.date_range_rounded),
      label: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          value == null ? label : '$label: ${_formatDate(value)}',
          overflow: TextOverflow.ellipsis,
        ),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.textPrimary,
        side: const BorderSide(color: Color(0xFFE0E0E0)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      ),
    );
  }

  Widget _buildInvoicesList(List<InterBranchInvoiceRead> invoices) {
    return Column(
      children: invoices.map((invoice) {
        final date = invoice.invoiceCreatedAt ?? invoice.requestDate;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: AppTheme.cardShadow(),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => InterBranchInvoiceDetailsScreen(
                      invoiceId: invoice.id,
                      role: widget.role,
                      branchId: widget.branchId,
                      branchName: widget.branchName,
                    ),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: invoice.status.color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.receipt_long_rounded,
                            color: invoice.status.color,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                invoice.invoiceNumber == '-'
                                    ? 'طلب بانتظار الفاتورة'
                                    : invoice.invoiceNumber,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _formatDate(date),
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _statusChip(invoice.status),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _miniInfo(
                            'من',
                            invoice.sendingBranchName,
                            Icons.call_made_rounded,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _miniInfo(
                            'إلى',
                            invoice.receivingBranchName,
                            Icons.call_received_rounded,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${invoice.items.length} منتج',
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                        if (_showsPrices)
                          Text(
                            invoice.totalPrice == null
                                ? 'بدون أسعار'
                                : _formatNumber(invoice.totalPrice!),
                            style: TextStyle(
                              color: invoice.totalPrice == null
                                  ? AppTheme.textHint
                                  : AppTheme.successColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _miniInfo(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: _roleColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$label: $value',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(InterBranchInvoiceStatus status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: status.color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 32),
      decoration: AppTheme.cardShadow(),
      child: Column(
        children: [
          Icon(icon, size: 52, color: AppTheme.textHint),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(color: AppTheme.textSecondary, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  List<InterBranchInvoiceRead> _invoiceList(
    QuerySnapshot<Map<String, dynamic>>? snapshot,
  ) {
    final invoices = (snapshot?.docs ?? [])
        .map((doc) => InterBranchInvoiceRead(id: doc.id, data: doc.data()))
        .toList();
    invoices.sort((a, b) {
      final aDate =
          a.invoiceCreatedAt ??
          a.requestDate ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bDate =
          b.invoiceCreatedAt ??
          b.requestDate ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    return invoices;
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '-';
    return _dateFormat.format(value);
  }

  String _formatNumber(double value) => _numberFormat.format(value);
}

Color _roleColorFor(UserRole role) {
  switch (role) {
    case UserRole.admin:
      return AppTheme.adminColor;
    case UserRole.accountant:
      return AppTheme.accountantColor;
    case UserRole.manager:
      return AppTheme.managerColor;
    case UserRole.collector:
      return AppTheme.collectorColor;
  }
}

List<Color> _roleGradientFor(UserRole role) {
  switch (role) {
    case UserRole.admin:
      return AppTheme.adminGradient;
    case UserRole.accountant:
      return AppTheme.accountantGradient;
    case UserRole.manager:
      return AppTheme.managerGradient;
    case UserRole.collector:
      return AppTheme.collectorGradient;
  }
}

String _roleLabelFor(UserRole role) {
  switch (role) {
    case UserRole.admin:
      return 'المدير العام';
    case UserRole.accountant:
      return 'المحاسب';
    case UserRole.manager:
      return 'مدير الفرع';
    case UserRole.collector:
      return 'المدير العام';
  }
}

IconData _roleIconFor(UserRole role) {
  switch (role) {
    case UserRole.admin:
      return Icons.admin_panel_settings_rounded;
    case UserRole.accountant:
      return Icons.calculate_rounded;
    case UserRole.manager:
      return Icons.business_center_rounded;
    case UserRole.collector:
      return Icons.admin_panel_settings_rounded;
  }
}
