import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:store_collection_app/models/branch_request_model.dart';
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/services/branch_request_service.dart';
import 'package:store_collection_app/theme/app_theme.dart';
import 'package:store_collection_app/utils/branch_scope.dart';

class BranchRequestFormScreen extends StatefulWidget {
  final UserRole role;
  final String? branchId;
  final String branchName;
  final BranchRequestService service;
  final BranchRequestRead? request;

  const BranchRequestFormScreen({
    super.key,
    required this.role,
    required this.branchName,
    required this.service,
    this.branchId,
    this.request,
  });

  @override
  State<BranchRequestFormScreen> createState() =>
      _BranchRequestFormScreenState();
}

class _BranchRequestFormScreenState extends State<BranchRequestFormScreen> {
  late final TextEditingController _title = TextEditingController(
    text: widget.request?.title ?? '',
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.request?.description ?? '',
  );
  late BranchRequestCategory _category =
      widget.request?.category ?? BranchRequestCategory.general;
  late BranchRequestPriority _priority =
      widget.request?.priority ?? BranchRequestPriority.normal;
  String? _selectedBranchId;
  String? _selectedBranchName;
  String _assignmentDestination = 'branch';
  bool _saving = false;

  bool get _isEdit => widget.request != null;
  bool get _isBranchManager => widget.role == UserRole.manager;
  bool get _isAssignment => !_isBranchManager;
  bool get _isAdministrativeAssignment =>
      _isAssignment && !_isEdit && _assignmentDestination == 'administration';

  String get _administrativeRecipientLabel =>
      widget.role == UserRole.collector ? 'المحاسب' : 'المدير العام';

  @override
  void initState() {
    super.initState();
    _selectedBranchId = widget.request?.branchId ?? widget.branchId;
    _selectedBranchName = widget.request?.branchName ?? widget.branchName;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = _isEdit
        ? 'تعديل الطلب'
        : _isAssignment
        ? 'إسناد مهمة'
        : 'طلب جديد للإدارة';
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(title: Text(title)),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(_isEdit ? Icons.save_rounded : Icons.send_rounded),
              label: Text(
                _isEdit
                    ? 'حفظ التعديلات'
                    : _isAssignment
                    ? 'إسناد المهمة'
                    : 'إرسال الطلب',
              ),
            ),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _introCard(),
              const SizedBox(height: 16),
              _targetSection(),
              const SizedBox(height: 16),
              _contentSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _introCard() {
    final title = _isAdministrativeAssignment
        ? 'مهمة إدارية مباشرة'
        : _isAssignment
        ? 'مهمة واضحة للفرع'
        : 'أرسل احتياج فرعك للإدارة';
    final subtitle = _isAdministrativeAssignment
        ? 'تصل إلى $_administrativeRecipientLabel ليبدأ تنفيذها أو يوضح سبب رفضها.'
        : _isAssignment
        ? 'يستلم مدير الفرع المهمة ثم يبدأ تنفيذها أو يوضح سبب رفضها.'
        : 'سيظهر طلبك للمدير العام، وتتابع حالته من نفس السجل.';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primaryOlive.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.add_task_rounded, color: AppTheme.primaryOlive),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _targetSection() {
    if (_isEdit || _isBranchManager) {
      final isAdministrativeTask =
          widget.request?.isAdministrativeTask ?? false;
      return _section(
        title: isAdministrativeTask
            ? 'الطرف المكلف'
            : _isAssignment
            ? 'الفرع المكلف'
            : 'الفرع مقدم الطلب',
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            isAdministrativeTask
                ? Icons.manage_accounts_rounded
                : Icons.storefront_rounded,
          ),
          title: Text(
            _selectedBranchName?.isNotEmpty == true
                ? _selectedBranchName!
                : 'الفرع غير محدد',
          ),
          subtitle: Text(
            isAdministrativeTask
                ? _administrativeRecipientLabel
                : _isAssignment
                ? 'المسؤول عن التنفيذ'
                : 'يُرسل الطلب إلى المدير العام',
          ),
        ),
      );
    }
    return Column(
      children: [
        _section(
          title: 'وجهة المهمة',
          child: DropdownButtonFormField<String>(
            initialValue: _assignmentDestination,
            decoration: const InputDecoration(
              labelText: 'وجّه المهمة إلى',
              prefixIcon: Icon(Icons.near_me_rounded),
            ),
            items: const [
              DropdownMenuItem(value: 'branch', child: Text('فرع')),
              DropdownMenuItem(
                value: 'administration',
                child: Text('طرف إداري'),
              ),
            ],
            onChanged: _saving
                ? null
                : (value) => setState(() => _assignmentDestination = value!),
          ),
        ),
        const SizedBox(height: 16),
        if (_isAdministrativeAssignment)
          _section(
            title: 'الطرف المكلف',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.manage_accounts_rounded),
              title: Text(_administrativeRecipientLabel),
              subtitle: const Text('مهمة داخلية بين المدير العام والمحاسب'),
            ),
          )
        else
          _branchTargetPicker(),
      ],
    );
  }

  Widget _branchTargetPicker() {
    return _section(
      title: 'اختر الفرع المكلف',
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('branches').snapshots(),
        builder: (context, snapshot) {
          final branches =
              (snapshot.data?.docs ?? const [])
                  .where((doc) => isActiveOperationalBranch(doc.data()))
                  .toList()
                ..sort(
                  (a, b) => (a.data()['name'] ?? '').toString().compareTo(
                    (b.data()['name'] ?? '').toString(),
                  ),
                );
          return DropdownButtonFormField<String>(
            initialValue: _selectedBranchId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'الفرع *',
              prefixIcon: Icon(Icons.storefront_rounded),
            ),
            hint: const Text('اختر الفرع'),
            items: branches
                .map(
                  (branch) => DropdownMenuItem(
                    value: branch.id,
                    child: Text(
                      branch.data()['name']?.toString() ?? 'فرع غير مسمى',
                    ),
                  ),
                )
                .toList(),
            onChanged: _saving
                ? null
                : (value) {
                    final selected = branches
                        .where((branch) => branch.id == value)
                        .firstOrNull;
                    setState(() {
                      _selectedBranchId = value;
                      _selectedBranchName =
                          selected?.data()['name']?.toString() ?? '';
                    });
                  },
          );
        },
      ),
    );
  }

  Widget _contentSection() => _section(
    title: 'تفاصيل الطلب',
    child: Column(
      children: [
        TextField(
          controller: _title,
          maxLength: 120,
          decoration: const InputDecoration(
            labelText: 'عنوان واضح للطلب *',
            prefixIcon: Icon(Icons.title_rounded),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _description,
          maxLength: 2000,
          minLines: 4,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: 'التفاصيل المطلوبة *',
            alignLabelWithHint: true,
            prefixIcon: Icon(Icons.notes_rounded),
          ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<BranchRequestCategory>(
          initialValue: _category,
          decoration: const InputDecoration(labelText: 'الفئة'),
          items: BranchRequestCategory.values
              .map(
                (item) =>
                    DropdownMenuItem(value: item, child: Text(item.label)),
              )
              .toList(),
          onChanged: _saving
              ? null
              : (value) => setState(() => _category = value!),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<BranchRequestPriority>(
          initialValue: _priority,
          decoration: const InputDecoration(labelText: 'الأولوية'),
          items: BranchRequestPriority.values
              .map(
                (item) =>
                    DropdownMenuItem(value: item, child: Text(item.label)),
              )
              .toList(),
          onChanged: _saving
              ? null
              : (value) => setState(() => _priority = value!),
        ),
      ],
    ),
  );

  Widget _section({required String title, required Widget child}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: AppTheme.cardShadow(radius: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );

  Future<void> _save() async {
    if (!_isAdministrativeAssignment &&
        ((_selectedBranchId ?? '').isEmpty ||
            (_selectedBranchName ?? '').isEmpty)) {
      _message('اختر الفرع أولاً.');
      return;
    }
    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await widget.service.editRequest(
          requestId: widget.request!.id,
          title: _title.text,
          description: _description.text,
          category: _category,
          priority: _priority,
        );
      } else if (_isAdministrativeAssignment) {
        await widget.service.createAdministrativeTask(
          title: _title.text,
          description: _description.text,
          category: _category,
          priority: _priority,
        );
      } else if (_isAssignment) {
        await widget.service.createTaskForBranch(
          branchId: _selectedBranchId!,
          branchName: _selectedBranchName!,
          title: _title.text,
          description: _description.text,
          category: _category,
          priority: _priority,
        );
      } else {
        await widget.service.createRequest(
          branchId: _selectedBranchId!,
          branchName: _selectedBranchName!,
          title: _title.text,
          description: _description.text,
          category: _category,
          priority: _priority,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      _message(error.toString().replaceFirst('Bad state: ', ''));
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String value) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(value)));
}
