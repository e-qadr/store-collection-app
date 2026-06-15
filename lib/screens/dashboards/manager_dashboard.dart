import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:store_collection_app/screens/transactions/branch_transactions_screen.dart';
import 'package:store_collection_app/screens/transactions/manager_approvals_screen.dart';
import 'package:store_collection_app/theme/app_theme.dart';
import 'package:store_collection_app/widgets/dashboard_widgets.dart';
import 'package:store_collection_app/widgets/notification_bell.dart';
import 'package:store_collection_app/utils/firestore_refresh.dart';

class ManagerDashboard extends StatelessWidget {
  final String branchId;
  final String branchName;

  const ManagerDashboard({
    super.key,
    this.branchId = 'BRANCH_001', // يمكنك تمرير هذه القيم ديناميكياً لاحقاً
    this.branchName = 'الفرع الرئيسي',
  });

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
                      _buildManagerStats(),
                      const SizedBox(height: 28),

                      // ── Quick Actions ──────────────────────────────────
                      const SectionHeader(
                        title: 'الإجراءات السريعة',
                        icon: Icons.flash_on_rounded,
                        color: AppTheme.managerColor,
                      ),
                      const SizedBox(height: 14),
                      ActionCard(
                        title: 'طلبات الاعتماد والتعديل',
                        subtitle:
                            'مراجعة السندات الجديدة والموافقة على التعديلات',
                        icon: Icons.check_circle_outline_rounded,
                        color: AppTheme.managerColor,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ManagerApprovalsScreen(
                              branchId: branchId,
                              branchName: branchName,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ActionCard(
                        title: 'سجل السندات والعمليات',
                        subtitle: 'عرض وتصفية كافة السندات، وطلب تعديلها',
                        icon: Icons.receipt_long_rounded,
                        color: const Color(0xFF0277BD),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => BranchTransactionsScreen(
                              branchId: branchId,
                              branchName: branchName,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),

                      // ── Recent Activity ────────────────────────────────
                      const SectionHeader(
                        title: 'آخر المعاملات',
                        icon: Icons.history_rounded,
                        color: AppTheme.managerColor,
                      ),
                      const SizedBox(height: 14),
                      RecentTransactionsList(
                        branchId: branchId,
                        color: AppTheme.managerColor,
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
      backgroundColor: AppTheme.managerColor,
      automaticallyImplyLeading: false,
      actions: [
        const NotificationBell(),
        IconButton(
          icon: const Icon(Icons.logout_rounded),
          tooltip: 'تسجيل الخروج',
          onPressed: () async {
            await FirebaseAuth.instance.signOut();
            if (context.mounted) {
              // هذا السطر السحري يقوم بإغلاق جميع الشاشات المتراكمة والعودة للشاشة الرئيسية (AuthGate)
              Navigator.of(context).popUntil((route) => route.isFirst);
            }
          },
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: true,
        title: const Text(
          'لوحة المدير',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        background: RoleAppBarBackground(
          gradientColors: AppTheme.managerGradient,
          title: branchName,
          subtitle: 'مدير الفرع',
          icon: Icons.business_center_rounded,
        ),
      ),
    );
  }

  // ── Live Summary Stats Section ────────────────────────────────────────────
  Widget _buildManagerStats() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('transactions')
          .where('branchId', isEqualTo: branchId)
          .snapshots(),
      builder: (context, snapshot) {
        int total = 0, pending = 0, editReqs = 0;

        if (snapshot.hasData) {
          final docs = snapshot.data!.docs;
          total = docs.length;
          pending = docs.where((d) => d['status'] == 'pending').length;
          editReqs = docs
              .where(
                (d) =>
                    d['status'] == 'pendingApprovalOfEdit' ||
                    d['status'] == 'editRequestedByCollector',
              )
              .length;
        }

        return Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'إجمالي السندات',
                value: '$total',
                icon: Icons.receipt_long_rounded,
                color: const Color(0xFF1565C0),
                bgColor: const Color(0xFFE3F2FD),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatCard(
                label: 'بانتظار الموافقة',
                value: '$pending',
                icon: Icons.pending_actions_rounded,
                color: const Color(0xFFE65100),
                bgColor: const Color(0xFFFFF3E0),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatCard(
                label: 'طلبات تعديل',
                value: '$editReqs',
                icon: Icons.edit_note_rounded,
                color: const Color(0xFFC62828),
                bgColor: const Color(0xFFFFEBEE),
              ),
            ),
          ],
        );
      },
    );
  }
}
