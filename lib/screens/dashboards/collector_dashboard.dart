import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/screens/inter_branch_invoices/inter_branch_invoices_dashboard.dart';
import 'package:store_collection_app/screens/transactions/new_transaction_screen.dart';
import 'package:store_collection_app/screens/transactions/branch_transactions_screen.dart';
import 'package:store_collection_app/screens/transactions/collector_edit_requests_screen.dart';
import 'package:store_collection_app/theme/app_theme.dart';
import 'package:store_collection_app/widgets/dashboard_widgets.dart';
import 'package:store_collection_app/widgets/notification_bell.dart';
import 'package:store_collection_app/utils/firestore_refresh.dart';
import 'package:store_collection_app/utils/logout_confirmation.dart';

class CollectorDashboard extends StatelessWidget {
  // تمرير بيانات الفرع الخاص بالمدير العام
  final String branchId;
  final String branchName;

  const CollectorDashboard({
    super.key,
    this.branchId = 'BRANCH_001', // قيمة افتراضية للتجربة
    this.branchName = 'الفرع الرئيسي',
  });

  @override
  Widget build(BuildContext context) {
    final collectorId = FirebaseAuth.instance.currentUser?.uid ?? '';

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
                      _buildCollectorStats(collectorId),
                      const SizedBox(height: 12),
                      ActionCard(
                        title: 'فواتير التحويل بين الفروع',
                        subtitle:
                            'قائمة عامة بالفواتير التي تنتظر تسعير المدير العام',
                        icon: Icons.swap_horiz_rounded,
                        color: AppTheme.collectorColor,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  InterBranchInvoicesDashboard(
                                    role: UserRole.collector,
                                    branchName: 'جميع الفروع',
                                  ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 28),

                      // ── Quick Actions ──────────────────────────────────
                      const SectionHeader(
                        title: 'الإجراءات السريعة',
                        icon: Icons.flash_on_rounded,
                        color: AppTheme.collectorColor,
                      ),
                      const SizedBox(height: 14),

                      // 1. زر إضافة سند جديد
                      ActionCard(
                        title: 'إضافة سند تحصيل جديد',
                        subtitle: 'إدخال بيانات مبلغ جديد ورفعه للاعتماد',
                        icon: Icons.add_circle_outline_rounded,
                        color: const Color(0xFF2E7D32),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => NewTransactionScreen(
                                branchId: branchId,
                                branchName: branchName,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),

                      // 2. زر السندات التي تتطلب تعديل
                      ActionCard(
                        title: 'سندات تتطلب تعديلاً',
                        subtitle: 'مراجعة وتصحيح السندات المعادة من الإدارة',
                        icon: Icons.edit_notifications_rounded,
                        color: const Color(0xFFE65100),
                        onTap: () {
                          // سننتقل إلى شاشة التعديل
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'سننتقل إلى شاشة السندات المعادة للتعديل...',
                              ),
                            ),
                          );

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => CollectorEditRequestsScreen(
                                branchId: branchId,
                                branchName: branchName,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),

                      // 3. زر سجل السندات
                      ActionCard(
                        title: 'سجل السندات الخاصة بي',
                        subtitle: 'متابعة حالة جميع السندات التي قمت برفعها',
                        icon: Icons.receipt_long_rounded,
                        color: AppTheme.collectorColor,
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
                      const SizedBox(height: 28),

                      // ── Recent Activity ────────────────────────────────
                      const SectionHeader(
                        title: 'آخر سنداتي',
                        icon: Icons.history_rounded,
                        color: AppTheme.collectorColor,
                      ),
                      const SizedBox(height: 14),
                      RecentTransactionsList(
                        branchId: branchId,
                        color: AppTheme.collectorColor,
                        collectorId: collectorId.isNotEmpty
                            ? collectorId
                            : null,
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
      backgroundColor: AppTheme.collectorColor,
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
          'لوحة المدير العام',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        background: RoleAppBarBackground(
          gradientColors: AppTheme.collectorGradient,
          title: 'مرحباً بك 👋',
          subtitle: branchName,
          icon: Icons.person_rounded,
        ),
      ),
    );
  }

  // ── Live Summary Stats Section ────────────────────────────────────────────
  Widget _buildCollectorStats(String collectorId) {
    final query = collectorId.isNotEmpty
        ? FirebaseFirestore.instance
              .collection('transactions')
              .where('branchId', isEqualTo: branchId)
              .where('collectorId', isEqualTo: collectorId)
              .snapshots()
        : FirebaseFirestore.instance
              .collection('transactions')
              .where('branchId', isEqualTo: branchId)
              .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: query,
      builder: (context, snapshot) {
        int total = 0, inProgress = 0, completed = 0;

        if (snapshot.hasData) {
          final docs = snapshot.data!.docs;
          total = docs.length;
          inProgress = docs
              .where(
                (d) =>
                    d['status'] == 'pending' ||
                    d['status'] == 'approvedByCollector' ||
                    d['status'] == 'approvedByManager',
              )
              .length;
          completed = docs
              .where((d) => d['status'] == 'approvedByAccountant')
              .length;
        }

        return Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'سنداتي',
                value: '$total',
                icon: Icons.receipt_long_rounded,
                color: const Color(0xFF00695C),
                bgColor: const Color(0xFFE0F2F1),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatCard(
                label: 'قيد المعالجة',
                value: '$inProgress',
                icon: Icons.pending_actions_rounded,
                color: const Color(0xFFE65100),
                bgColor: const Color(0xFFFFF3E0),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatCard(
                label: 'مكتملة',
                value: '$completed',
                icon: Icons.check_circle_rounded,
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
