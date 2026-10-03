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

class _PurchaseEventPresentation {
  final IconData icon;
  final Color color;

  const _PurchaseEventPresentation({required this.icon, required this.color});
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

  String get _currentUid {
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? '';
    } on FirebaseException {
      // Widget previews and tests may render this screen without Firebase.
      return '';
    }
  }

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
            _headerCard(invoice),
            const SizedBox(height: 12),
            _sectionTitle(
              icon: Icons.inventory_2_outlined,
              title: 'مواد الفاتورة',
              trailing: '${invoice.items.length} مواد',
            ),
            const SizedBox(height: 8),
            ...invoice.items.map((item) => _itemCard(item, verifiedPrices)),
            const SizedBox(height: 8),
            _invoiceSummaryCard(invoice, verifiedPrices),
            _amendmentSection(invoice, verifiedPrices ?? verifiedDraft),
            const SizedBox(height: 16),
            _timeline(invoice),
          ],
        ),
      ),
    );
  }

  Widget _headerCard(PurchaseInvoiceRead invoice) {
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
          ],
        ),
      ),
    );
  }

  Widget _invoiceSummaryCard(
    PurchaseInvoiceRead invoice,
    PurchaseInvoicePriceSnapshot? prices,
  ) {
    final hasConfirmedPrices =
        _mayReadPrices && prices?.pricingState == 'confirmed';
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.insights_rounded, color: AppTheme.primaryOlive),
                SizedBox(width: 8),
                Text(
                  'ملخص الفاتورة',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _summaryFact(
                    icon: Icons.inventory_2_outlined,
                    label: 'عدد المواد',
                    value: '${invoice.itemCount} مواد',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _summaryFact(
                    icon: Icons.person_pin_circle_outlined,
                    label: 'الإجراء التالي',
                    value: invoice.currentResponsibleParty,
                  ),
                ),
              ],
            ),
            if (hasConfirmedPrices) ...[
              const SizedBox(height: 8),
              _protectedSummary(invoice, prices!),
            ],
            if (invoice.generalManagerNotes.isNotEmpty)
              _summaryNote(
                icon: Icons.admin_panel_settings_outlined,
                label: 'ملاحظات المدير العام',
                text: invoice.generalManagerNotes,
              ),
            if (invoice.receiverNotes.isNotEmpty)
              _summaryNote(
                icon: Icons.local_shipping_outlined,
                label: 'ملاحظات الاستلام',
                text: invoice.receiverNotes,
              ),
            if (invoice.postedWithUnresolvedOverride)
              const Padding(
                padding: EdgeInsets.only(top: 10),
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

  Widget _summaryFact({
    required IconData icon,
    required String label,
    required String value,
  }) => Container(
    constraints: const BoxConstraints(minHeight: 82),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: AppTheme.primaryOlive.withValues(alpha: 0.055),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTheme.primaryOlive.withValues(alpha: 0.13)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 17, color: AppTheme.primaryOlive),
        const SizedBox(height: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppTheme.textHint),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );

  Widget _summaryNote({
    required IconData icon,
    required String label,
    required String text,
  }) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: AppTheme.surfaceColor,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppTheme.dividerColor),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppTheme.primaryOlive),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: DefaultTextStyle.of(context).style,
              children: [
                TextSpan(
                  text: '$label\n',
                  style: const TextStyle(
                    color: AppTheme.textHint,
                    fontSize: 11,
                  ),
                ),
                TextSpan(text: text),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _protectedSummary(
    PurchaseInvoiceRead invoice,
    PurchaseInvoicePriceSnapshot prices,
  ) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppTheme.successColor.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.18)),
    ),
    child: Row(
      children: [
        const Icon(Icons.verified_rounded, color: AppTheme.successColor),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'الإجمالي المعتمد',
                style: TextStyle(fontSize: 11, color: AppTheme.textHint),
              ),
              const SizedBox(height: 2),
              Text(
                '${_number(prices.invoiceTotal)} ${invoice.currency}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
        if (prices.accountingReference.isNotEmpty) ...[
          Container(width: 1, height: 34, color: AppTheme.dividerColor),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'المرجع المحاسبي',
                  style: TextStyle(fontSize: 11, color: AppTheme.textHint),
                ),
                const SizedBox(height: 2),
                Text(
                  prices.accountingReference,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
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
    final mayEditInvoice =
        !invoice.hasPendingAmendment && _mayRequestAmendment(invoice);
    if (!hasAction && !mayEditInvoice) return const SizedBox.shrink();
    final prompt = !hasAction && mayEditInvoice
        ? 'يمكنك تعديل الفاتورة. سيُحفظ التعديل مباشرة أو ينتظر اعتماد من سبق له العمل عليها.'
        : _actionPrompt(invoice, hasAction);
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
            if (hasAction && mayEditInvoice)
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
                      label: const Text('تعديل الفاتورة'),
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
                  label: const Text('تعديل الفاتورة'),
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
    final uid = _currentUid;
    if (uid.isNotEmpty) return invoice.amendmentParticipantUids.contains(uid);
    // Fixtures and offline previews do not have an authenticated user. Keep
    // the role-only fallback there; the server remains the authority.
    return widget.role != UserRole.admin &&
        (widget.role != UserRole.manager ||
            widget.branchId == invoice.receivingBranchId);
  }

  Widget _amendmentCard(
    PurchaseInvoiceRead invoice,
    PurchaseInvoiceAmendment amendment,
  ) {
    final currentUid = _currentUid;
    final mayDecide =
        amendment.status == 'pending' &&
        amendment.requiredApprovers.any((actor) => actor.uid == currentUid) &&
        !amendment.approvedBy(currentUid);
    final mayApplyImmediately =
        amendment.status == 'pending' &&
        currentUid.isNotEmpty &&
        amendment.approvedBy(currentUid) &&
        amendment.pendingApprovers.isEmpty;
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
                  'تعديل فاتورة المشتريات',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('التعديل بواسطة: ${amendment.requestedByName}'),
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
            if (mayApplyImmediately) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _submitting
                    ? null
                    : () => _decideAmendment(
                        invoice,
                        amendment,
                        decision: 'apply',
                      ),
                icon: const Icon(Icons.save_alt_rounded),
                label: const Text('تطبيق التعديل الآن'),
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
          title: const Text('تعديل فاتورة المشتريات'),
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
                      helperText:
                          'سيُطبق مباشرة إن كنت الطرف الوحيد الذي عمل على الفاتورة.',
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
              child: const Text('حفظ التعديل'),
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
        await _run(() async {
          final created = await _api.createAmendment(
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
          );
          if (created.amendmentRequiredApproverCount == 1 &&
              created.amendmentApprovalCount == 1 &&
              created.amendmentId.isNotEmpty) {
            await _api.decideAmendment(
              invoiceId: invoice.id,
              amendmentId: created.amendmentId,
              expectedRevision: invoice.revision,
              decision: 'apply',
              idempotencyKey:
                  PurchaseInvoiceApiService.generateIdempotencyKey(),
            );
          }
          return created;
        });
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
        invoice.history.reversed
            .map(
              (event) => {
                'action': event.action,
                'message': event.message,
                'actor_name': event.actorName,
                'actor_role': event.actorRole,
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
      _sectionTitle(icon: Icons.history_rounded, title: 'سجل الإجراءات'),
      const SizedBox(height: 8),
      if (events.isEmpty)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Text('لا توجد إجراءات مسجلة على هذه الفاتورة حتى الآن.'),
          ),
        )
      else
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (var index = 0; index < events.length; index++)
                  _eventTile(events[index], isLast: index == events.length - 1),
              ],
            ),
          ),
        ),
    ],
  );

  Widget _eventTile(Map<String, dynamic> event, {required bool isLast}) {
    final rawTime = event['created_at'] ?? event['timestamp'];
    final time = rawTime is Timestamp
        ? rawTime.toDate()
        : rawTime is DateTime
        ? rawTime
        : rawTime is String
        ? DateTime.tryParse(rawTime)
        : null;
    final action = event['action']?.toString() ?? '';
    final presentation = _eventPresentation(action);
    final actor = event['actor_name']?.toString().trim() ?? '';
    final role = _roleLabel(event['actor_role']?.toString() ?? '');
    final metadata = [
      if (actor.isNotEmpty) actor,
      if (role.isNotEmpty) role,
      if (time != null) DateFormat('yyyy/MM/dd HH:mm').format(time),
    ];
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 48,
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 13),
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: presentation.color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    presentation.icon,
                    size: 17,
                    color: presentation.color,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(width: 1.5, color: AppTheme.dividerColor),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(4, 12, 14, isLast ? 14 : 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _eventMessage(event),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (metadata.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      metadata.join(' • '),
                      style: const TextStyle(
                        color: AppTheme.textHint,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  _PurchaseEventPresentation _eventPresentation(String action) {
    return switch (action) {
      'purchase_invoice_created' => const _PurchaseEventPresentation(
        icon: Icons.add_task_rounded,
        color: AppTheme.primaryOlive,
      ),
      'purchase_receipt_confirmed' => const _PurchaseEventPresentation(
        icon: Icons.inventory_rounded,
        color: AppTheme.primaryOlive,
      ),
      'purchase_initial_prices_confirmed' ||
      'purchase_prices_confirmed' => const _PurchaseEventPresentation(
        icon: Icons.verified_rounded,
        color: AppTheme.successColor,
      ),
      'purchase_posted' || 'purchase_posted_with_review_override' =>
        const _PurchaseEventPresentation(
          icon: Icons.account_balance_rounded,
          color: AppTheme.successColor,
        ),
      'purchase_amendment_requested' => const _PurchaseEventPresentation(
        icon: Icons.edit_note_rounded,
        color: AppTheme.warningColor,
      ),
      'purchase_amendment_rejected' => const _PurchaseEventPresentation(
        icon: Icons.cancel_outlined,
        color: AppTheme.errorColor,
      ),
      'purchase_amendment_approved' ||
      'purchase_amendment_applied' => const _PurchaseEventPresentation(
        icon: Icons.fact_check_rounded,
        color: AppTheme.successColor,
      ),
      'purchase_material_clarification_requested' =>
        const _PurchaseEventPresentation(
          icon: Icons.help_outline_rounded,
          color: AppTheme.warningColor,
        ),
      'purchase_material_review_resumed' => const _PurchaseEventPresentation(
        icon: Icons.restart_alt_rounded,
        color: AppTheme.primaryOlive,
      ),
      'purchase_material_synchronized' ||
      'purchase_material_reconciled' => const _PurchaseEventPresentation(
        icon: Icons.link_rounded,
        color: AppTheme.successColor,
      ),
      _ => const _PurchaseEventPresentation(
        icon: Icons.history_rounded,
        color: AppTheme.textHint,
      ),
    };
  }

  String _eventMessage(Map<String, dynamic> event) {
    final action = event['action']?.toString() ?? '';
    final known = switch (action) {
      'purchase_invoice_created' =>
        'تم إنشاء فاتورة المشتريات وإرسالها إلى الفرع المستلم.',
      'purchase_receipt_confirmed' => 'أكد مدير الفرع الكميات المستلمة.',
      'purchase_initial_prices_confirmed' =>
        'تم تأكيد الأسعار الأولية بحسب الكميات المستلمة.',
      'purchase_prices_confirmed' =>
        'اعتمد المدير العام أسعار فاتورة المشتريات.',
      'purchase_posted' => 'تم ترحيل فاتورة المشتريات إلى النظام المحاسبي.',
      'purchase_posted_with_review_override' =>
        'تم ترحيل الفاتورة باستثناء مدقق مع بقاء مواد للمراجعة.',
      'purchase_amendment_requested' => 'تم إرسال طلب تعديل الفاتورة للموافقة.',
      'purchase_amendment_approved' =>
        'وافق أحد المشاركين المطلوبين على طلب التعديل.',
      'purchase_amendment_rejected' => 'رُفض طلب التعديل ولم تتغير الفاتورة.',
      'purchase_amendment_applied' => 'اكتملت الموافقات وطُبق تعديل الفاتورة.',
      'purchase_material_clarification_requested' =>
        'طلب المحاسب توضيح بيانات إحدى المواد.',
      'purchase_material_review_resumed' => 'أعيدت مادة إلى قائمة المراجعة.',
      'purchase_material_synchronized' => 'تم تأكيد مزامنة مادة محاسبيًا.',
      'purchase_material_reconciled' => 'تمت معالجة مادة في قائمة المراجعة.',
      _ => null,
    };
    if (known != null) return known;
    final message = event['message']?.toString().trim() ?? '';
    return _containsArabic(message)
        ? message
        : 'تم تسجيل إجراء على فاتورة المشتريات.';
  }

  bool _containsArabic(String value) =>
      RegExp(r'[\u0600-\u06FF]').hasMatch(value);

  String _roleLabel(String role) => switch (role.trim()) {
    'collector' => 'المدير العام',
    'manager' => 'مدير الفرع',
    'accountant' => 'المحاسب',
    'admin' => 'مدير النظام',
    _ => _containsArabic(role) ? role : '',
  };

  Future<void> _run(Future<Object?> Function() operation) async {
    setState(() => _submitting = true);
    try {
      await operation();
      if (mounted) _message('تم حفظ الإجراء بنجاح.');
    } catch (error) {
      if (mounted) _message(_operationErrorText(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _operationErrorText(Object error) {
    if (error is FirebaseException) {
      return switch (error.code) {
        'permission-denied' => 'لا تملك صلاحية تنفيذ هذا الإجراء.',
        'unavailable' ||
        'deadline-exceeded' => 'تعذر الاتصال بالخدمة. حاول مرة أخرى.',
        _ => 'تعذر إتمام الإجراء الآن. حاول مرة أخرى.',
      };
    }
    final detail = error.toString().toLowerCase();
    if (detail.contains('permission') || detail.contains('forbidden')) {
      return 'لا تملك صلاحية تنفيذ هذا الإجراء.';
    }
    if (detail.contains('revision') || detail.contains('changed')) {
      return 'تغيرت الفاتورة أثناء العمل عليها. حدّث الصفحة ثم حاول مرة أخرى.';
    }
    if (detail.contains('duplicate')) {
      return 'توجد فاتورة مورد مطابقة مسجلة مسبقًا.';
    }
    if (detail.contains('network') || detail.contains('unavailable')) {
      return 'تعذر الاتصال بالخدمة. حاول مرة أخرى.';
    }
    return 'تعذر إتمام الإجراء الآن. حاول مرة أخرى.';
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
