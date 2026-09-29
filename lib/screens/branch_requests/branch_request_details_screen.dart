import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:store_collection_app/models/branch_request_model.dart';
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/screens/branch_requests/branch_request_form_screen.dart';
import 'package:store_collection_app/services/branch_request_service.dart';
import 'package:store_collection_app/theme/app_theme.dart';

class BranchRequestDetailsScreen extends StatelessWidget {
  final UserRole role;
  final String? branchId;
  final BranchRequestRead request;
  final BranchRequestService service;

  const BranchRequestDetailsScreen({
    super.key,
    required this.role,
    required this.request,
    required this.service,
    this.branchId,
  });

  bool get _isExecutor =>
      (request.executorRole == UserRole.collector.name &&
          role == UserRole.collector) ||
      (request.executorRole == UserRole.accountant.name &&
          role == UserRole.accountant) ||
      (request.executorRole == UserRole.manager.name &&
          role == UserRole.manager &&
          branchId == request.branchId);

  bool get _mayEdit =>
      request.status == BranchRequestStatus.newRequest &&
      request.createdByRole == role.name;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      appBar: AppBar(title: const Text('تفاصيل الطلب')),
      bottomNavigationBar: _actions(context),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 118),
        children: [
          _header(),
          const SizedBox(height: 14),
          _summary(),
          const SizedBox(height: 14),
          _description(),
          if (request.rejectionReason.isNotEmpty) ...[
            const SizedBox(height: 14),
            _noteCard(
              title: 'سبب الرفض',
              value: request.rejectionReason,
              color: AppTheme.errorColor,
              icon: Icons.cancel_outlined,
            ),
          ],
          if (request.completionNote.isNotEmpty) ...[
            const SizedBox(height: 14),
            _noteCard(
              title: 'ملاحظة الإنجاز',
              value: request.completionNote,
              color: AppTheme.successColor,
              icon: Icons.task_alt_rounded,
            ),
          ],
          const SizedBox(height: 18),
          _history(),
        ],
      ),
    ),
  );

  Widget _header() => Container(
    padding: const EdgeInsets.all(18),
    decoration: AppTheme.cardShadow(radius: 20),
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
                  fontSize: 20,
                ),
              ),
            ),
            _statusPill(request.status),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          request.direction.label,
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _tag(
              request.isAdministrativeTask
                  ? Icons.manage_accounts_rounded
                  : Icons.storefront_rounded,
              request.isAdministrativeTask ? 'الإدارة' : request.branchName,
            ),
            _tag(Icons.category_rounded, request.category.label),
            _tag(
              Icons.flag_rounded,
              request.priority.label,
              request.priority.color,
            ),
          ],
        ),
      ],
    ),
  );

  Widget _summary() => Container(
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
    decoration: AppTheme.cardShadow(radius: 18),
    child: Row(
      children: [
        _fact('أنشئ بواسطة', request.createdByName),
        _line(),
        _fact('تاريخ الإنشاء', _date(request.createdAt)),
        _line(),
        _fact('المسؤول الآن', _executorLabel),
      ],
    ),
  );

  String get _executorLabel => switch (request.executorRole) {
    'manager' => 'مدير الفرع',
    'accountant' => 'المحاسب',
    _ => 'المدير العام',
  };

  Widget _fact(String label, String value) => Expanded(
    child: Column(
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 5),
        Text(
          value.isEmpty ? '-' : value,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        ),
      ],
    ),
  );

  Widget _line() =>
      Container(width: 1, height: 38, color: AppTheme.dividerColor);

  Widget _description() => Container(
    padding: const EdgeInsets.all(18),
    decoration: AppTheme.cardShadow(radius: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'التفاصيل',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 9),
        Text(request.description, style: const TextStyle(height: 1.6)),
      ],
    ),
  );

  Widget _noteCard({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
  }) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 3),
              Text(value),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _history() => Container(
    padding: const EdgeInsets.all(18),
    decoration: AppTheme.cardShadow(radius: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'سجل الطلب',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 12),
        ...request.history.reversed.map(
          (entry) => Padding(
            padding: const EdgeInsets.only(bottom: 11),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.circle, size: 8, color: AppTheme.primaryOlive),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    '${entry['message'] ?? entry['action'] ?? ''}${_historyNote(entry)}',
                    style: const TextStyle(height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  String _historyNote(Map<String, dynamic> entry) {
    final note = entry['note']?.toString().trim() ?? '';
    return note.isEmpty ? '' : '\n$note';
  }

  Widget? _actions(BuildContext context) {
    if (!_isExecutor && !_mayEdit) return null;
    final buttons = <Widget>[];
    if (_mayEdit) {
      buttons.add(
        OutlinedButton.icon(
          onPressed: () => _edit(context),
          icon: const Icon(Icons.edit_rounded),
          label: const Text('تعديل'),
        ),
      );
    }
    if (_isExecutor && request.status == BranchRequestStatus.newRequest) {
      buttons.add(
        FilledButton.icon(
          onPressed: () => _start(context),
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('بدء التنفيذ'),
        ),
      );
    }
    if (_isExecutor && request.status == BranchRequestStatus.inProgress) {
      buttons.add(
        FilledButton.icon(
          onPressed: () => _complete(context),
          icon: const Icon(Icons.task_alt_rounded),
          label: const Text('إكمال الطلب'),
        ),
      );
    }
    if (_isExecutor && request.status.isPending) {
      buttons.add(
        TextButton.icon(
          onPressed: () => _reject(context),
          icon: const Icon(Icons.close_rounded),
          label: const Text('رفض الطلب'),
          style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
        ),
      );
    }
    if (buttons.isEmpty) return null;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppTheme.dividerColor)),
        ),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 8,
          children: buttons,
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => BranchRequestFormScreen(
          role: role,
          branchId: branchId,
          branchName: request.branchName,
          service: service,
          request: request,
        ),
      ),
    );
    if (result == true && context.mounted) Navigator.pop(context, true);
  }

  Future<void> _start(BuildContext context) async {
    try {
      await service.startRequest(request.id);
      if (context.mounted) Navigator.pop(context, true);
    } catch (error) {
      if (context.mounted) _message(context, error);
    }
  }

  Future<void> _complete(BuildContext context) async {
    final note = await _noteDialog(
      context,
      title: 'إكمال الطلب',
      label: 'ملاحظة الإنجاز (اختيارية)',
    );
    if (note == null) return;
    try {
      await service.completeRequest(
        requestId: request.id,
        completionNote: note,
      );
      if (context.mounted) Navigator.pop(context, true);
    } catch (error) {
      if (context.mounted) _message(context, error);
    }
  }

  Future<void> _reject(BuildContext context) async {
    final reason = await _noteDialog(
      context,
      title: 'رفض الطلب',
      label: 'سبب الرفض *',
      required: true,
    );
    if (reason == null) return;
    try {
      await service.rejectRequest(requestId: request.id, reason: reason);
      if (context.mounted) Navigator.pop(context, true);
    } catch (error) {
      if (context.mounted) _message(context, error);
    }
  }

  Future<String?> _noteDialog(
    BuildContext context, {
    required String title,
    required String label,
    bool required = false,
  }) async {
    final controller = TextEditingController();
    String? error;
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            maxLines: 3,
            maxLength: 1000,
            decoration: InputDecoration(labelText: label, errorText: error),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                if (required && controller.text.trim().isEmpty) {
                  setDialogState(() => error = 'هذا الحقل مطلوب.');
                  return;
                }
                Navigator.pop(context, controller.text);
              },
              child: Text(title),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return value;
  }

  Widget _statusPill(BranchRequestStatus status) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: status.color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      status.label,
      style: TextStyle(
        color: status.color,
        fontWeight: FontWeight.bold,
        fontSize: 12,
      ),
    ),
  );

  Widget _tag(IconData icon, String label, [Color? color]) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: (color ?? AppTheme.primaryOlive).withValues(alpha: .1),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color ?? AppTheme.primaryOlive),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: color ?? AppTheme.primaryOlive),
        ),
      ],
    ),
  );

  String _date(DateTime? value) =>
      value == null ? '-' : DateFormat('yyyy/MM/dd').format(value);

  void _message(BuildContext context, Object error) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
}
