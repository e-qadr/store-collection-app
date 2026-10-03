import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/models/product_price_model.dart';
import 'package:store_collection_app/models/purchase_invoice_model.dart';
import 'package:store_collection_app/models/purchase_invoice_price_model.dart';
import 'package:store_collection_app/services/product_price_service.dart';
import 'package:store_collection_app/services/product_catalog_service.dart';
import 'package:store_collection_app/services/purchase_invoice_api_service.dart';
import 'package:store_collection_app/services/purchase_invoice_pdf_service.dart';
import 'package:store_collection_app/services/purchase_invoice_service.dart';
import 'package:store_collection_app/screens/purchase_invoices/purchase_catalog_picker.dart';
import 'package:store_collection_app/theme/app_theme.dart';

/// Keeps a failed Firestore read distinct from an actual missing Purchase
/// document. In particular, a protected-price denial must never turn the
/// public invoice into a false "not found" result.
String purchaseInvoiceDetailLoadErrorText(
  Object error, {
  String fallback = 'تعذر تحميل تفاصيل فاتورة المشتريات.',
  String missing = 'فاتورة المشتريات غير موجودة.',
}) {
  if (error is FirebaseException) {
    return switch (error.code) {
      'permission-denied' => 'لا تملك صلاحية عرض فاتورة المشتريات هذه.',
      'not-found' => missing,
      'unavailable' ||
      'deadline-exceeded' => 'تعذر الاتصال بالخدمة. حاول لاحقًا.',
      _ => fallback,
    };
  }
  if (error is StateError) return missing;
  return fallback;
}

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

class _PurchaseAmendmentItemDraft {
  final PurchaseInvoiceItem original;
  final TextEditingController quantity;
  final TextEditingController notes;
  CatalogSelection? selection;

  _PurchaseAmendmentItemDraft(this.original)
    : quantity = TextEditingController(
        text:
            original.orderedQuantity == original.orderedQuantity.roundToDouble()
            ? original.orderedQuantity.toInt().toString()
            : original.orderedQuantity.toString(),
      ),
      notes = TextEditingController(text: original.lineNotes);

  String get displayName => selection?.product.name ?? original.displayName;
  String get displayUnit =>
      selection?.unit.displayValue ?? original.displayUnit;

  PurchaseAmendmentItemChangeInput? toInput() {
    final nextQuantity = double.tryParse(quantity.text.trim());
    if (nextQuantity == null || !nextQuantity.isFinite || nextQuantity <= 0) {
      throw const FormatException();
    }
    final nextNotes = notes.text.trim();
    final selected = selection;
    final productChanged =
        selected != null && selected.product.id != original.canonicalProductId;
    final unitChanged =
        selected != null && selected.unit.id != original.canonicalUnitId;
    final quantityChanged = nextQuantity != original.orderedQuantity;
    final notesChanged = nextNotes != original.lineNotes;
    if (!productChanged && !unitChanged && !quantityChanged && !notesChanged) {
      return null;
    }
    return PurchaseAmendmentItemChangeInput(
      itemId: original.id,
      productId: selected?.product.id,
      unitId: selected?.unit.id,
      orderedQuantity: quantityChanged ? nextQuantity : null,
      lineNotes: notesChanged ? nextNotes : null,
    );
  }

  void dispose() {
    quantity.dispose();
    notes.dispose();
  }
}

class _PurchaseInvoiceDetailsScreenState
    extends State<PurchaseInvoiceDetailsScreen> {
  late final PurchaseInvoiceService _service = PurchaseInvoiceService();
  late final PurchaseInvoiceApiService _api = PurchaseInvoiceApiService();
  late final ProductCatalogService _catalog = ProductCatalogService();
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
      _invoiceFuture = _service.loadInvoiceWithItems(header.documentId);
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
        if (headerSnapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Text(
                purchaseInvoiceDetailLoadErrorText(headerSnapshot.error!),
              ),
            ),
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
            if (invoiceSnapshot.hasError) {
              return Scaffold(
                body: Center(
                  child: Text(
                    purchaseInvoiceDetailLoadErrorText(
                      invoiceSnapshot.error!,
                      fallback: 'تعذر تحميل أصناف فاتورة المشتريات.',
                      missing: 'أصناف فاتورة المشتريات غير موجودة.',
                    ),
                  ),
                ),
              );
            }
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
        bottomNavigationBar: _footerActions(
          invoice,
          verifiedPrices ?? verifiedDraft,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 142),
          children: [
            _headerCard(invoice, verifiedPrices),
            const SizedBox(height: 12),
            _sectionTitle(
              icon: Icons.inventory_2_outlined,
              title: 'مواد الفاتورة',
              trailing: '${invoice.items.length} مواد',
            ),
            const SizedBox(height: 8),
            ...invoice.items.map((item) => _itemCard(item, verifiedPrices)),
            _amendmentSection(invoice, verifiedPrices ?? verifiedDraft),
            const SizedBox(height: 16),
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
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: invoice.status.color.withValues(alpha: 0.07),
                border: Border(
                  bottom: BorderSide(
                    color: invoice.status.color.withValues(alpha: 0.18),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: invoice.status.color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.receipt_long_rounded,
                      color: invoice.status.color,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'فاتورة مشتريات',
                          style: TextStyle(color: AppTheme.textHint),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          invoice.purchaseNumber,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                  _statusPill(invoice),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (invoice.supplierName.isNotEmpty) ...[
              Text(
                invoice.supplierName,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (invoice.supplierInvoiceNumber.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    'فاتورة المورد: ${invoice.supplierInvoiceNumber}',
                    style: const TextStyle(color: AppTheme.textHint),
                  ),
                ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: _headerFact(
                    icon: Icons.storefront_rounded,
                    label: 'الفرع المستلم',
                    value: invoice.receivingBranchName.isEmpty
                        ? 'غير محدد'
                        : invoice.receivingBranchName,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _headerFact(
                    icon: Icons.calendar_month_rounded,
                    label: 'تاريخ المورد',
                    value: invoice.supplierInvoiceDate.isEmpty
                        ? 'غير محدد'
                        : invoice.supplierInvoiceDate,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _headerFact(
                    icon: Icons.payments_outlined,
                    label: 'العملة',
                    value: invoice.currency.isEmpty ? '-' : invoice.currency,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Text(
              'ملخص الفاتورة',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '${invoice.itemCount} مواد مطلوبة • ${invoice.currentResponsibleParty}',
              style: const TextStyle(color: AppTheme.textHint),
            ),
            if (invoice.generalManagerNotes.isNotEmpty)
              _noteLine('ملاحظات المدير العام', invoice.generalManagerNotes),
            if (invoice.receiverNotes.isNotEmpty)
              _noteLine('ملاحظات الاستلام', invoice.receiverNotes),
            if (_mayReadPrices && prices?.pricingState == 'confirmed') ...[
              const SizedBox(height: 12),
              _protectedSummary(invoice, prices!),
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
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: AppTheme.primaryOlive.withValues(alpha: 0.1),
                  foregroundColor: AppTheme.primaryOlive,
                  child: Text('${item.lineNumber}'),
                ),
                const SizedBox(width: 10),
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
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('القيمة الأصلية: ${item.originalMaterialName}'),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _itemFact(
                    label: 'المطلوب',
                    value:
                        '${_number(item.orderedQuantity)} ${item.displayUnit}',
                  ),
                ),
                if (item.receivedQuantity != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _itemFact(
                      label: 'المستلم',
                      value:
                          '${_number(item.receivedQuantity)} ${item.displayUnit}',
                    ),
                  ),
                ],
              ],
            ),
            if (item.missingQuantity > 0 || item.damagedQuantity > 0)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'ناقص: ${_number(item.missingQuantity)} — تالف: ${_number(item.damagedQuantity)}',
                  style: const TextStyle(color: AppTheme.errorColor),
                ),
              ),
            if (item.discrepancyNotes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('ملاحظة: ${item.discrepancyNotes}'),
              ),
            if (protectedItem != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'السعر: ${_number(protectedItem.unitPrice)} — '
                  'الإجمالي: ${_number(protectedItem.lineTotal)} ${prices!.currency}',
                  key: Key('protected-price-${item.id}'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            if (item.lineNotes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  item.lineNotes,
                  style: const TextStyle(color: AppTheme.textHint),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle({
    required IconData icon,
    required String title,
    String? trailing,
  }) => Row(
    children: [
      Icon(icon, color: AppTheme.primaryOlive),
      const SizedBox(width: 8),
      Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      const Spacer(),
      if (trailing != null)
        Text(trailing, style: const TextStyle(color: AppTheme.textHint)),
    ],
  );

  Widget _statusPill(PurchaseInvoiceRead invoice) => Container(
    constraints: const BoxConstraints(maxWidth: 128),
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: invoice.status.color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      invoice.status.label,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: invoice.status.color,
        fontSize: 11,
        fontWeight: FontWeight.bold,
      ),
    ),
  );

  Widget _headerFact({
    required IconData icon,
    required String label,
    required String value,
  }) => Container(
    constraints: const BoxConstraints(minHeight: 82),
    padding: const EdgeInsets.all(9),
    decoration: BoxDecoration(
      color: AppTheme.surfaceColor,
      border: Border.all(color: AppTheme.dividerColor),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: AppTheme.primaryOlive),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppTheme.textHint),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ],
    ),
  );

  Widget _itemFact({required String label, required String value}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: AppTheme.primaryOlive.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppTheme.textHint, fontSize: 11),
        ),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    ),
  );

  Widget _noteLine(String label, String text) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Text('$label: $text'),
  );

  Widget _protectedSummary(
    PurchaseInvoiceRead invoice,
    PurchaseInvoicePriceSnapshot prices,
  ) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppTheme.successColor.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'الإجمالي المعتمد: ${_number(prices.invoiceTotal)} ${invoice.currency}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        if (prices.accountingReference.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('المرجع المحاسبي: ${prices.accountingReference}'),
        ],
      ],
    ),
  );

  Widget _footerActions(
    PurchaseInvoiceRead invoice,
    PurchaseInvoicePriceSnapshot? prices,
  ) {
    final action = _action(invoice, prices);
    final hasAction = action is! SizedBox;
    final mayRequestAmendment =
        !invoice.hasPendingAmendment && _mayRequestAmendment(invoice);
    if (!hasAction && !mayRequestAmendment) return const SizedBox.shrink();
    final prompt = _actionPrompt(invoice, hasAction);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: const BoxDecoration(
          color: AppTheme.cardColor,
          border: Border(top: BorderSide(color: AppTheme.dividerColor)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  hasAction ? Icons.task_alt_rounded : Icons.edit_note_rounded,
                  size: 18,
                  color: hasAction
                      ? invoice.status.color
                      : AppTheme.warningColor,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    prompt,
                    style: const TextStyle(
                      color: AppTheme.textHint,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            if (hasAction && mayRequestAmendment)
              Row(
                children: [
                  Expanded(child: action),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('request-purchase-amendment'),
                      onPressed: _submitting
                          ? null
                          : () => _requestAmendment(invoice, prices),
                      icon: const Icon(Icons.edit_note_rounded),
                      label: const Text('طلب تعديل'),
                    ),
                  ),
                ],
              )
            else if (hasAction)
              SizedBox(width: double.infinity, child: action)
            else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const Key('request-purchase-amendment'),
                  onPressed: _submitting
                      ? null
                      : () => _requestAmendment(invoice, prices),
                  icon: const Icon(Icons.edit_note_rounded),
                  label: const Text('طلب تعديل الفاتورة'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _actionPrompt(PurchaseInvoiceRead invoice, bool hasAction) {
    if (hasAction) {
      return switch (invoice.status) {
        PurchaseInvoiceStatus.pendingReceiverReview =>
          'راجع الكميات الفعلية ثم أكد الاستلام أو سجّل الفروقات.',
        PurchaseInvoiceStatus.pendingPriceEntry =>
          'أدخل سعر كل مادة واعتمده لتنتقل الفاتورة إلى المحاسب.',
        PurchaseInvoiceStatus.pendingAccountingEntry =>
          'أكمل الأسعار إن لزم، ثم أدخل المرجع المحاسبي ورحّل الفاتورة.',
        _ => 'يوجد إجراء متاح لك على هذه الفاتورة.',
      };
    }
    return switch (invoice.status) {
      PurchaseInvoiceStatus.pendingReceiverReview =>
        'بانتظار مدير الفرع المستلم لتأكيد الكميات.',
      PurchaseInvoiceStatus.pendingPriceEntry =>
        'بانتظار المدير العام لاعتماد الأسعار.',
      PurchaseInvoiceStatus.pendingAccountingEntry =>
        'بانتظار المحاسب لإدخال المرجع والترحيل.',
      PurchaseInvoiceStatus.postedToAccounting =>
        'اكتملت الفاتورة وتم ترحيلها محاسبياً.',
      PurchaseInvoiceStatus.unknown =>
        'تعذر تحديد الإجراء التالي لهذه الفاتورة.',
    };
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
      return const SizedBox.shrink();
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
    if (!const {
      PurchaseInvoiceStatus.pendingReceiverReview,
      PurchaseInvoiceStatus.pendingPriceEntry,
      PurchaseInvoiceStatus.pendingAccountingEntry,
    }.contains(invoice.status)) {
      return false;
    }
    if (widget.role == UserRole.manager) {
      return widget.branchId == invoice.receivingBranchId;
    }
    // The approval record is deliberately fixed to the originating General
    // Manager, the receiving manager, and an accountant. Admins retain full
    // visibility but do not bypass that required three-party workflow.
    return const {
      UserRole.collector,
      UserRole.accountant,
    }.contains(widget.role);
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
            if (amendment.hasItemChanges) _amendmentItems(amendment),
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

  Widget _amendmentItems(PurchaseInvoiceAmendment amendment) =>
      StreamBuilder<List<PurchaseInvoiceAmendmentItem>>(
        stream: _service.watchAmendmentItems(amendment.id),
        builder: (context, snapshot) {
          final items = snapshot.data ?? const [];
          if (items.isEmpty) {
            return const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('يتضمن الطلب تعديلات تشغيلية على المواد.'),
            );
          }
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'تعديلات المواد المقترحة',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                ...items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${item.before.productName} (${item.before.unitValue}، '
                      '${_number(item.before.orderedQuantity)}) ← '
                      '${item.after.productName} (${item.after.unitValue}، '
                      '${_number(item.after.orderedQuantity)})',
                    ),
                  ),
                ),
              ],
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
    final itemDrafts =
        invoice.status == PurchaseInvoiceStatus.pendingReceiverReview
        ? invoice.items
              .where(
                (item) =>
                    !item.isUnmatched && item.canonicalProductId.isNotEmpty,
              )
              .map(_PurchaseAmendmentItemDraft.new)
              .toList(growable: false)
        : const <_PurchaseAmendmentItemDraft>[];
    final priceControllers = <String, TextEditingController>{
      if (_mayReadPrices)
        for (final item in invoice.items)
          item.id: TextEditingController(
            text: prices?.provisionalPrices[item.id]?.toString() ?? '',
          ),
    };
    void disposeDraftControllers() {
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
      for (final draft in itemDrafts) {
        draft.dispose();
      }
    }

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
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
                    decoration: const InputDecoration(
                      labelText: 'سبب التعديل *',
                    ),
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
                  if (itemDrafts.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'تعديل المواد والوحدات والكميات قبل الاستلام',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...itemDrafts.map(
                      (draft) => Card(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '${draft.displayName} — ${draft.displayUnit}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: TextButton.icon(
                                  onPressed: () async {
                                    final selection =
                                        await showPurchaseCatalogPicker(
                                          dialogContext,
                                          brandId: invoice.receivingBrandId,
                                          service: _catalog,
                                        );
                                    if (selection != null) {
                                      setDialogState(
                                        () => draft.selection = selection,
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.inventory_2_outlined),
                                  label: const Text(
                                    'اختيار مادة أو وحدة بديلة',
                                  ),
                                ),
                              ),
                              TextField(
                                controller: draft.quantity,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'الكمية',
                                ),
                              ),
                              TextField(
                                controller: draft.notes,
                                maxLines: 2,
                                decoration: const InputDecoration(
                                  labelText: 'ملاحظة البند (اختيارية)',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
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
                          labelText:
                              '${item.displayName} — ${item.displayUnit}',
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
          disposeDraftControllers();
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
      final itemChanges = <PurchaseAmendmentItemChangeInput>[];
      try {
        for (final draft in itemDrafts) {
          final change = draft.toInput();
          if (change != null) itemChanges.add(change);
        }
      } on FormatException {
        _message('تحقق من الكمية المقترحة لكل مادة.');
        disposeDraftControllers();
        return;
      }
      if (reason.text.trim().isEmpty ||
          (!hasHeaderChange && priceItems.isEmpty && itemChanges.isEmpty)) {
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
            itemChanges: itemChanges.isEmpty ? null : itemChanges,
            idempotencyKey: PurchaseInvoiceApiService.generateIdempotencyKey(),
          ),
        );
      }
    }
    disposeDraftControllers();
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
