import 'package:flutter/material.dart';
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/models/purchase_invoice_model.dart';
import 'package:store_collection_app/screens/purchase_invoices/new_purchase_invoice_screen.dart';
import 'package:store_collection_app/screens/purchase_invoices/product_review_queue_screen.dart';
import 'package:store_collection_app/screens/purchase_invoices/product_branch_accounting_screen.dart';
import 'package:store_collection_app/screens/purchase_invoices/purchase_invoice_details_screen.dart';
import 'package:store_collection_app/screens/purchase_invoices/purchase_invoice_history_screen.dart';
import 'package:store_collection_app/services/purchase_invoice_service.dart';
import 'package:store_collection_app/theme/app_theme.dart';
import 'package:store_collection_app/widgets/notification_bell.dart';

class PurchaseInvoicesDashboard extends StatefulWidget {
  final UserRole role;
  final String? branchId;
  final String branchName;
  final Stream<List<PurchaseInvoiceRead>>? invoiceStream;
  final Stream<List<PurchaseInvoiceRead>>? historyStream;
  final bool showNotificationBell;

  const PurchaseInvoicesDashboard({
    super.key,
    required this.role,
    required this.branchName,
    this.branchId,
    this.invoiceStream,
    this.historyStream,
    this.showNotificationBell = true,
  });

  @override
  State<PurchaseInvoicesDashboard> createState() =>
      _PurchaseInvoicesDashboardState();
}

class _PurchaseInvoicesDashboardState extends State<PurchaseInvoicesDashboard> {
  late final PurchaseInvoiceService _service = PurchaseInvoiceService();
  final GlobalKey _tasksKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        body: StreamBuilder<List<PurchaseInvoiceRead>>(
          stream:
              widget.invoiceStream ??
              _service.watchDashboard(
                role: widget.role,
                branchId: widget.branchId,
              ),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _dashboardError();
            }
            final actionInvoices = snapshot.data ?? const [];
            return StreamBuilder<List<PurchaseInvoiceRead>>(
              stream:
                  widget.historyStream ??
                  (widget.invoiceStream != null
                      ? Stream.value(actionInvoices)
                      : _service.watchHistory(
                          role: widget.role,
                          branchId: widget.branchId,
                        )),
              builder: (context, historySnapshot) {
                if (historySnapshot.hasError) return _dashboardError();
                return _dashboardBody(
                  actionInvoices,
                  historySnapshot.data ?? actionInvoices,
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _dashboardBody(
    List<PurchaseInvoiceRead> actionInvoices,
    List<PurchaseInvoiceRead> historyInvoices,
  ) {
    final completedCount = historyInvoices
        .where(
          (invoice) =>
              invoice.status == PurchaseInvoiceStatus.postedToAccounting,
        )
        .length;
    final amendmentCount = historyInvoices
        .where((invoice) => invoice.hasPendingAmendment)
        .length;
    final recent = historyInvoices.take(3).toList(growable: false);
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _heroHeader(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _statsRow(
                total: historyInvoices.length,
                actionCount: actionInvoices.length,
                completedCount: completedCount,
              ),
              if (amendmentCount > 0) ...[
                const SizedBox(height: 12),
                _amendmentNotice(amendmentCount),
              ],
              const SizedBox(height: 24),
              _sectionTitle('الإجراءات السريعة', Icons.bolt_rounded),
              const SizedBox(height: 10),
              ..._quickActions(actionInvoices.length),
              const SizedBox(height: 24),
              _sectionTitle(
                _queueTitle,
                Icons.assignment_rounded,
                trailing: actionInvoices.isEmpty
                    ? 'لا توجد مهام'
                    : '${actionInvoices.length} مهام',
              ),
              const SizedBox(height: 8),
              Container(
                key: _tasksKey,
                child: actionInvoices.isEmpty
                    ? _inlineEmpty(
                        icon: Icons.task_alt_rounded,
                        title: 'لا توجد مهام تحتاج إجراءك',
                        subtitle: _emptyActionText,
                      )
                    : Column(
                        children: actionInvoices
                            .map(_invoiceRow)
                            .toList(growable: false),
                      ),
              ),
              const SizedBox(height: 24),
              _sectionTitle(
                'آخر فواتير الفرع',
                Icons.history_rounded,
                trailing: 'عرض السجل',
                onTap: _openHistory,
              ),
              const SizedBox(height: 8),
              if (recent.isEmpty)
                _inlineEmpty(
                  icon: Icons.receipt_long_outlined,
                  title: 'لا توجد فواتير مسجلة بعد',
                  subtitle: 'ستظهر أحدث فواتير هذا الفرع هنا.',
                )
              else
                ...recent.map(_recentInvoiceRow),
            ],
          ),
        ),
      ],
    );
  }

  Widget _heroHeader() {
    final roleColor = switch (widget.role) {
      UserRole.collector => AppTheme.collectorColor,
      UserRole.accountant => AppTheme.accountantColor,
      UserRole.manager => AppTheme.managerColor,
      UserRole.admin => AppTheme.adminColor,
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [roleColor, roleColor.withValues(alpha: 0.78)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'رجوع',
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                if (widget.showNotificationBell) const NotificationBell(),
                IconButton(
                  key: const Key('purchase-history'),
                  tooltip: 'سجل فواتير المشتريات',
                  onPressed: _openHistory,
                  icon: const Icon(Icons.history_rounded, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.shopping_cart_checkout_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'مرحباً بك',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.82),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.branchName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 19,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Align(
              alignment: Alignment.centerRight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'فواتير المشتريات',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _roleDashboardTitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statsRow({
    required int total,
    required int actionCount,
    required int completedCount,
  }) => Row(
    children: [
      Expanded(
        child: _statCard(
          icon: Icons.receipt_long_outlined,
          value: total,
          label: 'فواتير الفرع',
          color: AppTheme.primaryOlive,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _statCard(
          icon: Icons.pending_actions_rounded,
          value: actionCount,
          label: 'تحتاج إجراءك',
          color: AppTheme.warningColor,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _statCard(
          icon: Icons.verified_rounded,
          value: completedCount,
          label: 'مكتملة',
          color: AppTheme.successColor,
        ),
      ),
    ],
  );

  Widget _statCard({
    required IconData icon,
    required int value,
    required String label,
    required Color color,
  }) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 8),
          Text(
            '$value',
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textHint, fontSize: 10),
          ),
        ],
      ),
    ),
  );

  Widget _amendmentNotice(int count) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppTheme.warningColor.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        const Icon(Icons.edit_note_rounded, color: AppTheme.warningColor),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            '$count فواتير لديها طلب تعديل بانتظار الموافقات.',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );

  Widget _sectionTitle(
    String title,
    IconData icon, {
    String? trailing,
    VoidCallback? onTap,
  }) => Row(
    children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.oliveSurface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: AppTheme.primaryOlive),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ),
      if (trailing != null) TextButton(onPressed: onTap, child: Text(trailing)),
    ],
  );

  List<Widget> _quickActions(int actionCount) {
    final actions = <Widget>[];
    if (widget.role == UserRole.collector) {
      actions.add(
        _quickAction(
          key: const Key('new-purchase-invoice'),
          icon: Icons.add_shopping_cart_rounded,
          color: AppTheme.collectorColor,
          title: 'إضافة فاتورة مشتريات جديدة',
          subtitle: 'اختر المورد والفرع وأضف المواد المطلوبة',
          onTap: _createInvoice,
        ),
      );
      actions.add(
        _quickAction(
          icon: Icons.price_check_rounded,
          color: AppTheme.warningColor,
          title: 'اعتماد الأسعار',
          subtitle: _actionSubtitle(
            actionCount,
            'راجع الأسعار واعتمد الفواتير الجاهزة',
          ),
          onTap: _scrollToTasks,
        ),
      );
    }
    if (widget.role == UserRole.manager) {
      actions.add(
        _quickAction(
          icon: Icons.inventory_rounded,
          color: AppTheme.managerColor,
          title: 'تأكيد استلام المواد',
          subtitle: _actionSubtitle(
            actionCount,
            'راجع الكميات وسجّل الفروقات إن وجدت',
          ),
          onTap: _scrollToTasks,
        ),
      );
    }
    if (widget.role == UserRole.accountant) {
      actions.add(
        _quickAction(
          icon: Icons.account_balance_rounded,
          color: AppTheme.accountantColor,
          title: 'إدخال المرجع والترحيل',
          subtitle: _actionSubtitle(
            actionCount,
            'أكمل المرجع المحاسبي للفواتير الجاهزة',
          ),
          onTap: _scrollToTasks,
        ),
      );
    }
    if (widget.role == UserRole.collector ||
        widget.role == UserRole.accountant) {
      actions.add(
        _quickAction(
          key: const Key('purchase-branch-accounting'),
          icon: Icons.account_tree_rounded,
          color: widget.role == UserRole.accountant
              ? AppTheme.accountantColor
              : AppTheme.oliveGreen,
          title: widget.role == UserRole.accountant
              ? 'ربط مواد الفرع محاسبيًا'
              : 'متابعة ربط المواد بالفروع',
          subtitle: widget.role == UserRole.accountant
              ? 'أدخل مرجع كل مادة في سجل فرعك'
              : 'راقب حالة ربط مادة الكتالوج في فروع العلامة',
          onTap: _openBranchAccounting,
        ),
      );
      actions.add(
        _quickAction(
          key: const Key('purchase-review-queue'),
          icon: Icons.rule_folder_rounded,
          color: AppTheme.oliveGreen,
          title: 'مراجعة المواد غير المطابقة',
          subtitle: 'ربط مادة موجودة أو إنشاء مادة جديدة في الدليل',
          onTap: _openReviewQueue,
        ),
      );
    }
    actions.add(
      _quickAction(
        icon: Icons.history_rounded,
        color: AppTheme.primaryOlive,
        title: 'سجل فواتير الفرع',
        subtitle: 'بحث وفلترة ومتابعة كل الفواتير السابقة',
        onTap: _openHistory,
      ),
    );
    return actions;
  }

  Widget _quickAction({
    Key? key,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) => Card(
    key: key,
    margin: const EdgeInsets.only(bottom: 9),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppTheme.textHint,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_left_rounded, color: AppTheme.textHint),
          ],
        ),
      ),
    ),
  );

  Widget _invoiceRow(PurchaseInvoiceRead invoice) => Card(
    key: Key('purchase-${invoice.id}'),
    margin: const EdgeInsets.only(bottom: 8),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => _openInvoice(invoice),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 42,
              decoration: BoxDecoration(
                color: invoice.status.color,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    invoice.purchaseNumber,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${invoice.status.label} • ${invoice.itemCount} مواد',
                    style: TextStyle(color: invoice.status.color, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_left_rounded, color: AppTheme.textHint),
          ],
        ),
      ),
    ),
  );

  Widget _recentInvoiceRow(PurchaseInvoiceRead invoice) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      onTap: () => _openInvoice(invoice),
      leading: Icon(Icons.receipt_long_outlined, color: invoice.status.color),
      title: Text(invoice.purchaseNumber),
      subtitle: Text('${invoice.status.label} • ${invoice.itemCount} مواد'),
      trailing: const Icon(Icons.chevron_left_rounded),
    ),
  );

  Widget _inlineEmpty({
    required IconData icon,
    required String title,
    required String subtitle,
  }) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(icon, size: 40, color: AppTheme.oliveGreen),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textHint),
          ),
        ],
      ),
    ),
  );

  Widget _dashboardError() => const _PurchaseEmpty(
    icon: Icons.error_outline_rounded,
    title: 'تعذر تحميل فواتير المشتريات',
    subtitle: 'تحقق من الاتصال ثم حاول مجددًا.',
  );

  String get _roleDashboardTitle => switch (widget.role) {
    UserRole.collector => 'لوحة المدير العام',
    UserRole.manager => 'لوحة مدير الفرع',
    UserRole.accountant => 'لوحة المحاسب',
    UserRole.admin => 'لوحة المشتريات',
  };

  String get _queueTitle => switch (widget.role) {
    UserRole.collector => 'فواتير الشراء الجديدة والقديمة',
    UserRole.manager => 'فواتير بانتظار تأكيد الاستلام',
    UserRole.accountant => 'فواتير بانتظار الترحيل المحاسبي',
    UserRole.admin => 'فواتير المشتريات',
  };

  String get _emptyActionText => switch (widget.role) {
    UserRole.collector => 'ستظهر هنا الفواتير الجاهزة لمراجعة الأسعار.',
    UserRole.manager => 'ستظهر هنا فواتير فرعك الجاهزة لتأكيد الاستلام.',
    UserRole.accountant => 'ستظهر هنا الفواتير الجاهزة لإدخال المرجع والترحيل.',
    UserRole.admin => 'لا توجد إجراءات متاحة لهذا الدور.',
  };

  String _actionSubtitle(int count, String base) =>
      count == 0 ? 'لا توجد مهام معلقة الآن' : '$base — لديك $count مهام';

  void _scrollToTasks() {
    final context = _tasksKey.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 350),
      );
    }
  }

  void _openReviewQueue() => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ProductReviewQueueScreen(
        role: widget.role,
        branchId: widget.branchId,
      ),
    ),
  );

  void _openBranchAccounting() => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ProductBranchAccountingScreen(
        role: widget.role,
        branchId: widget.branchId ?? '',
        branchName: widget.branchName,
      ),
    ),
  );

  void _openHistory() => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => PurchaseInvoiceHistoryScreen(
        role: widget.role,
        branchId: widget.branchId,
        branchName: widget.branchName,
      ),
    ),
  );

  void _openInvoice(PurchaseInvoiceRead invoice) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => PurchaseInvoiceDetailsScreen(
        invoiceId: invoice.id,
        role: widget.role,
        branchId: widget.branchId,
      ),
    ),
  );

  Future<void> _createInvoice() async {
    final invoiceId = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const NewPurchaseInvoiceScreen()),
    );
    if (!mounted || invoiceId == null || invoiceId.isEmpty) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PurchaseInvoiceDetailsScreen(
          invoiceId: invoiceId,
          role: widget.role,
          branchId: widget.branchId,
        ),
      ),
    );
  }
}

class _PurchaseEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _PurchaseEmpty({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 54, color: AppTheme.textHint),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(subtitle, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
