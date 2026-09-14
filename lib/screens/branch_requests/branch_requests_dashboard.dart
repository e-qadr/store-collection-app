import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:store_collection_app/models/branch_request_model.dart';
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/services/branch_request_service.dart';
import 'package:store_collection_app/theme/app_theme.dart';
import 'package:store_collection_app/utils/logout_confirmation.dart';
import 'package:store_collection_app/widgets/dashboard_widgets.dart';
import 'package:store_collection_app/widgets/notification_bell.dart';

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
  final _dateFormat = DateFormat('yyyy/MM/dd HH:mm');

  bool get _isBranchManager =>
      widget.role == UserRole.manager &&
      (widget.branchId?.trim().isNotEmpty ?? false);
  bool get _isGeneralManager => widget.role == UserRole.collector;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        floatingActionButton: _isBranchManager
            ? FloatingActionButton.extended(
                key: const Key('branch-request-create-button'),
                onPressed: _showCreateSheet,
                backgroundColor: AppTheme.managerColor,
                icon: const Icon(Icons.add_rounded),
                label: const Text('طلب جديد'),
              )
            : null,
        body: CustomScrollView(
          slivers: [
            _appBar(),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 96),
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _service.watchRequests(
                    role: widget.role,
                    branchId: widget.branchId,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SizedBox(
                        height: 240,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snapshot.hasError) return _errorState();
                    final requests = _sorted(snapshot.data?.docs ?? const []);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _summary(requests),
                        const SizedBox(height: 24),
                        const SectionHeader(
                          title: 'قائمة الطلبات',
                          icon: Icons.assignment_rounded,
                          color: AppTheme.primaryOlive,
                        ),
                        const SizedBox(height: 12),
                        if (!_isGeneralManager && !_isBranchManager)
                          _emptyState(
                            icon: Icons.lock_outline_rounded,
                            title: 'هذه الصفحة مخصصة للمدير العام ومدير الفرع',
                            subtitle: 'لا تتوفر صلاحية لعرض طلبات الفروع.',
                          )
                        else if (requests.isEmpty)
                          _emptyState(
                            icon: Icons.assignment_outlined,
                            title: 'لا توجد طلبات فروع حتى الآن',
                            subtitle: _isBranchManager
                                ? 'استخدم زر طلب جديد لإرسال احتياجك للإدارة.'
                                : 'ستظهر هنا طلبات جميع الفروع.',
                          )
                        else
                          ...requests.map(_requestCard),
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

  SliverAppBar _appBar() => SliverAppBar(
    expandedHeight: 165,
    pinned: true,
    backgroundColor: _isGeneralManager
        ? AppTheme.collectorColor
        : AppTheme.managerColor,
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
            : AppTheme.managerGradient,
        title: _isGeneralManager ? 'جميع الفروع' : widget.branchName,
        subtitle: _isGeneralManager ? 'قائمة مهام المدير العام' : 'طلبات فرعي',
        icon: Icons.assignment_rounded,
      ),
    ),
  );

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

  Widget _summary(List<BranchRequestRead> requests) {
    final pending = requests
        .where((request) => request.status.isPending)
        .length;
    final inProgress = requests
        .where((request) => request.status == BranchRequestStatus.inProgress)
        .length;
    final completed = requests
        .where((request) => request.status == BranchRequestStatus.completed)
        .length;
    return Row(
      children: [
        Expanded(
          child: StatCard(
            label: 'معلقة',
            value: '$pending',
            icon: Icons.pending_actions_rounded,
            color: AppTheme.warningColor,
            bgColor: const Color(0xFFFFF3E0),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatCard(
            label: 'قيد التنفيذ',
            value: '$inProgress',
            icon: Icons.handyman_rounded,
            color: AppTheme.collectorColor,
            bgColor: const Color(0xFFE0F2F1),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatCard(
            label: 'مكتملة',
            value: '$completed',
            icon: Icons.check_circle_rounded,
            color: AppTheme.successColor,
            bgColor: const Color(0xFFE8F5E9),
          ),
        ),
      ],
    );
  }

  Widget _requestCard(BranchRequestRead request) => Card(
    key: Key('branch-request-${request.id}'),
    margin: const EdgeInsets.only(bottom: 12),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _showDetails(request),
      child: Padding(
        padding: const EdgeInsets.all(15),
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
                      fontSize: 16,
                    ),
                  ),
                ),
                _chip(request.status.label, request.status.color),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              request.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 11),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _chip(request.category.label, AppTheme.primaryOlive),
                _chip(request.priority.label, request.priority.color),
                if (_isGeneralManager)
                  _chip(request.branchName, AppTheme.collectorColor),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'أنشئ في ${_formatDate(request.createdAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );

  Widget _errorState() => _emptyState(
    icon: Icons.cloud_off_rounded,
    title: 'تعذر تحميل طلبات الفروع',
    subtitle: 'تحقق من الاتصال والصلاحيات ثم حاول مرة أخرى.',
  );

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) => Card(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Icon(icon, size: 42, color: AppTheme.textSecondary),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(subtitle, textAlign: TextAlign.center),
        ],
      ),
    ),
  );

  Future<void> _showCreateSheet() async {
    final title = TextEditingController();
    final description = TextEditingController();
    var category = BranchRequestCategory.general;
    var priority = BranchRequestPriority.normal;
    var saving = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
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
                const Text(
                  'طلب فرع جديد',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 14),
                Text('الفرع: ${widget.branchName}'),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('branch-request-title'),
                  controller: title,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'العنوان'),
                ),
                TextField(
                  key: const Key('branch-request-description'),
                  controller: description,
                  maxLines: 4,
                  maxLength: 2000,
                  decoration: const InputDecoration(labelText: 'الوصف'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<BranchRequestCategory>(
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'فئة الطلب'),
                  items: BranchRequestCategory.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.label),
                        ),
                      )
                      .toList(),
                  onChanged: saving
                      ? null
                      : (value) => setSheetState(() => category = value!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<BranchRequestPriority>(
                  initialValue: priority,
                  decoration: const InputDecoration(labelText: 'الأولوية'),
                  items: BranchRequestPriority.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.label),
                        ),
                      )
                      .toList(),
                  onChanged: saving
                      ? null
                      : (value) => setSheetState(() => priority = value!),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  key: const Key('branch-request-submit'),
                  onPressed: saving
                      ? null
                      : () async {
                          setSheetState(() => saving = true);
                          try {
                            await _service.createRequest(
                              branchId: widget.branchId!,
                              branchName: widget.branchName,
                              title: title.text,
                              description: description.text,
                              category: category,
                              priority: priority,
                            );
                            if (context.mounted) {
                              Navigator.pop(context);
                            }
                            if (mounted) {
                              _message('تم إرسال طلب الفرع للمدير العام.');
                            }
                          } catch (error) {
                            if (context.mounted) {
                              _message('تعذر إرسال الطلب: $error');
                            }
                            setSheetState(() => saving = false);
                          }
                        },
                  icon: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                  label: const Text('إرسال الطلب'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    title.dispose();
    description.dispose();
  }

  Future<void> _showDetails(BranchRequestRead request) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  request.title,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                _chip(request.status.label, request.status.color),
                const SizedBox(height: 18),
                _detailRow('الفرع', request.branchName),
                _detailRow('الفئة', request.category.label),
                _detailRow('الأولوية', request.priority.label),
                _detailRow('أنشئ بواسطة', request.createdByName),
                _detailRow('تاريخ الإنشاء', _formatDate(request.createdAt)),
                const SizedBox(height: 8),
                const Text(
                  'الوصف',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(request.description),
                if (request.completionNote.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'ملاحظة الإنجاز',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(request.completionNote),
                ],
                const SizedBox(height: 18),
                const Text(
                  'سجل الطلب',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...request.history.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '• ${entry['message'] ?? entry['action'] ?? ''}',
                    ),
                  ),
                ),
                if (_isGeneralManager &&
                    request.status == BranchRequestStatus.newRequest) ...[
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: () => _startRequest(context, request),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('بدء التنفيذ'),
                  ),
                ],
                if (_isGeneralManager &&
                    request.status == BranchRequestStatus.inProgress) ...[
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: () => _completeRequest(context, request),
                    icon: const Icon(Icons.task_alt_rounded),
                    label: const Text('إكمال الطلب'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Text('$label: ${value.isEmpty ? '-' : value}'),
  );

  Future<void> _startRequest(
    BuildContext sheetContext,
    BranchRequestRead request,
  ) async {
    try {
      await _service.startRequest(request.id);
      if (sheetContext.mounted) Navigator.pop(sheetContext);
      if (mounted) _message('تم نقل الطلب إلى قيد التنفيذ.');
    } catch (error) {
      if (mounted) _message('تعذر تحديث الطلب: $error');
    }
  }

  Future<void> _completeRequest(
    BuildContext sheetContext,
    BranchRequestRead request,
  ) async {
    final note = TextEditingController();
    final result = await showDialog<String>(
      context: sheetContext,
      builder: (context) => AlertDialog(
        title: const Text('إكمال طلب الفرع'),
        content: TextField(
          controller: note,
          maxLength: 1000,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'ملاحظة الإنجاز (اختيارية)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, note.text),
            child: const Text('إكمال'),
          ),
        ],
      ),
    );
    note.dispose();
    if (result == null) return;
    try {
      await _service.completeRequest(
        requestId: request.id,
        completionNote: result,
      );
      if (sheetContext.mounted) Navigator.pop(sheetContext);
      if (mounted) _message('تم إكمال الطلب وإشعار الفرع.');
    } catch (error) {
      if (mounted) _message('تعذر إكمال الطلب: $error');
    }
  }

  String _formatDate(DateTime? date) =>
      date == null ? 'قيد الحفظ' : _dateFormat.format(date);

  void _message(String value) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(value)));
}
