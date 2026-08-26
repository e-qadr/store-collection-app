import 'package:flutter/material.dart';
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/models/purchase_invoice_model.dart';
import 'package:store_collection_app/screens/purchase_invoices/new_purchase_invoice_screen.dart';
import 'package:store_collection_app/screens/purchase_invoices/product_review_queue_screen.dart';
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
  final bool showNotificationBell;

  const PurchaseInvoicesDashboard({
    super.key,
    required this.role,
    required this.branchName,
    this.branchId,
    this.invoiceStream,
    this.showNotificationBell = true,
  });

  @override
  State<PurchaseInvoicesDashboard> createState() =>
      _PurchaseInvoicesDashboardState();
}

class _PurchaseInvoicesDashboardState extends State<PurchaseInvoicesDashboard> {
  late final PurchaseInvoiceService _service = PurchaseInvoiceService();

  @override
  Widget build(BuildContext context) {
    final canCreate = widget.role == UserRole.collector;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(
          title: const Text('فواتير المشتريات'),
          actions: [
            IconButton(
              key: const Key('purchase-history'),
              tooltip: 'سجل فواتير المشتريات',
              icon: const Icon(Icons.history_rounded),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PurchaseInvoiceHistoryScreen(
                    role: widget.role,
                    branchId: widget.branchId,
                    branchName: widget.branchName,
                  ),
                ),
              ),
            ),
            if (widget.showNotificationBell) const NotificationBell(),
          ],
        ),
        floatingActionButton: canCreate
            ? FloatingActionButton.extended(
                key: const Key('new-purchase-invoice'),
                onPressed: _createInvoice,
                icon: const Icon(Icons.add_rounded),
                label: const Text('فاتورة مشتريات جديدة'),
              )
            : null,
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
              return const _PurchaseEmpty(
                icon: Icons.error_outline_rounded,
                title: 'تعذر تحميل فواتير المشتريات',
                subtitle: 'تحقق من الاتصال ثم حاول مجددًا.',
              );
            }
            final invoices = snapshot.data ?? const [];
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 96),
              children: [
                if (widget.role == UserRole.collector ||
                    widget.role == UserRole.accountant) ...[
                  Card(
                    child: ListTile(
                      key: const Key('purchase-review-queue'),
                      leading: const Icon(Icons.rule_folder_rounded),
                      title: const Text('مراجعة المواد غير المطابقة'),
                      subtitle: const Text(
                        'ربط المواد أو إنشاؤها ومتابعة المزامنة المحاسبية',
                      ),
                      trailing: const Icon(Icons.chevron_left_rounded),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ProductReviewQueueScreen(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  _queueTitle(widget.role),
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (invoices.isEmpty)
                  const _PurchaseEmpty(
                    icon: Icons.receipt_long_outlined,
                    title: 'لا توجد فواتير في هذه القائمة',
                    subtitle: 'ستظهر هنا الفواتير التي تحتاج إجراء دورك.',
                  )
                else
                  ...invoices.map(
                    (invoice) => Card(
                      child: ListTile(
                        key: Key('purchase-${invoice.id}'),
                        leading: CircleAvatar(
                          backgroundColor: invoice.status.color.withValues(
                            alpha: 0.12,
                          ),
                          child: Icon(
                            Icons.shopping_cart_checkout_rounded,
                            color: invoice.status.color,
                          ),
                        ),
                        title: Text(invoice.purchaseNumber),
                        subtitle: Text(
                          '${invoice.receivingBranchName}\n${invoice.status.label}',
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_left_rounded),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PurchaseInvoiceDetailsScreen(
                              invoiceId: invoice.id,
                              role: widget.role,
                              branchId: widget.branchId,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _queueTitle(UserRole role) => switch (role) {
    UserRole.manager => 'فواتير فرع ${widget.branchName}',
    UserRole.collector => 'فواتير الشراء الجديدة والقديمة',
    UserRole.accountant => 'بانتظار الترحيل المحاسبي',
    UserRole.admin => 'فواتير المشتريات',
  };

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
