import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:store_collection_app/models/consumable_request_model.dart';
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/services/consumable_request_service.dart';
import 'package:store_collection_app/theme/app_theme.dart';

class ConsumableRequestDetailsScreen extends StatefulWidget {
  final String requestId;
  final UserRole role;
  final String? branchId;
  final String branchName;

  const ConsumableRequestDetailsScreen({
    super.key,
    required this.requestId,
    required this.role,
    required this.branchName,
    this.branchId,
  });

  @override
  State<ConsumableRequestDetailsScreen> createState() =>
      _ConsumableRequestDetailsScreenState();
}

class _ConsumableRequestDetailsScreenState
    extends State<ConsumableRequestDetailsScreen> {
  final _service = ConsumableRequestService();
  final _numberFormat = NumberFormat('#,##0.##');
  final _dateFormat = DateFormat('yyyy/MM/dd HH:mm');

  Color get _roleColor {
    switch (widget.role) {
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

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(
          title: const Text('تفاصيل طلب المستهلكات'),
          backgroundColor: _roleColor,
        ),
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection(ConsumableRequestFields.collection)
              .doc(widget.requestId)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return const Center(child: Text('تعذر تحميل الطلب'));
            }
            final data = snapshot.data?.data();
            if (data == null) {
              return const Center(child: Text('الطلب غير موجود'));
            }
            final request = ConsumableRequestRead(
              id: widget.requestId,
              data: data,
            );
            if (!_canViewRequest(request)) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'ليست لديك صلاحية عرض هذا الطلب من هذا الفرع.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            final actions = _actions(request);
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _requestDocument(request),
                if (actions != null) ...[const SizedBox(height: 12), actions],
                const SizedBox(height: 12),
                _statusTimeline(request),
                const SizedBox(height: 12),
                _notes(request),
                const SizedBox(height: 12),
                _history(request),
              ],
            );
          },
        ),
      ),
    );
  }

  bool _canViewRequest(ConsumableRequestRead request) {
    if (widget.role == UserRole.admin) return false;
    final currentBranchId = widget.branchId ?? '';
    return currentBranchId.isNotEmpty && request.branchId == currentBranchId;
  }

  Widget _requestDocument(ConsumableRequestRead request) {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _requestHeader(request),
          const SizedBox(height: 16),
          _productsTable(request),
          const SizedBox(height: 14),
          _summary(request),
        ],
      ),
    );
  }

  Widget _requestHeader(ConsumableRequestRead request) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.dividerColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _roleColor.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(9),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _roleColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Icon(
                    Icons.inventory_2_rounded,
                    color: _roleColor,
                    size: 25,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'طلب استهلاك منتج للعرض',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        request.requestNumber,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _statusChip(request.status),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _infoBox('الفرع', request.branchName, Icons.storefront_rounded),
                _infoBox(
                  'تاريخ الطلب',
                  _formatDate(request.createdAt),
                  Icons.date_range_rounded,
                ),
                _infoBox(
                  'المرجع المحاسبي',
                  request.accountingReference.isEmpty
                      ? 'لم يعتمد بعد'
                      : request.accountingReference,
                  Icons.receipt_long_rounded,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoBox(String label, String value, IconData icon) {
    return Container(
      constraints: const BoxConstraints(minWidth: 140, maxWidth: 230),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: _roleColor),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value.isEmpty ? '-' : value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _productsTable(ConsumableRequestRead request) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.table_rows_rounded, color: _roleColor, size: 18),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                'جدول المنتجات',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 38,
                dataRowMinHeight: 44,
                dataRowMaxHeight: 58,
                horizontalMargin: 12,
                columnSpacing: 22,
                headingRowColor: WidgetStatePropertyAll(
                  _roleColor.withValues(alpha: 0.08),
                ),
                columns: const [
                  DataColumn(label: Text('#')),
                  DataColumn(label: Text('المنتج')),
                  DataColumn(label: Text('الوحدة')),
                  DataColumn(label: Text('المطلوب')),
                  DataColumn(label: Text('بعد مراجعة المدير العام')),
                ],
                rows: request.items.asMap().entries.map((entry) {
                  final item = entry.value;
                  final changed =
                      item.requestedQuantity != item.collectorQuantity;
                  return DataRow(
                    cells: [
                      DataCell(Text('${entry.key + 1}')),
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 190),
                          child: Text(
                            item.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      DataCell(Text(item.unit)),
                      DataCell(Text(_formatNumber(item.requestedQuantity))),
                      DataCell(
                        Text(
                          _formatNumber(item.collectorQuantity),
                          style: TextStyle(
                            color: changed
                                ? AppTheme.warningColor
                                : AppTheme.successColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _summary(ConsumableRequestRead request) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _summaryTile(
            'عدد المنتجات',
            '${request.items.length}',
            Icons.category_rounded,
            _roleColor,
          ),
          _summaryTile(
            'إجمالي المطلوب',
            _formatNumber(request.totalRequestedQuantity),
            Icons.playlist_add_check_rounded,
            AppTheme.managerColor,
          ),
          _summaryTile(
            'إجمالي المدير العام',
            _formatNumber(request.totalCollectorQuantity),
            Icons.inventory_rounded,
            AppTheme.collectorColor,
          ),
          _summaryTile(
            'تعديل الكمية',
            request.hasQuantityChanges ? 'يوجد تعديل' : 'بدون تعديل',
            request.hasQuantityChanges
                ? Icons.edit_note_rounded
                : Icons.check_circle_rounded,
            request.hasQuantityChanges
                ? AppTheme.warningColor
                : AppTheme.successColor,
          ),
        ],
      ),
    );
  }

  Widget _summaryTile(String label, String value, IconData icon, Color color) {
    return Container(
      constraints: const BoxConstraints(minWidth: 132, maxWidth: 190),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 7),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget? _actions(ConsumableRequestRead request) {
    final buttons = <Widget>[];

    if (widget.role == UserRole.collector &&
        request.status == ConsumableRequestStatus.pendingCollectorReview) {
      buttons.add(
        _actionButton(
          'قبول / تعديل الكمية',
          Icons.fact_check_rounded,
          AppTheme.collectorColor,
          () => _showCollectorReview(request),
        ),
      );
    }

    if (widget.role == UserRole.accountant &&
        request.status == ConsumableRequestStatus.pendingAccountingApproval) {
      buttons.add(
        _actionButton(
          'إدخال واعتماد',
          Icons.verified_rounded,
          AppTheme.accountantColor,
          () => _showAccounting(request),
        ),
      );
    }

    if (buttons.isEmpty) return null;
    return _panel(
      child: Row(
        children: [
          Icon(Icons.tune_rounded, color: _roleColor, size: 18),
          const SizedBox(width: 6),
          const Expanded(
            child: Text(
              'إجراءات الطلب',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          for (final button in buttons) button,
        ],
      ),
    );
  }

  Future<void> _showCollectorReview(ConsumableRequestRead request) async {
    final controllers = request.items
        .map(
          (item) => TextEditingController(
            text: _formatNumber(item.collectorQuantity),
          ),
        )
        .toList();
    final notes = TextEditingController(text: request.collectorNotes);

    await _dialog(
      title: 'مراجعة كميات المستهلكات',
      children: [
        ...request.items.asMap().entries.map((entry) {
          final item = entry.value;
          return TextField(
            controller: controllers[entry.key],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
            ],
            decoration: InputDecoration(
              labelText: '${item.name} - الكمية المقبولة',
              helperText:
                  'المطلوب: ${_formatNumber(item.requestedQuantity)} ${item.unit}',
            ),
          );
        }),
        TextField(
          controller: notes,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'ملاحظات المدير العام'),
        ),
      ],
      onSubmit: () async {
        final reviewedItems = request.items.asMap().entries.map((entry) {
          final item = entry.value;
          return item.copyWith(
            collectorQuantity: _parseNumber(controllers[entry.key].text),
          );
        }).toList();
        await _service.submitCollectorReview(
          requestId: request.id,
          reviewedItems: reviewedItems,
          branchId: widget.branchId,
          notes: notes.text,
        );
      },
    );
  }

  Future<void> _showAccounting(ConsumableRequestRead request) async {
    final reference = TextEditingController(text: request.accountingReference);
    final notes = TextEditingController(text: request.accountantNotes);
    await _dialog(
      title: 'الإدخال والاعتماد المحاسبي',
      children: [
        TextField(
          controller: reference,
          decoration: const InputDecoration(
            labelText: 'رقم القيد أو المرجع المحاسبي',
          ),
        ),
        TextField(
          controller: notes,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'ملاحظات المحاسب'),
        ),
      ],
      onSubmit: () async {
        await _service.approveAccounting(
          requestId: request.id,
          accountingReference: reference.text,
          branchId: widget.branchId,
          notes: notes.text,
        );
      },
    );
  }

  Future<void> _dialog({
    required String title,
    required List<Widget> children,
    required Future<void> Function() onSubmit,
  }) async {
    var saving = false;
    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final child in children) ...[
                  child,
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            ElevatedButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      setDialogState(() => saving = true);
                      try {
                        await onSubmit();
                        if (!mounted || !dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        _showSnack('تم تنفيذ الإجراء');
                      } catch (e) {
                        setDialogState(() => saving = false);
                        _showSnack(
                          e.toString().replaceFirst('Exception: ', ''),
                        );
                      }
                    },
              icon: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.save_rounded),
              label: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusTimeline(ConsumableRequestRead request) {
    final steps = [
      _TimelineStep(
        title: 'طلب المدير',
        subtitle: 'تم إنشاء طلب المستهلكات',
        icon: Icons.assignment_rounded,
        color: AppTheme.managerColor,
      ),
      const _TimelineStep(
        title: 'مراجعة المدير العام',
        subtitle: 'قبول الطلب أو تعديل الكمية',
        icon: Icons.fact_check_rounded,
        color: AppTheme.collectorColor,
      ),
      const _TimelineStep(
        title: 'اعتماد المحاسب',
        subtitle: 'إدخال الطلب في النظام المحاسبي وإقفاله',
        icon: Icons.verified_rounded,
        color: AppTheme.accountantColor,
      ),
    ];
    final current = switch (request.status) {
      ConsumableRequestStatus.pendingCollectorReview => 0,
      ConsumableRequestStatus.pendingAccountingApproval => 1,
      ConsumableRequestStatus.approvedByAccountant => 2,
    };

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.route_rounded, color: _roleColor, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'مسار حالة الطلب',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              _statusChip(request.status),
            ],
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < steps.length; index++)
            _timelineRow(
              step: steps[index],
              isFirst: index == 0,
              isLast: index == steps.length - 1,
              isCompleted:
                  index < current ||
                  request.status ==
                      ConsumableRequestStatus.approvedByAccountant,
              isActive: index == current,
              activeLabel: index == current ? request.status.label : null,
            ),
        ],
      ),
    );
  }

  Widget _timelineRow({
    required _TimelineStep step,
    required bool isFirst,
    required bool isLast,
    required bool isCompleted,
    required bool isActive,
    String? activeLabel,
  }) {
    final color = isCompleted || isActive ? step.color : AppTheme.textHint;
    final stateLabel = isCompleted
        ? 'مكتمل'
        : isActive
        ? activeLabel ?? 'الحالي'
        : 'بانتظار';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 34,
          child: Column(
            children: [
              if (!isFirst)
                Container(
                  width: 2,
                  height: 10,
                  color: isCompleted || isActive
                      ? color.withValues(alpha: 0.45)
                      : AppTheme.dividerColor,
                ),
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isActive ? 0.14 : 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: isActive ? 2 : 1),
                ),
                child: Icon(
                  isCompleted ? Icons.check_rounded : step.icon,
                  color: color,
                  size: 17,
                ),
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: 34,
                  color: isCompleted
                      ? color.withValues(alpha: 0.45)
                      : AppTheme.dividerColor,
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            margin: EdgeInsets.only(bottom: isLast ? 0 : 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isActive
                  ? color.withValues(alpha: 0.08)
                  : AppTheme.surfaceColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isActive
                    ? color.withValues(alpha: 0.18)
                    : AppTheme.dividerColor,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.title,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isActive && activeLabel != null
                            ? activeLabel
                            : step.subtitle,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 92),
                  child: Text(
                    stateLabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _notes(ConsumableRequestRead request) {
    final notes = <Widget>[];
    if (request.managerNotes.isNotEmpty) {
      notes.add(
        _noteRow(
          'ملاحظات المدير',
          request.managerNotes,
          Icons.business_center_rounded,
        ),
      );
    }
    if (request.collectorNotes.isNotEmpty) {
      notes.add(
        _noteRow(
          'ملاحظات المدير العام',
          request.collectorNotes,
          Icons.person_rounded,
        ),
      );
    }
    if (request.accountantNotes.isNotEmpty) {
      notes.add(
        _noteRow(
          'ملاحظات المحاسب',
          request.accountantNotes,
          Icons.calculate_rounded,
        ),
      );
    }
    if (notes.isEmpty) return const SizedBox.shrink();
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'ملاحظات الطلب',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          for (final note in notes) note,
        ],
      ),
    );
  }

  Widget _noteRow(String title, String note, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _roleColor, size: 19),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(note, style: const TextStyle(height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _history(ConsumableRequestRead request) {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'سجل الطلب',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          if (request.history.isEmpty)
            const Text('لا يوجد سجل بعد')
          else
            ...request.history.reversed.map((entry) {
              final timestamp = entry['timestamp'];
              final date = timestamp is Timestamp ? timestamp.toDate() : null;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.history_rounded, color: _roleColor),
                title: Text(entry['message']?.toString() ?? '-'),
                subtitle: Text(
                  '${entry['actor_name'] ?? '-'} - ${entry['actor_role'] ?? '-'}'
                  '${date == null ? '' : '\n${_formatDate(date)}'}'
                  '${(entry['note']?.toString() ?? '').isEmpty ? '' : '\n${entry['note']}'}',
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _panel({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardShadow(),
      child: child,
    );
  }

  Widget _actionButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 0,
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _statusChip(ConsumableRequestStatus status) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 150),
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

  String _formatDate(DateTime? value) {
    if (value == null) return '-';
    return _dateFormat.format(value);
  }

  String _formatNumber(double value) => _numberFormat.format(value);

  double _parseNumber(String value) =>
      double.tryParse(value.trim().replaceAll(',', '.')) ?? 0;

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _TimelineStep {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _TimelineStep({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}
