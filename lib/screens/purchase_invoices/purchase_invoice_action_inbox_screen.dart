import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/models/purchase_invoice_model.dart';
import 'package:store_collection_app/screens/purchase_invoices/purchase_invoice_details_screen.dart';
import 'package:store_collection_app/services/purchase_invoice_service.dart';
import 'package:store_collection_app/theme/app_theme.dart';

enum _InboxFilter { all, workflow, amendment }

/// A cross-branch inbox for the two purchase roles that choose a branch first.
/// It deliberately shows only actions assigned to the signed-in role and, for
/// controlled edits, only amendments that still need this exact user's vote.
class PurchaseInvoiceActionInboxScreen extends StatefulWidget {
  final UserRole role;

  const PurchaseInvoiceActionInboxScreen({super.key, required this.role});

  @override
  State<PurchaseInvoiceActionInboxScreen> createState() =>
      _PurchaseInvoiceActionInboxScreenState();
}

class _PurchaseInvoiceActionInboxScreenState
    extends State<PurchaseInvoiceActionInboxScreen> {
  final PurchaseInvoiceService _service = PurchaseInvoiceService();
  final TextEditingController _search = TextEditingController();
  _InboxFilter _filter = _InboxFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(title: const Text('مهامي في فواتير المشتريات')),
        body: uid.isEmpty
            ? const Center(child: Text('انتهت جلسة الدخول. سجل الدخول مجدداً.'))
            : StreamBuilder<List<PurchaseInvoiceRead>>(
                stream: _service.watchDashboard(role: widget.role),
                builder: (context, workflowSnapshot) =>
                    StreamBuilder<List<PurchaseInvoiceAmendment>>(
                      stream: _service.watchMyPendingAmendments(
                        uid,
                        role: widget.role,
                      ),
                      builder: (context, amendmentSnapshot) {
                        if (amendmentSnapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (amendmentSnapshot.hasError) {
                          return _amendmentLoadError();
                        }
                        return _body(
                          workflowSnapshot.data ?? const [],
                          amendmentSnapshot.data ?? const [],
                          workflowUnavailable: workflowSnapshot.hasError,
                        );
                      },
                    ),
              ),
      ),
    );
  }

  Widget _body(
    List<PurchaseInvoiceRead> workflowInvoices,
    List<PurchaseInvoiceAmendment> amendments, {
    required bool workflowUnavailable,
  }) {
    final query = _search.text.trim().toLowerCase();
    final visibleWorkflow = workflowInvoices
        .where((invoice) => _matchesInvoice(invoice, query))
        .toList(growable: false);
    final showWorkflow = _filter != _InboxFilter.amendment;
    final showAmendments = _filter != _InboxFilter.workflow;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _intro(workflowInvoices.length, amendments.length),
        if (workflowUnavailable) ...[
          const SizedBox(height: 10),
          _workflowLoadWarning(),
        ],
        const SizedBox(height: 14),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'بحث برقم الفاتورة أو الفرع أو المورد',
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _filterChip(_InboxFilter.all, 'كل مهامي'),
            _filterChip(_InboxFilter.workflow, _workflowFilterLabel),
            _filterChip(_InboxFilter.amendment, 'اعتمادات التعديل'),
          ],
        ),
        if (showWorkflow) ...[
          const SizedBox(height: 20),
          _sectionTitle(_workflowFilterLabel, Icons.playlist_add_check_rounded),
          const SizedBox(height: 8),
          if (visibleWorkflow.isEmpty)
            _empty('لا توجد فواتير جاهزة لإجرائك الآن.')
          else
            ...visibleWorkflow.map(_workflowCard),
        ],
        if (showAmendments) ...[
          const SizedBox(height: 20),
          _sectionTitle('اعتمادات تعديل بانتظارك', Icons.edit_note_rounded),
          const SizedBox(height: 8),
          if (amendments.isEmpty)
            _empty('لا توجد تعديلات بانتظار موافقتك.')
          else
            ...amendments.map((amendment) => _amendmentCard(amendment, query)),
        ],
      ],
    );
  }

  Widget _intro(int workflowCount, int amendmentCount) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppTheme.primaryOlive.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppTheme.primaryOlive.withValues(alpha: .14)),
    ),
    child: Text(
      'هذه القائمة تخص حسابك ودورك فقط: $workflowCount إجراء في مسار الفاتورة و$amendmentCount اعتماد تعديل.',
      style: const TextStyle(height: 1.45),
    ),
  );

  Widget _filterChip(_InboxFilter value, String label) => FilterChip(
    label: Text(label),
    selected: _filter == value,
    onSelected: (_) => setState(() => _filter = value),
  );

  Widget _sectionTitle(String value, IconData icon) => Row(
    children: [
      Icon(icon, color: AppTheme.primaryOlive),
      const SizedBox(width: 8),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
    ],
  );

  Widget _empty(String text) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppTheme.cardColor,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: AppTheme.textHint),
    ),
  );

  Widget _amendmentLoadError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 38),
          const SizedBox(height: 10),
          const Text(
            'تعذر تحميل اعتمادات التعديل من الخدمة. تحقق من الاتصال ثم أعد المحاولة.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => setState(() {}),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    ),
  );

  Widget _workflowLoadWarning() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF3E0),
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Text(
      'تعذر تحميل بعض مهام سير الفاتورة، لكن اعتمادات التعديل أدناه ما زالت متاحة.',
      textAlign: TextAlign.center,
    ),
  );

  Widget _workflowCard(PurchaseInvoiceRead invoice) => Card(
    margin: const EdgeInsets.only(bottom: 9),
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: invoice.workflowColor.withValues(alpha: .12),
        child: Icon(Icons.receipt_long_rounded, color: invoice.workflowColor),
      ),
      title: Text(
        invoice.purchaseNumber,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        '${invoice.receivingBranchName} • ${invoice.workflowLabel}',
      ),
      trailing: const Icon(Icons.chevron_left_rounded),
      onTap: () => _openInvoice(invoice),
    ),
  );

  Widget _amendmentCard(
    PurchaseInvoiceAmendment amendment,
    String query,
  ) => StreamBuilder<PurchaseInvoiceRead?>(
    stream: _service.watchInvoice(amendment.invoiceId),
    builder: (context, snapshot) {
      final invoice = snapshot.data;
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Padding(
          padding: EdgeInsets.all(12),
          child: LinearProgressIndicator(),
        );
      }
      if (invoice != null && !_matchesInvoice(invoice, query)) {
        return const SizedBox.shrink();
      }
      if (invoice == null && !_matchesAmendment(amendment, query)) {
        return const SizedBox.shrink();
      }
      return Card(
        margin: const EdgeInsets.only(bottom: 9),
        child: ListTile(
          leading: const CircleAvatar(
            backgroundColor: Color(0xFFFFE0B2),
            child: Icon(Icons.edit_note_rounded, color: AppTheme.warningColor),
          ),
          title: Text(
            invoice?.purchaseNumber.isNotEmpty == true
                ? invoice!.purchaseNumber
                : (amendment.purchaseNumber.isNotEmpty
                      ? amendment.purchaseNumber
                      : 'فاتورة بانتظار اعتماد تعديل'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            '${invoice?.receivingBranchName.isNotEmpty == true ? invoice!.receivingBranchName : amendment.receivingBranchName} • تعديل بانتظار اعتمادك',
          ),
          trailing: const Icon(Icons.chevron_left_rounded),
          onTap: () => _openAmendmentInvoice(amendment, invoice),
        ),
      );
    },
  );

  bool _matchesAmendment(PurchaseInvoiceAmendment amendment, String query) {
    if (query.isEmpty) return true;
    return [
      amendment.purchaseNumber,
      amendment.receivingBranchName,
      amendment.requestedByName,
      amendment.reason,
    ].any((value) => value.toLowerCase().contains(query));
  }

  bool _matchesInvoice(PurchaseInvoiceRead invoice, String query) {
    if (query.isEmpty) return true;
    return [
      invoice.purchaseNumber,
      invoice.receivingBranchName,
      invoice.supplierName,
      invoice.workflowLabel,
    ].any((value) => value.toLowerCase().contains(query));
  }

  String get _workflowFilterLabel => switch (widget.role) {
    UserRole.collector => 'اعتماد الأسعار',
    UserRole.accountant => 'المراجع والترحيل',
    _ => 'إجراءات الفاتورة',
  };

  void _openInvoice(PurchaseInvoiceRead invoice) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => PurchaseInvoiceDetailsScreen(
        invoiceId: invoice.id,
        role: widget.role,
        branchId: invoice.receivingBranchId,
      ),
    ),
  );

  void _openAmendmentInvoice(
    PurchaseInvoiceAmendment amendment,
    PurchaseInvoiceRead? invoice,
  ) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => PurchaseInvoiceDetailsScreen(
        invoiceId: amendment.invoiceId,
        role: widget.role,
        branchId: invoice?.receivingBranchId ?? amendment.receivingBranchId,
      ),
    ),
  );
}
