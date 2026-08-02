import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/screens/inter_branch_invoices/inter_branch_invoices_dashboard.dart';
import 'package:store_collection_app/screens/products/product_catalog_management_screen.dart';
import 'package:store_collection_app/screens/transactions/branch_transactions_screen.dart';
import 'package:store_collection_app/services/pdf_service.dart';
import 'package:store_collection_app/theme/app_theme.dart';
import 'package:store_collection_app/utils/transaction_records.dart';
import 'package:store_collection_app/utils/firestore_refresh.dart';
import 'package:store_collection_app/utils/logout_confirmation.dart';
import 'package:store_collection_app/widgets/dashboard_widgets.dart';
import 'package:store_collection_app/widgets/notification_bell.dart';

class AccountantDashboard extends StatelessWidget {
  final String branchId;
  final String branchName;

  const AccountantDashboard({
    super.key,
    required this.branchId,
    required this.branchName,
  });

  // دالة لإظهار نافذة اختيار التواريخ ثم استخراج التقرير
  Future<void> _generateReportDialog(BuildContext context) async {
    DateTime startDate = DateTime.now().subtract(const Duration(days: 30));
    DateTime endDate = DateTime.now();
    bool isGenerating = false;
    String pdfAction = 'save';

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.accountantColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.picture_as_pdf_rounded,
                      color: AppTheme.accountantColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('استخراج تقرير السندات')),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('حدد الفترة الزمنية لتاريخ إدخال السندات:'),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(
                            Icons.calendar_today_rounded,
                            size: 15,
                          ),
                          label: Text(
                            'من: ${startDate.year}/${startDate.month}/${startDate.day}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: startDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now(),
                            );
                            if (picked != null) {
                              setDialogState(() => startDate = picked);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(
                            Icons.calendar_today_rounded,
                            size: 15,
                          ),
                          label: Text(
                            'إلى: ${endDate.year}/${endDate.month}/${endDate.day}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: endDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now(),
                            );
                            if (picked != null) {
                              setDialogState(() => endDate = picked);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: pdfAction,
                    decoration: const InputDecoration(
                      labelText: 'إجراء ملف PDF',
                      prefixIcon: Icon(Icons.picture_as_pdf_rounded),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'save',
                        child: Text('حفظ PDF على الجهاز'),
                      ),
                      DropdownMenuItem(
                        value: 'print',
                        child: Text('معاينة وطباعة'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => pdfAction = value);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isGenerating ? null : () => Navigator.pop(context),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton.icon(
                  icon: isGenerating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.download_rounded, size: 18),
                  label: const Text('استخراج PDF'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accountantColor,
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                  onPressed: isGenerating
                      ? null
                      : () async {
                          setDialogState(() => isGenerating = true);
                          try {
                            // جلب السندات لهذه الفترة من فايربيس
                            final querySnapshot = await FirebaseFirestore
                                .instance
                                .collection('transactions')
                                .where('branchId', isEqualTo: branchId)
                                .get();
                            final transactions =
                                filterAndSortTransactionRecords(
                                  records: querySnapshot.docs,
                                  dataOf: (doc) => doc.data(),
                                  filters: TransactionRecordFilters(
                                    createdFrom: startDate,
                                    createdTo: endDate,
                                  ),
                                );

                            if (transactions.isEmpty) {
                              setDialogState(() => isGenerating = false);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'لا توجد سندات في هذه الفترة',
                                    ),
                                  ),
                                );
                              }
                              return;
                            }

                            // إرسال البيانات لدالة الطباعة
                            String? path;
                            if (pdfAction == 'save') {
                              path = await PdfService.saveTransactionsReport(
                                transactions: transactions,
                                branchName: branchName,
                                startDate: startDate,
                                endDate: endDate,
                              );
                            } else {
                              await PdfService.printTransactionsReport(
                                transactions: transactions,
                                branchName: branchName,
                                startDate: startDate,
                                endDate: endDate,
                              );
                            }

                            if (context.mounted) {
                              Navigator.pop(context);
                              if (pdfAction == 'save') {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'تم حفظ تقرير PDF${path == null ? '' : ': $path'}',
                                    ),
                                  ),
                                );
                              }
                            }
                          } catch (e) {
                            setDialogState(() => isGenerating = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('حدث خطأ: $e')),
                              );
                            }
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        body: RefreshIndicator(
          onRefresh: () => refreshFirestoreQueries([
            FirebaseFirestore.instance
                .collection('transactions')
                .where('branchId', isEqualTo: branchId),
          ]),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              _buildSliverAppBar(context),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 48),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Summary Stats ──────────────────────────────────
                      _buildAccountantStats(),
                      const SizedBox(height: 12),
                      ActionCard(
                        title: 'فواتير الطلبات بين الفروع',
                        subtitle:
                            'عرض كل الفواتير وترحيلها محاسبياً واعتماد طلبات التعديل أو الإلغاء',
                        icon: Icons.account_balance_wallet_rounded,
                        color: AppTheme.accountantColor,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  InterBranchInvoicesDashboard(
                                    role: UserRole.accountant,
                                    branchName: branchName,
                                    branchId: branchId,
                                  ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      ActionCard(
                        title: 'دليل المواد والمنتجات',
                        subtitle:
                            'إدارة كتالوج العلامات والمجموعات وأرشفة المنتجات وسجلها',
                        icon: Icons.inventory_2_rounded,
                        color: AppTheme.accountantColor,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                const ProductCatalogManagementScreen(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),

                      // ── Quick Actions ──────────────────────────────────
                      const SectionHeader(
                        title: 'الإجراءات السريعة',
                        icon: Icons.flash_on_rounded,
                        color: AppTheme.accountantColor,
                      ),
                      const SizedBox(height: 14),
                      ActionCard(
                        title: 'سجل السندات والاعتماد',
                        subtitle:
                            'مراجعة السندات، واعتمادها نهائياً أو طلب تعديلها',
                        icon: Icons.fact_check_rounded,
                        color: const Color(0xFF00695C),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => BranchTransactionsScreen(
                                branchId: branchId,
                                branchName: branchName,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      ActionCard(
                        title: 'استخراج تقارير PDF',
                        subtitle: 'تحديد فترة زمنية وتصدير جدول بالسندات',
                        icon: Icons.picture_as_pdf_rounded,
                        color: const Color(0xFFC62828),
                        onTap: () => _generateReportDialog(context),
                      ),
                      const SizedBox(height: 28),

                      // ── Recent Activity ────────────────────────────────
                      const SectionHeader(
                        title: 'آخر المعاملات',
                        icon: Icons.history_rounded,
                        color: AppTheme.accountantColor,
                      ),
                      const SizedBox(height: 14),
                      RecentTransactionsList(
                        branchId: branchId,
                        color: AppTheme.accountantColor,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Sliver App Bar with gradient ──────────────────────────────────────────
  SliverAppBar _buildSliverAppBar(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 160,
      floating: false,
      pinned: true,
      backgroundColor: AppTheme.accountantColor,
      automaticallyImplyLeading: Navigator.of(context).canPop(),
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
          'لوحة المحاسب',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        background: RoleAppBarBackground(
          gradientColors: AppTheme.accountantGradient,
          title: branchName,
          subtitle: 'المراجعة المالية',
          icon: Icons.calculate_rounded,
        ),
      ),
    );
  }

  // ── Live Summary Stats Section ────────────────────────────────────────────
  Widget _buildAccountantStats() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('transactions')
          .where('branchId', isEqualTo: branchId)
          .snapshots(),
      builder: (context, snapshot) {
        int total = 0, awaitingApproval = 0, fullyApproved = 0;

        if (snapshot.hasData) {
          final docs = snapshot.data!.docs;
          total = docs.length;
          awaitingApproval = docs
              .where((d) => d['status'] == 'approvedByManager')
              .length;
          fullyApproved = docs
              .where((d) => d['status'] == 'approvedByAccountant')
              .length;
        }

        return Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'إجمالي السندات',
                value: '$total',
                icon: Icons.receipt_long_rounded,
                color: AppTheme.accountantColor,
                bgColor: const Color(0xFFEDE7F6),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatCard(
                label: 'بانتظار مراجعتي',
                value: '$awaitingApproval',
                icon: Icons.pending_actions_rounded,
                color: const Color(0xFFE65100),
                bgColor: const Color(0xFFFFF3E0),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatCard(
                label: 'مكتملة نهائياً',
                value: '$fullyApproved',
                icon: Icons.verified_rounded,
                color: const Color(0xFF2E7D32),
                bgColor: const Color(0xFFE8F5E9),
              ),
            ),
          ],
        );
      },
    );
  }
}
