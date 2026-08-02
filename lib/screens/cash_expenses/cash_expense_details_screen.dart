import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:store_collection_app/models/cash_expense_request_model.dart';
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/services/cash_expense_service.dart';
import 'package:store_collection_app/services/pdf_service.dart';
import 'package:store_collection_app/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

class CashExpenseDetailsScreen extends StatefulWidget {
  final String requestId;
  final UserRole role;
  final String? branchId;
  final String branchName;

  const CashExpenseDetailsScreen({
    super.key,
    required this.requestId,
    required this.role,
    required this.branchName,
    this.branchId,
  });

  @override
  State<CashExpenseDetailsScreen> createState() =>
      _CashExpenseDetailsScreenState();
}

class _CashExpenseDetailsScreenState extends State<CashExpenseDetailsScreen> {
  final _service = CashExpenseService();
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
          title: const Text('تفاصيل الصرف النقدي'),
          backgroundColor: _roleColor,
        ),
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection(CashExpenseFields.collection)
              .doc(widget.requestId)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return const Center(child: Text('تعذر تحميل طلب الصرف'));
            }
            final data = snapshot.data?.data();
            if (data == null) {
              return const Center(child: Text('طلب الصرف غير موجود'));
            }
            final request = CashExpenseRead(id: widget.requestId, data: data);
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
                _expenseDocument(request),
                if (actions != null) ...[const SizedBox(height: 12), actions],
                if (request.editRequest.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _editRequestPanel(request),
                ],
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

  bool _canViewRequest(CashExpenseRead request) {
    if (widget.role == UserRole.admin) return false;
    final currentBranchId = widget.branchId ?? '';
    return currentBranchId.isNotEmpty && request.branchId == currentBranchId;
  }

  Widget _expenseDocument(CashExpenseRead request) {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(request),
          const SizedBox(height: 14),
          _amountSummary(request),
          const SizedBox(height: 14),
          _invoiceAttachment(request),
        ],
      ),
    );
  }

  Widget _header(CashExpenseRead request) {
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
                    Icons.payments_rounded,
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
                        'سند صرف نقدي',
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  request.title.isEmpty ? '-' : request.title,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (request.description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    request.description,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _infoBox(
                      'الفرع',
                      request.branchName,
                      Icons.storefront_rounded,
                    ),
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _amountSummary(CashExpenseRead request) {
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
            'المبلغ المطلوب',
            '${_formatNumber(request.requestedAmount)} ${request.currency}',
            Icons.request_quote_rounded,
            AppTheme.managerColor,
          ),
          _summaryTile(
            'المبلغ المعتمد',
            '${_formatNumber(request.approvedAmount)} ${request.currency}',
            Icons.verified_rounded,
            request.hasAmountChange
                ? AppTheme.warningColor
                : AppTheme.successColor,
          ),
          _summaryTile(
            'تعديل المبلغ',
            request.hasAmountChange ? 'تم التعديل' : 'بدون تعديل',
            request.hasAmountChange
                ? Icons.edit_note_rounded
                : Icons.check_circle_rounded,
            request.hasAmountChange
                ? AppTheme.warningColor
                : AppTheme.successColor,
          ),
        ],
      ),
    );
  }

  Widget _invoiceAttachment(CashExpenseRead request) {
    final hasInvoice = request.invoiceUrl.isNotEmpty;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: hasInvoice ? () => _openAttachment(request) : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: hasInvoice
                ? AppTheme.successColor.withValues(alpha: 0.06)
                : AppTheme.surfaceColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: hasInvoice
                  ? AppTheme.successColor.withValues(alpha: 0.16)
                  : AppTheme.dividerColor,
            ),
          ),
          child: Row(
            children: [
              Icon(
                hasInvoice
                    ? Icons.attach_file_rounded
                    : Icons.upload_file_rounded,
                color: hasInvoice ? AppTheme.successColor : AppTheme.textHint,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'فاتورة المصروف',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasInvoice ? request.invoiceFileName : 'بدون ملف مرفق',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: hasInvoice
                            ? AppTheme.successColor
                            : AppTheme.textSecondary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasInvoice) ...[
                const SizedBox(width: 8),
                const Icon(
                  Icons.open_in_new_rounded,
                  color: AppTheme.successColor,
                  size: 18,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openAttachment(CashExpenseRead request) async {
    if (request.invoiceUrl.isEmpty) return;
    if (_isImageAttachment(request)) {
      await showDialog(
        context: context,
        builder: (dialogContext) => Directionality(
          textDirection: TextDirection.rtl,
          child: Dialog(
            insetPadding: const EdgeInsets.all(18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.image_rounded),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            request.invoiceFileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          tooltip: 'إغلاق',
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: InteractiveViewer(
                      minScale: 0.7,
                      maxScale: 4,
                      child: Image.network(
                        request.invoiceUrl,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('تعذر عرض الصورة'),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton.icon(
                        onPressed: () => _openExternalUrl(request.invoiceUrl),
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: const Text('فتح خارجياً'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      return;
    }
    await _openExternalUrl(request.invoiceUrl);
  }

  bool _isImageAttachment(CashExpenseRead request) {
    final contentType = request.invoiceContentType.toLowerCase();
    final fileName = request.invoiceFileName.toLowerCase();
    return contentType.startsWith('image/') ||
        fileName.endsWith('.png') ||
        fileName.endsWith('.jpg') ||
        fileName.endsWith('.jpeg');
  }

  Future<void> _openExternalUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      _showSnack('رابط الملف غير صالح');
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) _showSnack('تعذر فتح الملف');
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

  Widget _summaryTile(String label, String value, IconData icon, Color color) {
    return Container(
      constraints: const BoxConstraints(minWidth: 150, maxWidth: 250),
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

  Widget? _actions(CashExpenseRead request) {
    final buttons = <Widget>[];

    buttons.add(
      _actionButton(
        'طباعة',
        Icons.print_rounded,
        _roleColor,
        () => _printRequest(request),
      ),
    );

    if (_canRequestEdit(request)) {
      buttons.add(
        _actionButton(
          'طلب تعديل',
          Icons.edit_note_rounded,
          AppTheme.warningColor,
          () => _showRequestEdit(request),
        ),
      );
    }

    if (_canManagerApplyApprovedEdit(request)) {
      buttons.add(
        _actionButton(
          'تعديل البيانات',
          Icons.edit_rounded,
          AppTheme.managerColor,
          () => _showManagerEditAfterApproval(request),
        ),
      );
    }

    if (_canDecideEdit(request)) {
      buttons.addAll([
        _actionButton(
          'موافقة التعديل',
          Icons.check_rounded,
          AppTheme.successColor,
          () => _showEditApproval(request, approved: true),
        ),
        _actionButton(
          'رفض التعديل',
          Icons.close_rounded,
          AppTheme.errorColor,
          () => _showEditApproval(request, approved: false),
        ),
      ]);
    }

    if (widget.role == UserRole.collector &&
        request.status == CashExpenseStatus.pendingGeneralManagerReview &&
        !_allEditApprovalsApproved(request)) {
      buttons.addAll([
        _actionButton(
          'اعتماد / تعديل',
          Icons.fact_check_rounded,
          AppTheme.successColor,
          () => _showGeneralManagerDecision(request, approved: true),
        ),
        _actionButton(
          'رفض',
          Icons.close_rounded,
          AppTheme.errorColor,
          () => _showGeneralManagerDecision(request, approved: false),
        ),
      ]);
    }

    if (widget.role == UserRole.manager &&
        request.status == CashExpenseStatus.pendingInvoiceAttachment) {
      buttons.addAll([
        _actionButton(
          'إرفاق واعتماد',
          Icons.upload_file_rounded,
          AppTheme.managerColor,
          () => _showInvoiceUpload(request),
        ),
        _actionButton(
          'بدون ملف',
          Icons.file_present_rounded,
          AppTheme.textSecondary,
          () => _showApproveWithoutInvoice(request),
        ),
      ]);
    }

    if (widget.role == UserRole.accountant &&
        request.status == CashExpenseStatus.pendingAccountingApproval) {
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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Icon(Icons.tune_rounded, color: _roleColor, size: 18),
            const SizedBox(width: 8),
            const Text(
              'إجراءات الطلب',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 12),
            for (final button in buttons) ...[
              button,
              if (button != buttons.last) const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _printRequest(CashExpenseRead request) async {
    try {
      await PdfService.printCashExpenseRequest(
        data: request.data,
        branchName: request.branchName,
      );
    } catch (e) {
      _showSnack(
        'تعذر طباعة السند: ${e.toString().replaceFirst('Exception: ', '')}',
      );
    }
  }

  bool _canRequestEdit(CashExpenseRead request) {
    if (request.status.isFinal ||
        request.status == CashExpenseStatus.editPendingApprovals ||
        _allEditApprovalsApproved(request) ||
        _canManagerApplyApprovedEdit(request)) {
      return false;
    }
    return _editPartyForRole(widget.role) != null;
  }

  bool _canManagerApplyApprovedEdit(CashExpenseRead request) {
    return widget.role == UserRole.manager &&
        request.status == CashExpenseStatus.pendingGeneralManagerReview &&
        _allEditApprovalsApproved(request);
  }

  bool _allEditApprovalsApproved(CashExpenseRead request) {
    const parties = ['manager', 'general_manager', 'accountant'];
    return request.editRequest.isNotEmpty &&
        parties.every((party) {
          final entry = request.editApprovals[party];
          return entry is Map && entry['approved'] == true;
        });
  }

  bool _canDecideEdit(CashExpenseRead request) {
    if (request.status != CashExpenseStatus.editPendingApprovals) return false;
    final party = _editPartyForRole(widget.role);
    if (party == null) return false;
    return !request.editApprovals.containsKey(party);
  }

  String? _editPartyForRole(UserRole role) {
    switch (role) {
      case UserRole.manager:
        return 'manager';
      case UserRole.collector:
        return 'general_manager';
      case UserRole.accountant:
        return 'accountant';
      case UserRole.admin:
        return null;
    }
  }

  Future<void> _showGeneralManagerDecision(
    CashExpenseRead request, {
    required bool approved,
  }) async {
    final title = TextEditingController(text: request.title);
    final description = TextEditingController(text: request.description);
    final amount = TextEditingController(
      text: _formatNumber(request.approvedAmount),
    );
    final notes = TextEditingController();

    await _dialog(
      title: approved ? 'اعتماد أو تعديل سند الصرف' : 'رفض سند الصرف',
      children: [
        if (approved) ...[
          TextField(
            controller: title,
            decoration: const InputDecoration(labelText: 'عنوان المصروف'),
          ),
          TextField(
            controller: description,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'تفاصيل المصروف'),
          ),
          TextField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
            ],
            decoration: const InputDecoration(labelText: 'المبلغ المعتمد'),
          ),
        ],
        TextField(
          controller: notes,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: approved ? 'ملاحظات المدير العام' : 'سبب الرفض',
          ),
        ),
      ],
      onSubmit: () async {
        await _service.submitGeneralManagerDecision(
          requestId: request.id,
          approved: approved,
          approvedAmount: approved
              ? _parseNumber(amount.text)
              : request.approvedAmount,
          title: title.text,
          description: description.text,
          branchId: widget.branchId,
          notes: notes.text,
        );
      },
    );
  }

  Future<void> _showInvoiceUpload(CashExpenseRead request) async {
    final notes = TextEditingController(text: request.invoiceNotes);
    PlatformFile? pickedFile;

    await _dialog(
      title: 'إرفاق فاتورة المصروف',
      children: [
        StatefulBuilder(
          builder: (context, setLocalState) {
            return OutlinedButton.icon(
              onPressed: () async {
                final result = await FilePicker.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
                  withData: true,
                );
                if (result == null || result.files.isEmpty) return;
                setLocalState(() => pickedFile = result.files.single);
              },
              icon: const Icon(Icons.attach_file_rounded),
              label: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  pickedFile?.name ?? 'اختيار ملف PDF أو صورة',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );
          },
        ),
        TextField(
          controller: notes,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'ملاحظات الفاتورة'),
        ),
      ],
      onSubmit: () async {
        final file = pickedFile;
        final bytes = file?.bytes;
        if (file == null || bytes == null || bytes.isEmpty) {
          throw Exception('اختر ملف الفاتورة أولاً.');
        }
        await _service.attachInvoiceAndApprove(
          requestId: request.id,
          fileBytes: bytes,
          fileName: file.name,
          branchId: widget.branchId,
          notes: notes.text,
        );
      },
    );
  }

  Future<void> _showApproveWithoutInvoice(CashExpenseRead request) async {
    final notes = TextEditingController(text: request.invoiceNotes);
    await _dialog(
      title: 'اعتماد بدون ملف مرفق',
      children: [
        const Text(
          'سيتم إرسال سند الصرف للمحاسب بحالة بدون ملف مرفق.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        TextField(
          controller: notes,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'ملاحظات اختيارية'),
        ),
      ],
      onSubmit: () async {
        await _service.approveWithoutInvoice(
          requestId: request.id,
          branchId: widget.branchId,
          notes: notes.text,
        );
      },
    );
  }

  Future<void> _showManagerEditAfterApproval(CashExpenseRead request) async {
    final title = TextEditingController(text: request.title);
    final description = TextEditingController(text: request.description);
    final amount = TextEditingController(
      text: _formatNumber(request.requestedAmount),
    );
    final notes = TextEditingController(text: request.managerNotes);
    PlatformFile? pickedFile;

    await _dialog(
      title: 'تعديل بيانات سند الصرف',
      children: [
        TextField(
          controller: title,
          decoration: const InputDecoration(labelText: 'عنوان المصروف'),
        ),
        TextField(
          controller: description,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'تفاصيل المصروف'),
        ),
        TextField(
          controller: amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
          ],
          decoration: const InputDecoration(labelText: 'المبلغ المطلوب'),
        ),
        StatefulBuilder(
          builder: (context, setLocalState) {
            return OutlinedButton.icon(
              onPressed: () async {
                final result = await FilePicker.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
                  withData: true,
                );
                if (result == null || result.files.isEmpty) return;
                setLocalState(() => pickedFile = result.files.single);
              },
              icon: const Icon(Icons.attach_file_rounded),
              label: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  pickedFile?.name ?? 'إرفاق ملف بديل اختياري',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );
          },
        ),
        TextField(
          controller: notes,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'ملاحظات مدير الفرع'),
        ),
      ],
      onSubmit: () async {
        await _service.updateManagerRequestAfterEditApproval(
          requestId: request.id,
          title: title.text,
          description: description.text,
          amount: _parseNumber(amount.text),
          branchId: widget.branchId,
          notes: notes.text,
          invoiceFileBytes: pickedFile?.bytes,
          invoiceFileName: pickedFile?.name,
        );
      },
    );
  }

  Future<void> _showAccounting(CashExpenseRead request) async {
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

  Future<void> _showRequestEdit(CashExpenseRead request) async {
    final reason = TextEditingController();
    await _dialog(
      title: 'طلب تعديل سند الصرف',
      children: [
        TextField(
          controller: reason,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'سبب طلب التعديل'),
        ),
      ],
      onSubmit: () async {
        await _service.requestEdit(
          requestId: request.id,
          branchId: widget.branchId,
          reason: reason.text,
        );
      },
    );
  }

  Future<void> _showEditApproval(
    CashExpenseRead request, {
    required bool approved,
  }) async {
    final notes = TextEditingController();
    await _dialog(
      title: approved ? 'الموافقة على طلب التعديل' : 'رفض طلب التعديل',
      children: [
        TextField(
          controller: notes,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: approved ? 'ملاحظات اختيارية' : 'سبب الرفض',
          ),
        ),
      ],
      onSubmit: () async {
        await _service.submitEditApproval(
          requestId: request.id,
          branchId: widget.branchId,
          approved: approved,
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

  Widget _editRequestPanel(CashExpenseRead request) {
    final editRequest = request.editRequest;
    final approvals = request.editApprovals;
    final reason = editRequest['reason']?.toString() ?? '-';
    final requester = editRequest['requested_by_name']?.toString() ?? '-';
    final requestedAt = _timestampToDate(editRequest['requested_at']);
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_note_rounded, color: AppTheme.warningColor),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'طلب تعديل السند',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              _statusChip(request.status),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            reason,
            style: const TextStyle(color: AppTheme.textPrimary, height: 1.4),
          ),
          const SizedBox(height: 6),
          Text(
            '$requester${requestedAt == null ? '' : ' - ${_formatDate(requestedAt)}'}',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _approvalPill('مدير الفرع', approvals['manager']),
              _approvalPill('المدير العام', approvals['general_manager']),
              _approvalPill('المحاسب', approvals['accountant']),
            ],
          ),
        ],
      ),
    );
  }

  Widget _approvalPill(String label, dynamic entry) {
    final approval = entry is Map ? Map<String, dynamic>.from(entry) : null;
    final approved = approval?['approved'] == true;
    final rejected = approval?['approved'] == false;
    final color = approved
        ? AppTheme.successColor
        : rejected
        ? AppTheme.errorColor
        : AppTheme.textSecondary;
    final text = approved
        ? 'موافق'
        : rejected
        ? 'مرفوض'
        : 'بانتظار';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            approved
                ? Icons.check_circle_rounded
                : rejected
                ? Icons.cancel_rounded
                : Icons.schedule_rounded,
            color: color,
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            '$label: $text',
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _statusTimeline(CashExpenseRead request) {
    final editPending =
        request.status == CashExpenseStatus.editPendingApprovals;
    final steps = [
      const _TimelineStep(
        title: 'طلب مدير الفرع',
        subtitle: 'تم إنشاء طلب الصرف النقدي',
        icon: Icons.assignment_rounded,
        color: AppTheme.managerColor,
      ),
      if (editPending)
        const _TimelineStep(
          title: 'موافقات التعديل',
          subtitle: 'بانتظار موافقة الأدوار على إعادة فتح السند',
          icon: Icons.edit_note_rounded,
          color: AppTheme.warningColor,
        ),
      const _TimelineStep(
        title: 'مراجعة المدير العام',
        subtitle: 'قبول أو رفض أو تعديل السند',
        icon: Icons.fact_check_rounded,
        color: AppTheme.collectorColor,
      ),
      const _TimelineStep(
        title: 'فاتورة المصروف',
        subtitle: 'إرفاق الفاتورة واعتمادها من مدير الفرع',
        icon: Icons.upload_file_rounded,
        color: AppTheme.managerColor,
      ),
      const _TimelineStep(
        title: 'الاعتماد المحاسبي',
        subtitle: 'إدخال المصروف في النظام المحاسبي وإقفاله',
        icon: Icons.verified_rounded,
        color: AppTheme.accountantColor,
      ),
    ];
    final current = editPending
        ? 1
        : switch (request.status) {
            CashExpenseStatus.pendingGeneralManagerReview => 0,
            CashExpenseStatus.rejectedByGeneralManager => 1,
            CashExpenseStatus.pendingInvoiceAttachment => 2,
            CashExpenseStatus.pendingAccountingApproval => 3,
            CashExpenseStatus.approvedByAccountant => 3,
            CashExpenseStatus.editPendingApprovals => 1,
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
                  'مسار حالة الصرف',
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
                  request.status == CashExpenseStatus.approvedByAccountant,
              isActive: index == current,
              isRejected:
                  request.status ==
                      CashExpenseStatus.rejectedByGeneralManager &&
                  index == current,
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
    required bool isRejected,
    String? activeLabel,
  }) {
    final color = isRejected
        ? AppTheme.errorColor
        : isCompleted || isActive
        ? step.color
        : AppTheme.textHint;
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

  Widget _notes(CashExpenseRead request) {
    final notes = <Widget>[];
    if (request.managerNotes.isNotEmpty) {
      notes.add(
        _noteRow(
          'ملاحظات مدير الفرع',
          request.managerNotes,
          Icons.business_center_rounded,
        ),
      );
    }
    if (request.generalManagerNotes.isNotEmpty) {
      notes.add(
        _noteRow(
          'ملاحظات المدير العام',
          request.generalManagerNotes,
          Icons.admin_panel_settings_rounded,
        ),
      );
    }
    if (request.rejectionReason.isNotEmpty) {
      notes.add(
        _noteRow('سبب الرفض', request.rejectionReason, Icons.cancel_rounded),
      );
    }
    if (request.invoiceNotes.isNotEmpty) {
      notes.add(
        _noteRow(
          'ملاحظات الفاتورة',
          request.invoiceNotes,
          Icons.attach_file_rounded,
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
            'ملاحظات الصرف',
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

  Widget _history(CashExpenseRead request) {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'سجل الصرف',
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

  Widget _statusChip(CashExpenseStatus status) {
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

  DateTime? _timestampToDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
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
