import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/models/product_price_model.dart';
import 'package:store_collection_app/models/purchase_invoice_model.dart';
import 'package:store_collection_app/models/purchase_invoice_price_model.dart';
import 'package:store_collection_app/services/product_price_service.dart';
import 'package:store_collection_app/services/purchase_invoice_api_service.dart';
import 'package:store_collection_app/services/purchase_invoice_pdf_service.dart';
import 'package:store_collection_app/services/purchase_invoice_service.dart';
import 'package:store_collection_app/theme/app_theme.dart';

class PurchaseInvoiceDetailsScreen extends StatefulWidget {
  final String invoiceId;
  final UserRole role;
  final String? branchId;
  final PurchaseInvoiceRead? fixtureInvoice;
  final PurchaseInvoicePriceSnapshot? fixturePrices;

  const PurchaseInvoiceDetailsScreen({
    super.key,
    required this.invoiceId,
    required this.role,
    this.branchId,
    this.fixtureInvoice,
    this.fixturePrices,
  });

  @override
  State<PurchaseInvoiceDetailsScreen> createState() =>
      _PurchaseInvoiceDetailsScreenState();
}

class _PurchaseInvoiceDetailsScreenState
    extends State<PurchaseInvoiceDetailsScreen> {
  late final PurchaseInvoiceService _service = PurchaseInvoiceService();
  late final PurchaseInvoiceApiService _api = PurchaseInvoiceApiService();
  late final Stream<PurchaseInvoiceRead?> _headerStream = _service.watchInvoice(
    widget.invoiceId,
  );
  late final Stream<PurchaseInvoicePriceSnapshot?> _priceStream = _service
      .watchProtectedPrices(widget.invoiceId);
  String? _loadedInvoiceKey;
  Future<PurchaseInvoiceRead>? _invoiceFuture;
  bool _submitting = false;

  Future<PurchaseInvoiceRead> _itemsFor(PurchaseInvoiceRead header) {
    final key = '${header.id}-${header.revision}-${header.itemDigest}';
    if (_loadedInvoiceKey != key || _invoiceFuture == null) {
      _loadedInvoiceKey = key;
      _invoiceFuture = _service.loadInvoiceWithItems(widget.invoiceId);
    }
    return _invoiceFuture!;
  }

  bool get _mayReadPrices => const {
    UserRole.collector,
    UserRole.accountant,
    UserRole.admin,
  }.contains(widget.role);

  @override
  Widget build(BuildContext context) {
    if (widget.fixtureInvoice != null) {
      return _page(widget.fixtureInvoice!, widget.fixturePrices);
    }
    return StreamBuilder<PurchaseInvoiceRead?>(
      stream: _headerStream,
      builder: (context, headerSnapshot) {
        final header = headerSnapshot.data;
        if (headerSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (header == null) {
          return const Scaffold(
            body: Center(child: Text('فاتورة المشتريات غير موجودة.')),
          );
        }
        return FutureBuilder<PurchaseInvoiceRead>(
          key: ValueKey('${header.id}-${header.revision}-${header.itemDigest}'),
          future: _itemsFor(header),
          builder: (context, invoiceSnapshot) {
            final invoice = invoiceSnapshot.data;
            if (invoice == null) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (!_mayReadPrices) return _page(invoice, null);
            return StreamBuilder<PurchaseInvoicePriceSnapshot?>(
              stream: _priceStream,
              builder: (context, priceSnapshot) =>
                  _page(invoice, priceSnapshot.data),
            );
          },
        );
      },
    );
  }

  Widget _page(
    PurchaseInvoiceRead invoice,
    PurchaseInvoicePriceSnapshot? prices,
  ) {
    final verifiedPrices = _mayReadPrices && prices?.matches(invoice) == true
        ? prices
        : null;
    final verifiedDraft =
        _mayReadPrices && prices?.matchesProvisional(invoice) == true
        ? prices
        : null;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(
          title: Text(invoice.purchaseNumber),
          actions: [
            IconButton(
              key: const Key('purchase-pdf'),
              tooltip: _mayReadPrices
                  ? 'طباعة النسخة المخولة'
                  : 'طباعة نسخة المدير',
              onPressed: () => PurchaseInvoicePdfService.printInvoice(
                invoice: invoice,
                audienceRole: widget.role,
                protectedPrices: prices,
              ),
              icon: const Icon(Icons.picture_as_pdf_rounded),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _headerCard(invoice, verifiedPrices),
            const SizedBox(height: 12),
            Text(
              'المواد',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...invoice.items.map((item) => _itemCard(item, verifiedPrices)),
            const SizedBox(height: 12),
            _action(invoice, verifiedPrices ?? verifiedDraft),
            const SizedBox(height: 12),
            _amendmentSection(invoice, verifiedPrices ?? verifiedDraft),
            const SizedBox(height: 20),
            _timeline(invoice),
          ],
        ),
      ),
    );
  }

  Widget _headerCard(
    PurchaseInvoiceRead invoice,
    PurchaseInvoicePriceSnapshot? prices,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    invoice.status.label,
                    style: TextStyle(
                      color: invoice.status.color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(invoice.currency),
              ],
            ),
            const Divider(),
            _line('رقم الفاتورة (النظام)', invoice.purchaseNumber),
            _line('الفرع المستلم', invoice.receivingBranchName),
            _line('المورد', invoice.supplierName),
            _line('رقم فاتورة المورد / الورقية', invoice.supplierInvoiceNumber),
            _line('تاريخ فاتورة المورد', invoice.supplierInvoiceDate),
            if (invoice.generalManagerNotes.isNotEmpty)
              _line('ملاحظات المدير العام', invoice.generalManagerNotes),
            if (invoice.receiverNotes.isNotEmpty)
              _line('ملاحظات الاستلام', invoice.receiverNotes),
            if (_mayReadPrices && prices?.pricingState == 'confirmed') ...[
              const Divider(),
              _line(
                'الإجمالي المحمي',
                '${_number(prices?.invoiceTotal)} ${invoice.currency}',
              ),
              if ((prices?.accountingReference ?? '').isNotEmpty)
                _line('المرجع المحاسبي', prices!.accountingReference),
            ],
            if (invoice.postedWithUnresolvedOverride)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Chip(
                  avatar: Icon(Icons.warning_amber_rounded),
                  label: Text('رُحلت باستثناء مدقق ومواد غير محلولة'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _itemCard(
    PurchaseInvoiceItem item,
    PurchaseInvoicePriceSnapshot? prices,
  ) {
    final protectedItem = _mayReadPrices ? prices?.itemById(item.id) : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.displayName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Chip(label: Text(item.reviewLabel)),
              ],
            ),
            if (item.canonicalProductName.isNotEmpty && item.isUnmatched)
              Text('القيمة الأصلية: ${item.originalMaterialName}'),
            Text(
              'المطلوب: ${_number(item.orderedQuantity)} ${item.displayUnit}',
            ),
            if (item.receivedQuantity != null)
              Text(
                'المستلم: ${_number(item.receivedQuantity)} ${item.displayUnit}',
              ),
            if (item.missingQuantity > 0 || item.damagedQuantity > 0)
              Text(
                'ناقص: ${_number(item.missingQuantity)} — تالف: ${_number(item.damagedQuantity)}',
                style: const TextStyle(color: AppTheme.errorColor),
              ),
            if (item.discrepancyNotes.isNotEmpty)
              Text('ملاحظة: ${item.discrepancyNotes}'),
            if (protectedItem != null)
              Text(
                'السعر: ${_number(protectedItem.unitPrice)} — '
                'الإجمالي: ${_number(protectedItem.lineTotal)} ${prices!.currency}',
                key: Key('protected-price-${item.id}'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
          ],
        ),
      ),
    );
  }

  Widget _action(
    PurchaseInvoiceRead invoice,
    PurchaseInvoicePriceSnapshot? prices,
  ) {
    if (_submitting) return const Center(child: CircularProgressIndicator());
    if (widget.role == UserRole.manager &&
        widget.branchId == invoice.receivingBranchId &&
        invoice.status == PurchaseInvoiceStatus.pendingReceiverReview) {
      return FilledButton.icon(
        key: const Key('confirm-purchase-receipt'),
        onPressed: () => _confirmReceipt(invoice),
        icon: const Icon(Icons.inventory_rounded),
        label: const Text('تأكيد الكميات المستلمة'),
      );
    }
    if (widget.role == UserRole.collector &&
        invoice.status == PurchaseInvoiceStatus.pendingPriceEntry) {
      return FilledButton.icon(
        key: const Key('confirm-purchase-prices'),
        onPressed: () => _confirmPrices(invoice, prices),
        icon: const Icon(Icons.price_check_rounded),
        label: const Text('مراجعة واعتماد الأسعار'),
      );
    }
    if (widget.role == UserRole.accountant &&
        invoice.status == PurchaseInvoiceStatus.pendingAccountingEntry &&
        prices?.pricingState != 'confirmed') {
      return FilledButton.icon(
        key: const Key('confirm-purchase-prices'),
        onPressed: () => _confirmPrices(invoice, prices),
        icon: const Icon(Icons.price_check_rounded),
        label: const Text(
          '\u0645\u0631\u0627\u062c\u0639\u0629 \u0648\u0627\u0639\u062a\u0645\u0627\u062f \u0627\u0644\u0623\u0633\u0639\u0627\u0631',
        ),
      );
    }
    if (widget.role == UserRole.accountant &&
        invoice.status == PurchaseInvoiceStatus.pendingAccountingEntry) {
      return FilledButton.icon(
        key: const Key('post-purchase-accounting'),
        onPressed: () => _postAccounting(invoice),
        icon: const Icon(Icons.account_balance_rounded),
        label: const Text('الترحيل إلى النظام المحاسبي'),
      );
    }
    return const SizedBox.shrink();
  }

  Future<void> _confirmReceipt(PurchaseInvoiceRead invoice) async {
    final quantityControllers = {
      for (final item in invoice.items)
        item.id: TextEditingController(text: _number(item.orderedQuantity)),
    };
    final noteControllers = {
      for (final item in invoice.items) item.id: TextEditingController(),
    };
    final receiverNotes = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد الاستلام'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...invoice.items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.displayName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextField(
                          controller: quantityControllers[item.id],
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'المستلم (${item.displayUnit})',
                          ),
                        ),
                        TextField(
                          controller: noteControllers[item.id],
                          decoration: const InputDecoration(
                            labelText: 'ملاحظة فرق (اختيارية)',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                TextField(
                  controller: receiverNotes,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات مدير الفرع',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    if (accepted != true) {
      for (final controller in [
        ...quantityControllers.values,
        ...noteControllers.values,
        receiverNotes,
      ]) {
        controller.dispose();
      }
      return;
    }
    final inputs = <PurchaseReceiptInput>[];
    for (final item in invoice.items) {
      final received = double.tryParse(
        quantityControllers[item.id]!.text.trim(),
      );
      if (received == null || received < 0) {
        _message('تحقق من الكميات المستلمة.');
        return;
      }
      inputs.add(
        PurchaseReceiptInput(
          itemId: item.id,
          receivedQuantity: received,
          missingQuantity: (item.orderedQuantity - received)
              .clamp(0, double.infinity)
              .toDouble(),
          discrepancyNotes: noteControllers[item.id]!.text,
        ),
      );
    }
    await _run(
      () => _api.confirmReceipt(
        invoiceId: invoice.id,
        expectedRevision: invoice.revision,
        items: inputs,
        receiverNotes: receiverNotes.text,
        idempotencyKey: PurchaseInvoiceApiService.generateIdempotencyKey(),
      ),
    );
    for (final controller in [
      ...quantityControllers.values,
      ...noteControllers.values,
      receiverNotes,
    ]) {
      controller.dispose();
    }
  }

  Future<void> _confirmPrices(
    PurchaseInvoiceRead invoice,
    PurchaseInvoicePriceSnapshot? prices,
  ) async {
    final controllers = <String, TextEditingController>{};
    final suggestions = <String, ProductPriceLatest?>{};
    final priceService = ProductPriceService();
    for (final item in invoice.items) {
      ProductPriceLatest? latest;
      if (item.canonicalProductId.isNotEmpty &&
          item.canonicalUnitId.isNotEmpty) {
        latest = await priceService.fetchLatest(
          brandId: invoice.receivingBrandId,
          productId: item.canonicalProductId,
          unitId: item.canonicalUnitId,
          currency: invoice.currency,
        );
      }
      suggestions[item.id] = latest;
      final provisional = prices?.provisionalPrices[item.id];
      controllers[item.id] = TextEditingController(
        text: provisional?.toString() ?? latest?.price.toString() ?? '',
      );
    }
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('اعتماد الأسعار النهائية'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: invoice.items.map((item) {
                final suggestion = suggestions[item.id];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: controllers[item.id],
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: '${item.displayName} — ${item.displayUnit}',
                      helperText: suggestion == null
                          ? 'لا يوجد سعر محفوظ؛ يلزم إدخال صريح.'
                          : suggestion.sourceType == 'catalog_manual'
                          ? 'آخر سعر مقترح من تسعير دليل المواد '
                          : 'آخر سعر مقترح من ${suggestion.sourceInvoiceId} '
                                '${suggestion.changedAt == null ? '' : DateFormat('yyyy/MM/dd').format(suggestion.changedAt!)}',
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('اعتماد صريح'),
          ),
        ],
      ),
    );
    if (accepted != true) {
      for (final controller in controllers.values) {
        controller.dispose();
      }
      return;
    }
    final inputs = <PurchasePriceInput>[];
    for (final item in invoice.items) {
      final value = double.tryParse(controllers[item.id]!.text.trim());
      if (value == null || value < 0) {
        _message('يجب إدخال سعر صالح لكل مادة.');
        return;
      }
      inputs.add(PurchasePriceInput(itemId: item.id, unitPrice: value));
    }
    await _run(
      () => _api.confirmPrices(
        invoiceId: invoice.id,
        expectedRevision: invoice.revision,
        items: inputs,
        idempotencyKey: PurchaseInvoiceApiService.generateIdempotencyKey(),
      ),
    );
    for (final controller in controllers.values) {
      controller.dispose();
    }
  }

  Future<void> _postAccounting(PurchaseInvoiceRead invoice) async {
    final tasks = await _service.loadInvoiceReviewTasks(invoice.id);
    final unresolved = tasks
        .where(
          (task) => !const {
            'linked_material',
            'newly_created_material',
            'synchronized',
          }.contains(task.status),
        )
        .toList();
    if (!mounted) return;
    final reference = TextEditingController();
    final notes = TextEditingController();
    final overrideReason = TextEditingController();
    var useOverride = false;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('الترحيل المحاسبي'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: reference,
                  decoration: const InputDecoration(
                    labelText: 'المرجع المحاسبي',
                  ),
                ),
                TextField(
                  controller: notes,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات المحاسب (محمية)',
                  ),
                ),
                if (unresolved.isNotEmpty) ...[
                  CheckboxListTile(
                    value: useOverride,
                    title: Text(
                      'استخدام استثناء مدقق (${unresolved.length} مواد غير محلولة)',
                    ),
                    onChanged: (value) =>
                        setDialogState(() => useOverride = value == true),
                  ),
                  if (useOverride)
                    TextField(
                      key: const Key('purchase-override-reason'),
                      controller: overrideReason,
                      decoration: const InputDecoration(
                        labelText: 'سبب الاستثناء الإلزامي',
                      ),
                    ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('ترحيل'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true ||
        reference.text.trim().isEmpty ||
        (unresolved.isNotEmpty &&
            (!useOverride || overrideReason.text.trim().isEmpty))) {
      if (accepted == true) {
        _message('أكمل المرجع وسبب الاستثناء عند استخدامه.');
      }
      return;
    }
    await _run(
      () => _api.postAccounting(
        invoiceId: invoice.id,
        expectedRevision: invoice.revision,
        accountingReference: reference.text,
        accountantNotes: notes.text,
        overrideUnresolvedMaterials: useOverride,
        overrideReason: overrideReason.text,
        idempotencyKey: PurchaseInvoiceApiService.generateIdempotencyKey(),
      ),
    );
    reference.dispose();
    notes.dispose();
    overrideReason.dispose();
  }

  Widget _amendmentSection(
    PurchaseInvoiceRead invoice,
    PurchaseInvoicePriceSnapshot? prices,
  ) {
    if (!invoice.hasPendingAmendment) {
      if (!_mayRequestAmendment(invoice)) return const SizedBox.shrink();
      return OutlinedButton.icon(
        key: const Key('request-purchase-amendment'),
        onPressed: _submitting
            ? null
            : () => _requestAmendment(invoice, prices),
        icon: const Icon(Icons.edit_note_rounded),
        label: const Text('طلب تعديل الفاتورة'),
      );
    }
    return StreamBuilder<PurchaseInvoiceAmendment?>(
      stream: _service.watchAmendment(invoice.openAmendmentId),
      builder: (context, snapshot) {
        final amendment = snapshot.data;
        if (amendment == null) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text('جارٍ تحميل طلب التعديل...'),
            ),
          );
        }
        return _amendmentCard(invoice, amendment);
      },
    );
  }

  bool _mayRequestAmendment(PurchaseInvoiceRead invoice) {
    if (invoice.status != PurchaseInvoiceStatus.pendingReceiverReview) {
      return false;
    }
    if (widget.role == UserRole.manager) {
      return widget.branchId == invoice.receivingBranchId;
    }
    return _mayReadPrices;
  }

  Widget _amendmentCard(
    PurchaseInvoiceRead invoice,
    PurchaseInvoiceAmendment amendment,
  ) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final mayDecide =
        amendment.status == 'pending' &&
        amendment.requiredApprovers.any((actor) => actor.uid == currentUid) &&
        !amendment.approvedBy(currentUid);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.edit_note_rounded),
                SizedBox(width: 8),
                Text(
                  'طلب تعديل الفاتورة',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('الطلب بواسطة: ${amendment.requestedByName}'),
            Text('السبب: ${amendment.reason}'),
            if (amendment.includesProtectedPriceChanges)
              Text(
                _mayReadPrices
                    ? 'يتضمن الطلب تعديلاً مالياً محمياً.'
                    : 'يتضمن الطلب تعديلاً مالياً محمياً دون عرض القيم.',
              ),
            const SizedBox(height: 8),
            ...amendment.changes.entries.map(
              (entry) => Text(
                '${_amendmentFieldLabel(entry.key)}: '
                '${entry.value['before'] ?? '-'} ← ${entry.value['after'] ?? '-'}',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'تمت الموافقة: '
              '${amendment.approvals.map((actor) => actor.name).where((name) => name.isNotEmpty).join('، ')}',
            ),
            Text(
              'بانتظار: '
              '${amendment.pendingApprovers.map((actor) => actor.name).where((name) => name.isNotEmpty).join('، ')}',
            ),
            if (amendment.rejectionReason.isNotEmpty)
              Text('سبب الرفض: ${amendment.rejectionReason}'),
            if (_mayReadPrices && amendment.includesProtectedPriceChanges)
              _protectedAmendmentPrices(amendment),
            if (mayDecide) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    key: const Key('approve-purchase-amendment'),
                    onPressed: _submitting
                        ? null
                        : () => _decideAmendment(
                            invoice,
                            amendment,
                            decision: 'approve',
                          ),
                    child: const Text('موافقة'),
                  ),
                  OutlinedButton(
                    key: const Key('reject-purchase-amendment'),
                    onPressed: _submitting
                        ? null
                        : () => _rejectAmendment(invoice, amendment),
                    child: const Text('رفض'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _protectedAmendmentPrices(PurchaseInvoiceAmendment amendment) =>
      StreamBuilder<PurchaseInvoiceAmendmentPrice?>(
        stream: _service.watchProtectedAmendmentPrices(amendment.id),
        builder: (context, snapshot) {
          final values = snapshot.data;
          if (values == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: values.items
                  .map(
                    (item) => Text(
                      'سعر محمي: ${_number(item.oldUnitPrice)} ← '
                      '${_number(item.newUnitPrice)} ${values.currency}',
                    ),
                  )
                  .toList(growable: false),
            ),
          );
        },
      );

  String _amendmentFieldLabel(String field) => switch (field) {
    'supplier_name' => 'المورد',
    'supplier_invoice_number' => 'رقم فاتورة المورد',
    'supplier_invoice_date' => 'تاريخ فاتورة المورد',
    'general_manager_notes' => 'ملاحظات المدير العام',
    _ => field,
  };

  Future<void> _requestAmendment(
    PurchaseInvoiceRead invoice,
    PurchaseInvoicePriceSnapshot? prices,
  ) async {
    final reason = TextEditingController();
    final supplier = TextEditingController(text: invoice.supplierName);
    final supplierNumber = TextEditingController(
      text: invoice.supplierInvoiceNumber,
    );
    final supplierDate = TextEditingController(
      text: invoice.supplierInvoiceDate,
    );
    final notes = TextEditingController(text: invoice.generalManagerNotes);
    final priceControllers = <String, TextEditingController>{
      if (_mayReadPrices)
        for (final item in invoice.items)
          item.id: TextEditingController(
            text: prices?.provisionalPrices[item.id]?.toString() ?? '',
          ),
    };
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('طلب تعديل الفاتورة'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: reason,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'سبب التعديل *'),
                ),
                TextField(
                  controller: supplier,
                  decoration: const InputDecoration(labelText: 'المورد'),
                ),
                TextField(
                  controller: supplierNumber,
                  decoration: const InputDecoration(
                    labelText: 'رقم فاتورة المورد',
                  ),
                ),
                TextField(
                  controller: supplierDate,
                  decoration: const InputDecoration(
                    labelText: 'تاريخ فاتورة المورد (YYYY-MM-DD)',
                  ),
                ),
                TextField(
                  controller: notes,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات المدير العام',
                  ),
                ),
                if (_mayReadPrices) ...[
                  const SizedBox(height: 12),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'تعديل السعر المحمي (اختياري)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  ...invoice.items.map(
                    (item) => TextField(
                      controller: priceControllers[item.id],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: '${item.displayName} — ${item.displayUnit}',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('إرسال للموافقة'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      final priceItems = <PurchaseAmendmentPriceInput>[];
      for (final item in invoice.items) {
        final controller = priceControllers[item.id];
        if (controller == null || controller.text.trim().isEmpty) continue;
        final value = double.tryParse(controller.text.trim());
        final original = prices?.provisionalPrices[item.id];
        if (value == null || value < 0) {
          _message('تحقق من قيمة السعر المحمي.');
          return;
        }
        if (value != original) {
          priceItems.add(
            PurchaseAmendmentPriceInput(itemId: item.id, unitPrice: value),
          );
        }
      }
      final hasHeaderChange =
          supplier.text.trim() != invoice.supplierName ||
          supplierNumber.text.trim() != invoice.supplierInvoiceNumber ||
          supplierDate.text.trim() != invoice.supplierInvoiceDate ||
          notes.text.trim() != invoice.generalManagerNotes;
      if (reason.text.trim().isEmpty ||
          (!hasHeaderChange && priceItems.isEmpty)) {
        _message('أدخل سبباً وتغييراً واحداً على الأقل.');
      } else {
        await _run(
          () => _api.createAmendment(
            invoiceId: invoice.id,
            expectedRevision: invoice.revision,
            reason: reason.text,
            supplierName: supplier.text.trim() == invoice.supplierName
                ? null
                : supplier.text,
            supplierInvoiceNumber:
                supplierNumber.text.trim() == invoice.supplierInvoiceNumber
                ? null
                : supplierNumber.text,
            supplierInvoiceDate:
                supplierDate.text.trim() == invoice.supplierInvoiceDate
                ? null
                : supplierDate.text,
            generalManagerNotes:
                notes.text.trim() == invoice.generalManagerNotes
                ? null
                : notes.text,
            priceItems: priceItems.isEmpty ? null : priceItems,
            idempotencyKey: PurchaseInvoiceApiService.generateIdempotencyKey(),
          ),
        );
      }
    }
    for (final controller in [
      reason,
      supplier,
      supplierNumber,
      supplierDate,
      notes,
      ...priceControllers.values,
    ]) {
      controller.dispose();
    }
  }

  Future<void> _rejectAmendment(
    PurchaseInvoiceRead invoice,
    PurchaseInvoiceAmendment amendment,
  ) async {
    final reason = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('رفض طلب التعديل'),
        content: TextField(
          controller: reason,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'سبب الرفض *'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('تأكيد الرفض'),
          ),
        ],
      ),
    );
    if (accepted == true && reason.text.trim().isNotEmpty) {
      await _decideAmendment(
        invoice,
        amendment,
        decision: 'reject',
        reason: reason.text,
      );
    } else if (accepted == true) {
      _message('سبب الرفض مطلوب.');
    }
    reason.dispose();
  }

  Future<void> _decideAmendment(
    PurchaseInvoiceRead invoice,
    PurchaseInvoiceAmendment amendment, {
    required String decision,
    String? reason,
  }) => _run(
    () => _api.decideAmendment(
      invoiceId: invoice.id,
      amendmentId: amendment.id,
      expectedRevision: invoice.revision,
      decision: decision,
      reason: reason,
      idempotencyKey: PurchaseInvoiceApiService.generateIdempotencyKey(),
    ),
  );

  Widget _timeline(PurchaseInvoiceRead invoice) {
    final fixture = widget.fixtureInvoice != null;
    if (fixture) {
      return _eventList(
        invoice.history
            .map(
              (event) => {
                'message': event.message,
                'actor_name': event.actorName,
                'created_at': event.timestamp,
              },
            )
            .toList(),
      );
    }
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _service.watchEvents(invoice.id, invoice.receivingBranchId),
      builder: (context, snapshot) => _eventList(snapshot.data ?? const []),
    );
  }

  Widget _eventList(List<Map<String, dynamic>> events) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'سجل الإجراءات',
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      ...events.map((event) {
        final rawTime = event['created_at'] ?? event['timestamp'];
        final time = rawTime is Timestamp
            ? rawTime.toDate()
            : rawTime is DateTime
            ? rawTime
            : rawTime is String
            ? DateTime.tryParse(rawTime)
            : null;
        return ListTile(
          leading: const Icon(Icons.history_rounded),
          title: Text(event['message']?.toString() ?? ''),
          subtitle: Text(
            [
              event['actor_name']?.toString() ?? '',
              if (time != null) DateFormat('yyyy/MM/dd HH:mm').format(time),
            ].where((value) => value.isNotEmpty).join(' — '),
          ),
        );
      }),
    ],
  );

  Future<void> _run(Future<Object?> Function() operation) async {
    setState(() => _submitting = true);
    try {
      await operation();
      if (mounted) _message('تم حفظ الإجراء بنجاح.');
    } catch (error) {
      if (mounted) _message(error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _line(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text('$label: $value'),
    );
  }

  String _number(dynamic value) {
    final number = value is num ? value.toDouble() : null;
    if (number == null) return '-';
    return number == number.roundToDouble()
        ? number.toInt().toString()
        : number.toStringAsFixed(2);
  }

  void _message(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
