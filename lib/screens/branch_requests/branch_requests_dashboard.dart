import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:store_collection_app/models/branch_request_model.dart';
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/screens/branch_requests/branch_request_details_screen.dart';
import 'package:store_collection_app/screens/branch_requests/branch_request_form_screen.dart';
import 'package:store_collection_app/services/branch_request_service.dart';
import 'package:store_collection_app/theme/app_theme.dart';
import 'package:store_collection_app/utils/branch_scope.dart';
import 'package:store_collection_app/utils/logout_confirmation.dart';
import 'package:store_collection_app/widgets/dashboard_widgets.dart';
import 'package:store_collection_app/widgets/notification_bell.dart';

enum _BoardStage { newRequests, inProgress, closed }

class BranchRequestsDashboard extends StatefulWidget {
  final UserRole role;
  final String? branchId;
  final String branchName;
  final BranchRequestService? service;

  const BranchRequestsDashboard({
    super.key,
    required this.role,
    required this.branchName,
    this.branchId,
    this.service,
  });

  @override
  State<BranchRequestsDashboard> createState() =>
      _BranchRequestsDashboardState();
}

class _BranchRequestsDashboardState extends State<BranchRequestsDashboard> {
  late final BranchRequestService _service =
      widget.service ?? BranchRequestService();
  final _dateFormat = DateFormat('yyyy/MM/dd');
  _BoardStage _stage = _BoardStage.newRequests;
  String? _selectedBranchId;
  String? _selectedBranchName;

  bool get _isBranchManager =>
      widget.role == UserRole.manager &&
      (widget.branchId?.trim().isNotEmpty ?? false);
  bool get _isGeneralManager => widget.role == UserRole.collector;
  bool get _isAccountant => widget.role == UserRole.accountant;
  bool get _canCreate => _isBranchManager || _isGeneralManager || _isAccountant;
  bool get _showsBranchOverview =>
      (_isGeneralManager || _isAccountant) && _selectedBranchId == null;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      floatingActionButton: _canCreate
          ? FloatingActionButton.extended(
              key: const Key('branch-request-create-button'),
              onPressed: _openForm,
              backgroundColor: _color,
              icon: Icon(
                _isBranchManager ? Icons.add_rounded : Icons.add_task_rounded,
              ),
              label: Text(_isBranchManager ? 'طلب جديد' : 'إسناد مهمة'),
            )
          : null,
      body: CustomScrollView(
        slivers: [
          _appBar(),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 100),
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _service.watchRequests(
                  role: widget.role,
                  branchId: _isGeneralManager
                      ? _selectedBranchId
                      : widget.branchId,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox(
                      height: 260,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError) {
                    return _emptyState(
                      icon: Icons.cloud_off_rounded,
                      title: 'تعذر تحميل الطلبات',
                      subtitle: 'تحقق من الاتصال والصلاحيات ثم حاول مرة أخرى.',
                    );
                  }
                  var requests = _sorted(snapshot.data?.docs ?? const []);
                  if (_isAccountant && _selectedBranchId != null) {
                    requests = requests
                        .where(
                          (request) => request.branchId == _selectedBranchId,
                        )
                        .toList();
                  }
                  if (!_canCreate) {
                    return _emptyState(
                      icon: Icons.lock_outline_rounded,
                      title: 'لا تتوفر صلاحية لطلبات الفروع',
                      subtitle:
                          'هذه الصفحة مخصصة لمدير الفرع والمدير العام والمحاسب.',
                    );
                  }
                  if (_showsBranchOverview) return _branchOverview(requests);
                  return _requestBoard(requests);
                },
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Color get _color => _isGeneralManager
      ? AppTheme.collectorColor
      : _isAccountant
      ? AppTheme.accountantColor
      : AppTheme.managerColor;

  SliverAppBar _appBar() => SliverAppBar(
    expandedHeight: 160,
    pinned: true,
    backgroundColor: _color,
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
        'طلبات الفروع',
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      background: RoleAppBarBackground(
        gradientColors: _isGeneralManager
            ? AppTheme.collectorGradient
            : _isAccountant
            ? AppTheme.accountantGradient
            : AppTheme.managerGradient,
        title:
            _selectedBranchName ??
            (_isGeneralManager
                ? 'مهام جميع الفروع'
                : _isAccountant
                ? 'مهامي وطلبات الفروع'
                : widget.branchName),
        subtitle: _subtitle,
        icon: Icons.assignment_rounded,
      ),
    ),
  );

  String get _subtitle {
    if (_selectedBranchName != null) return 'طلبات $_selectedBranchName';
    if (_isGeneralManager) return 'تابع الطلبات ووجّه المهام';
    if (_isAccountant) return 'تابع مهام الفروع والمهام الإدارية';
    return 'طلبات فرعك ومهامه الواردة';
  }

  Widget _branchOverview(List<BranchRequestRead> requests) =>
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('branches').snapshots(),
        builder: (context, snapshot) {
          final branches =
              (snapshot.data?.docs ?? const [])
                  .where((branch) => isActiveOperationalBranch(branch.data()))
                  .toList()
                ..sort(
                  (a, b) => (a.data()['name'] ?? '').toString().compareTo(
                    (b.data()['name'] ?? '').toString(),
                  ),
                );
          final administrativeTasks = requests
              .where((item) => item.isAdministrativeTask)
              .take(3)
              .toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _overviewIntro(),
              const SizedBox(height: 18),
              _administrativePreview(administrativeTasks),
              const SizedBox(height: 18),
              const SectionHeader(
                title: 'الفروع وآخر الطلبات',
                icon: Icons.account_tree_rounded,
                color: AppTheme.primaryOlive,
              ),
              const SizedBox(height: 10),
              if (branches.isEmpty)
                _emptyState(
                  icon: Icons.storefront_outlined,
                  title: 'لا توجد فروع تشغيلية',
                  subtitle: 'ستظهر هنا الفروع التي يمكن إرسال مهام إليها.',
                )
              else
                ...branches.map((branch) {
                  final branchRequests = requests
                      .where((item) => item.branchId == branch.id)
                      .take(3)
                      .toList();
                  return _branchPreview(
                    branch.id,
                    branch.data()['name']?.toString() ?? 'فرع غير مسمى',
                    branchRequests,
                  );
                }),
            ],
          );
        },
      );

  Widget _overviewIntro() => Container(
    padding: const EdgeInsets.all(16),
    decoration: AppTheme.cardShadow(radius: 18),
    child: Row(
      children: [
        Icon(Icons.view_list_rounded, color: _color, size: 28),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            _isGeneralManager
                ? 'راجع مهام الفروع أو وجّه مهمة إلى المحاسب عند الحاجة.'
                : 'تابع مهام الفروع أو المهام الموجهة إليك من المدير العام.',
            style: const TextStyle(height: 1.45),
          ),
        ),
      ],
    ),
  );

  Widget _administrativePreview(List<BranchRequestRead> requests) =>
      _branchPreview(
        BranchRequestFields.administrationScopeId,
        'المهام الإدارية',
        requests,
        administrative: true,
      );

  Widget _branchPreview(
    String id,
    String name,
    List<BranchRequestRead> requests, {
    bool administrative = false,
  }) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(15),
    decoration: AppTheme.cardShadow(radius: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                administrative
                    ? Icons.manage_accounts_rounded
                    : Icons.storefront_rounded,
                color: _color,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            Text(
              'آخر 3',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 11),
        if (requests.isEmpty)
          const Text(
            'لا توجد طلبات ظاهرة لهذا الفرع.',
            style: TextStyle(color: AppTheme.textSecondary),
          )
        else
          ...requests.map(
            (request) => InkWell(
              onTap: () => _openDetails(request),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      _statusIcon(request.status),
                      size: 17,
                      color: request.status.color,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        request.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      request.status.label,
                      style: TextStyle(
                        color: request.status.color,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const Divider(height: 22),
        TextButton.icon(
          onPressed: () => setState(() {
            _selectedBranchId = id;
            _selectedBranchName = name;
            _stage = _BoardStage.newRequests;
          }),
          icon: const Icon(Icons.arrow_back_rounded),
          label: Text(
            administrative ? 'عرض المهام الإدارية' : 'عرض طلبات الفرع',
          ),
        ),
      ],
    ),
  );

  Widget _requestBoard(List<BranchRequestRead> requests) {
    final shown = requests.where(_matchesStage).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_selectedBranchId != null) ...[
          TextButton.icon(
            onPressed: () => setState(() {
              _selectedBranchId = null;
              _selectedBranchName = null;
            }),
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text('العودة إلى الفروع'),
          ),
          const SizedBox(height: 4),
        ],
        _summary(requests),
        const SizedBox(height: 18),
        _stageSwitcher(requests),
        const SizedBox(height: 18),
        SectionHeader(
          title: _stageTitle,
          icon: _stage == _BoardStage.closed
              ? Icons.inventory_2_rounded
              : Icons.checklist_rounded,
          color: _color,
        ),
        const SizedBox(height: 10),
        if (shown.isEmpty)
          _emptyState(
            icon: _stage == _BoardStage.closed
                ? Icons.inventory_2_outlined
                : Icons.task_alt_rounded,
            title: _emptyTitle,
            subtitle: _stage == _BoardStage.closed
                ? 'الطلبات المكتملة أو المرفوضة تبقى محفوظة هنا للرجوع إليها.'
                : 'ستظهر هنا الطلبات التي تقع في هذه المرحلة.',
          )
        else
          ...shown.map(_checklistItem),
      ],
    );
  }

  Widget _summary(List<BranchRequestRead> requests) {
    final newCount = requests
        .where((request) => request.status == BranchRequestStatus.newRequest)
        .length;
    final progressCount = requests
        .where((request) => request.status == BranchRequestStatus.inProgress)
        .length;
    final closedCount = requests
        .where((request) => !request.status.isPending)
        .length;
    return Row(
      children: [
        _stat(
          _BoardStage.newRequests,
          'معلقة',
          newCount,
          Icons.pending_actions_rounded,
          AppTheme.pendingColor,
        ),
        const SizedBox(width: 9),
        _stat(
          _BoardStage.inProgress,
          'يعمل عليها',
          progressCount,
          Icons.handyman_rounded,
          AppTheme.warningColor,
        ),
        const SizedBox(width: 9),
        _stat(
          _BoardStage.closed,
          'مكتملة',
          closedCount,
          Icons.task_alt_rounded,
          AppTheme.successColor,
        ),
      ],
    );
  }

  Widget _stat(
    _BoardStage stage,
    String label,
    int value,
    IconData icon,
    Color color,
  ) => Expanded(
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => setState(() => _stage = stage),
      child: StatCard(
        label: label,
        value: '$value',
        icon: icon,
        color: color,
        bgColor: color.withValues(alpha: .1),
      ),
    ),
  );

  Widget _stageSwitcher(List<BranchRequestRead> requests) => Container(
    padding: const EdgeInsets.all(5),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppTheme.dividerColor),
    ),
    child: Row(
      children: [
        _stageTab(
          _BoardStage.newRequests,
          'معلقة',
          requests
              .where((item) => item.status == BranchRequestStatus.newRequest)
              .length,
        ),
        _stageTab(
          _BoardStage.inProgress,
          'يعمل عليها',
          requests
              .where((item) => item.status == BranchRequestStatus.inProgress)
              .length,
        ),
        _stageTab(
          _BoardStage.closed,
          'مكتملة',
          requests.where((item) => !item.status.isPending).length,
        ),
      ],
    ),
  );

  Widget _stageTab(_BoardStage stage, String label, int count) {
    final selected = _stage == stage;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _stage = stage),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? _color : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$label ($count)',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: selected ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _checklistItem(BranchRequestRead request) => Container(
    key: Key('branch-request-${request.id}'),
    margin: const EdgeInsets.only(bottom: 10),
    decoration: AppTheme.cardShadow(radius: 17),
    child: InkWell(
      borderRadius: BorderRadius.circular(17),
      onTap: () => _openDetails(request),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: request.status.color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _statusIcon(request.status),
                color: request.status.color,
                size: 20,
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
                          request.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      _priority(request.priority),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    request.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        request.isAdministrativeTask
                            ? Icons.manage_accounts_rounded
                            : Icons.storefront_rounded,
                        size: 15,
                        color: _color,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          request.isAdministrativeTask
                              ? 'مهمة إدارية'
                              : request.branchName,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Text(
                        _dateFormat.format(request.createdAt ?? DateTime.now()),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _priority(BranchRequestPriority priority) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: priority.color.withValues(alpha: .11),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      priority.label,
      style: TextStyle(
        color: priority.color,
        fontSize: 11,
        fontWeight: FontWeight.bold,
      ),
    ),
  );

  bool _matchesStage(BranchRequestRead request) => switch (_stage) {
    _BoardStage.newRequests => request.status == BranchRequestStatus.newRequest,
    _BoardStage.inProgress => request.status == BranchRequestStatus.inProgress,
    _BoardStage.closed => !request.status.isPending,
  };

  String get _stageTitle => switch (_stage) {
    _BoardStage.newRequests => 'الطلبات المعلقة',
    _BoardStage.inProgress => 'طلبات يعمل عليها الآن',
    _BoardStage.closed => 'الأرشيف: المكتملة والمرفوضة',
  };

  String get _emptyTitle => switch (_stage) {
    _BoardStage.newRequests => 'لا توجد طلبات معلقة',
    _BoardStage.inProgress => 'لا توجد طلبات قيد التنفيذ',
    _BoardStage.closed => 'لا توجد طلبات مغلقة',
  };

  List<BranchRequestRead> _sorted(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final requests = docs
        .map((doc) => BranchRequestRead(id: doc.id, data: doc.data()))
        .toList();
    requests.sort((a, b) {
      final pending = (a.status.isPending ? 0 : 1).compareTo(
        b.status.isPending ? 0 : 1,
      );
      if (pending != 0) return pending;
      final priority = _priorityOrder(
        a.priority,
      ).compareTo(_priorityOrder(b.priority));
      if (priority != 0) return priority;
      return (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0));
    });
    return requests;
  }

  int _priorityOrder(BranchRequestPriority priority) => switch (priority) {
    BranchRequestPriority.urgent => 0,
    BranchRequestPriority.important => 1,
    BranchRequestPriority.normal => 2,
  };

  IconData _statusIcon(BranchRequestStatus status) => switch (status) {
    BranchRequestStatus.newRequest => Icons.radio_button_unchecked_rounded,
    BranchRequestStatus.inProgress => Icons.play_circle_outline_rounded,
    BranchRequestStatus.completed => Icons.check_circle_rounded,
    BranchRequestStatus.rejected => Icons.cancel_rounded,
  };

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) => Container(
    padding: const EdgeInsets.all(30),
    decoration: AppTheme.cardShadow(radius: 18),
    child: Column(
      children: [
        Icon(icon, size: 42, color: AppTheme.textSecondary),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
      ],
    ),
  );

  Future<void> _openForm() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => BranchRequestFormScreen(
          role: widget.role,
          branchId: widget.branchId,
          branchName: widget.branchName,
          service: _service,
        ),
      ),
    );
    if (saved == true && mounted) {
      _message('تم حفظ الطلب وإشعار الطرف المسؤول.');
    }
  }

  Future<void> _openDetails(BranchRequestRead request) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => BranchRequestDetailsScreen(
          role: widget.role,
          branchId: widget.branchId,
          request: request,
          service: _service,
        ),
      ),
    );
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}
