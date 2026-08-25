import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:store_collection_app/models/consumable_request_model.dart';
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/screens/consumables/consumable_request_details_screen.dart';
import 'package:store_collection_app/screens/consumables/new_consumable_request_screen.dart';
import 'package:store_collection_app/services/consumable_request_service.dart';
import 'package:store_collection_app/theme/app_theme.dart';
import 'package:store_collection_app/utils/logout_confirmation.dart';
import 'package:store_collection_app/widgets/dashboard_widgets.dart';
import 'package:store_collection_app/widgets/notification_bell.dart';
import 'package:store_collection_app/widgets/grouped_branch_overview.dart';

class ConsumableRequestsDashboard extends StatefulWidget {
  final UserRole role;
  final String? branchId;
  final String branchName;

  const ConsumableRequestsDashboard({
    super.key,
    required this.role,
    required this.branchName,
    this.branchId,
  });

  @override
  State<ConsumableRequestsDashboard> createState() =>
      _ConsumableRequestsDashboardState();
}

class _ConsumableRequestsDashboardState
    extends State<ConsumableRequestsDashboard> {
  final _service = ConsumableRequestService();
  final _dateFormat = DateFormat('yyyy/MM/dd');
  final _numberFormat = NumberFormat('#,##0.##');

  bool get _hasBranch =>
      widget.branchId != null && widget.branchId!.trim().isNotEmpty;

  bool get _canCreate =>
      widget.role == UserRole.manager && widget.branchId?.isNotEmpty == true;

  Color get _roleColor => _roleColorFor(widget.role);

  List<Color> get _roleGradient => _roleGradientFor(widget.role);

  String get _roleLabel => _roleLabelFor(widget.role);

  IconData get _roleIcon => _roleIconFor(widget.role);

  @override
  Widget build(BuildContext context) {
    if (usesGroupedBranchOverview(widget.role, widget.branchId)) {
      return GroupedBranchOverview(
        role: widget.role,
        kind: GroupedBranchOverviewKind.consumption,
        onViewAll: (context, branchId, branchName) => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ConsumableRequestsDashboard(
              role: widget.role,
              branchId: branchId,
              branchName: branchName,
            ),
          ),
        ),
      );
    }
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        floatingActionButton: _canCreate
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
                  stream: _service.watchRequests(
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
                        title: 'تعذر تحميل طلبات المستهلكات',
                        subtitle: 'تحقق من الاتصال ثم حاول مرة أخرى.',
                      );
                    }

                    final requests = _requestList(snapshot.data);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildStats(requests),
                        const SizedBox(height: 24),
                        const SectionHeader(
                          title: 'نظام المستهلكات',
                          icon: Icons.inventory_2_rounded,
                          color: AppTheme.warningColor,
                        ),
                        const SizedBox(height: 14),
                        if (_canCreate) ...[
                          _controlCard(
                            title: 'طلب استهلاك جديد',
                            subtitle:
                                'إنشاء طلب مستهلكات للعرض وإرساله للمدير العام.',
                            countLabel: 'جديد',
                            icon: Icons.add_circle_outline_rounded,
                            color: AppTheme.managerColor,
                            onTap: _openNewRequest,
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (!_hasBranch)
                          _emptyState(
                            icon: Icons.storefront_outlined,
                            title: 'لا يوجد فرع محدد',
                            subtitle:
                                'اختر فرعاً قبل فتح نظام طلبات المستهلكات.',
                          )
                        else if (requests.isEmpty)
                          _emptyState(
                            icon: Icons.inventory_2_outlined,
                            title: 'لا توجد طلبات حتى الآن',
                            subtitle: _emptySubtitle,
                          )
                        else
                          _requestsList(requests),
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
          'طلب استهلاك منتج للعرض',
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

  String get _emptySubtitle {
    switch (widget.role) {
      case UserRole.manager:
        return 'ابدأ بإنشاء طلب جديد من زر الطلب.';
      case UserRole.collector:
        return 'ستظهر هنا الطلبات التي تحتاج قبول أو تعديل كمية من المدير العام.';
      case UserRole.accountant:
        return 'ستظهر هنا الطلبات التي تحتاج إدخالاً واعتماداً محاسبياً.';
      case UserRole.admin:
        return 'النظام مخصص للمدير والمحصّل والمحاسب.';
    }
  }

  Widget _buildStats(List<ConsumableRequestRead> requests) {
    final pendingCollector = requests
        .where(
          (request) =>
              request.status == ConsumableRequestStatus.pendingCollectorReview,
        )
        .length;
    final pendingAccounting = requests
        .where(
          (request) =>
              request.status ==
              ConsumableRequestStatus.pendingAccountingApproval,
        )
        .length;
    final approved = requests
        .where(
          (request) =>
              request.status == ConsumableRequestStatus.approvedByAccountant,
        )
        .length;

    return Row(
      children: [
        Expanded(
          child: StatCard(
            label: 'الإجمالي',
            value: '${requests.length}',
            icon: Icons.inventory_2_rounded,
            color: AppTheme.warningColor,
            bgColor: const Color(0xFFFFF3E0),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatCard(
            label: widget.role == UserRole.accountant
                ? 'بانتظار محاسب'
                : 'بانتظار مدير عام',
            value: widget.role == UserRole.accountant
                ? '$pendingAccounting'
                : '$pendingCollector',
            icon: widget.role == UserRole.accountant
                ? Icons.calculate_rounded
                : Icons.person_search_rounded,
            color: widget.role == UserRole.accountant
                ? AppTheme.accountantColor
                : AppTheme.collectorColor,
            bgColor: widget.role == UserRole.accountant
                ? const Color(0xFFEDE7F6)
                : const Color(0xFFE0F2F1),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatCard(
            label: 'معتمد',
            value: '$approved',
            icon: Icons.verified_rounded,
            color: AppTheme.successColor,
            bgColor: const Color(0xFFE8F5E9),
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
          onTap: onTap,
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

  Widget _requestsList(List<ConsumableRequestRead> requests) {
    return Column(
      children: requests.map((request) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: AppTheme.cardShadow(),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ConsumableRequestDetailsScreen(
                    requestId: request.id,
                    role: widget.role,
                    branchId: widget.branchId,
                    branchName: widget.branchName,
                  ),
                ),
              ),
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
                            color: request.status.color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.inventory_2_rounded,
                            color: request.status.color,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                request.requestNumber,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _formatDate(request.createdAt),
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _statusChip(request.status),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _miniInfo(
                            '${request.items.length} منتج',
                            Icons.category_rounded,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _miniInfo(
                            'الكمية: ${_formatNumber(request.totalCollectorQuantity)}',
                            Icons.numbers_rounded,
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

  Widget _miniInfo(String value, IconData icon) {
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
              value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(ConsumableRequestStatus status) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 130),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
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

  List<ConsumableRequestRead> _requestList(
    QuerySnapshot<Map<String, dynamic>>? snapshot,
  ) {
    final requests = (snapshot?.docs ?? [])
        .map((doc) => ConsumableRequestRead(id: doc.id, data: doc.data()))
        .toList();
    requests.sort((a, b) {
      final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    return requests;
  }

  void _openNewRequest() {
    final branchId = widget.branchId;
    if (branchId == null || branchId.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NewConsumableRequestScreen(
          branchId: branchId,
          branchName: widget.branchName,
        ),
      ),
    );
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
