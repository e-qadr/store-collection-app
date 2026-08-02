import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/models/inter_branch_invoice_model.dart';
import 'package:store_collection_app/models/inter_branch_invoice_price_model.dart';
import 'package:store_collection_app/models/product_price_model.dart';
import 'package:store_collection_app/services/inter_branch_invoice_api_service.dart';
import 'package:store_collection_app/services/inter_branch_invoice_service.dart';
import 'package:store_collection_app/services/pdf_service.dart';
import 'package:store_collection_app/services/product_price_service.dart';
import 'package:store_collection_app/theme/app_theme.dart';
import 'package:store_collection_app/utils/inter_branch_invoice_policies.dart';

typedef DirectReceiptSubmitter =
    Future<void> Function({
      required String invoiceId,
      required int expectedRevision,
      required List<InterBranchInvoiceItem> items,
      required String idempotencyKey,
      String? receiverNotes,
    });

typedef DirectPriceSubmitter =
    Future<void> Function({
      required String invoiceId,
      required int expectedRevision,
      required String currency,
      required List<InterBranchInvoicePriceInput> items,
      required String idempotencyKey,
      String? pricingNotes,
    });

typedef DirectAccountingSubmitter =
    Future<void> Function({
      required String invoiceId,
      required int expectedRevision,
      required String accountingReference,
      required String idempotencyKey,
      String? accountingNotes,
    });

typedef LegacySupplierDecisionSubmitter =
    Future<void> Function({
      required String invoiceId,
      required bool approved,
      required List<InterBranchInvoiceItem>? approvedItems,
      required String notes,
    });

typedef ProtectedPriceSnapshotLoader =
    Future<InterBranchInvoicePriceSnapshot?> Function(
      InterBranchInvoiceRead invoice,
    );

typedef LatestProductPriceLoader =
    Future<ProductPriceLatest?> Function({
      required String brandId,
      required String productId,
      required String unitId,
      required String currency,
    });

class InterBranchInvoiceDetailsScreen extends StatefulWidget {
  final String invoiceId;
  final UserRole role;
  final String? branchId;
  final String branchName;
  final Stream<Map<String, dynamic>?>? invoiceDataStream;
  final Stream<List<Map<String, dynamic>>>? itemDataStream;
  final ProtectedPriceSnapshotLoader? protectedPriceSnapshotLoader;
  final LatestProductPriceLoader? latestProductPriceLoader;
  final DirectReceiptSubmitter? directReceiptSubmitter;
  final DirectPriceSubmitter? directPriceSubmitter;
  final DirectAccountingSubmitter? directAccountingSubmitter;
  final LegacySupplierDecisionSubmitter? legacySupplierDecisionSubmitter;

  const InterBranchInvoiceDetailsScreen({
    super.key,
    required this.invoiceId,
    required this.role,
    required this.branchName,
    this.branchId,
    this.invoiceDataStream,
    this.itemDataStream,
    this.protectedPriceSnapshotLoader,
    this.latestProductPriceLoader,
    this.directReceiptSubmitter,
    this.directPriceSubmitter,
    this.directAccountingSubmitter,
    this.legacySupplierDecisionSubmitter,
  });

  @override
  State<InterBranchInvoiceDetailsScreen> createState() =>
      _InterBranchInvoiceDetailsScreenState();
}

class _InterBranchInvoiceDetailsScreenState
    extends State<InterBranchInvoiceDetailsScreen> {
  InterBranchInvoiceService? _service;
  ProductPriceService? _priceService;
  final _numberFormat = NumberFormat('#,##0.##');
  final _dateFormat = DateFormat('yyyy/MM/dd HH:mm');

  bool get _showsPrices =>
      InterBranchInvoicePolicy.mayReadProtectedPrices(widget.role);

  InterBranchInvoiceService get _invoiceService =>
      _service ??= InterBranchInvoiceService();

  ProductPriceService get _productPriceService =>
      _priceService ??= ProductPriceService();

  Stream<Map<String, dynamic>?> get _invoiceDataStream =>
      widget.invoiceDataStream ??
      _invoiceService
          .watchInvoice(widget.invoiceId)
          .map((snapshot) => snapshot.data());

  Stream<List<Map<String, dynamic>>> get _itemDataStream =>
      widget.itemDataStream ??
      _invoiceService.watchV2ItemDocuments(
        invoiceId: widget.invoiceId,
        role: widget.role,
        branchId: widget.branchId,
      );

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
          title: const Text('تفاصيل فاتورة بين الفروع'),
          backgroundColor: _roleColor,
          actions: [
            StreamBuilder<Map<String, dynamic>?>(
              stream: _invoiceDataStream,
              builder: (context, snapshot) {
                final data = snapshot.data;
                if (data == null) return const SizedBox.shrink();
                final header = InterBranchInvoiceRead(
                  id: widget.invoiceId,
                  data: data,
                );
                if (!_canViewInvoice(header)) return const SizedBox.shrink();
                return IconButton(
                  tooltip: 'طباعة PDF',
                  icon: const Icon(Icons.picture_as_pdf_rounded),
                  onPressed: () async {
                    try {
                      final invoice = header.isVersion2
                          ? header.withItemDocuments(
                              await _invoiceService.fetchV2ItemDocuments(
                                invoiceId: header.id,
                                role: widget.role,
                                branchId: widget.branchId,
                              ),
                            )
                          : header;
                      if (invoice.isVersion2 &&
                          invoice.items.length != invoice.itemCount) {
                        throw StateError('Invoice items are incomplete.');
                      }
                      final protectedPrices = await _loadProtectedPriceSnapshot(
                        invoice,
                      );
                      await PdfService.printSecureInterBranchInvoice(
                        invoiceId: invoice.id,
                        publicData: data,
                        audienceRole: widget.role,
                        priceSnapshot: protectedPrices,
                        itemDocuments: invoice.itemDocuments,
                      );
                    } catch (_) {
                      _showSnack('تعذر إنشاء PDF. حاول مجدداً.');
                    }
                  },
                );
              },
            ),
          ],
        ),
        body: StreamBuilder<Map<String, dynamic>?>(
          stream: _invoiceDataStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return const Center(child: Text('تعذر تحميل تفاصيل الفاتورة'));
            }
            final data = snapshot.data;
            if (data == null) {
              return const Center(child: Text('الفاتورة غير موجودة'));
            }
            final header = InterBranchInvoiceRead(
              id: widget.invoiceId,
              data: data,
            );
            if (!_canViewInvoice(header)) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'ليست لديك صلاحية عرض هذه الفاتورة من هذا الفرع.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            if (header.isVersion2) {
              return StreamBuilder<List<Map<String, dynamic>>>(
                stream: _itemDataStream,
                builder: (context, itemSnapshot) {
                  if (itemSnapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (itemSnapshot.hasError) {
                    return const Center(
                      child: Text('تعذر تحميل أصناف الفاتورة'),
                    );
                  }
                  final invoice = header.withItemDocuments(
                    itemSnapshot.data ?? const [],
                  );
                  if (invoice.items.length != invoice.itemCount) {
                    return const Center(
                      child: Text(
                        'بيانات أصناف الفاتورة غير مكتملة. أعد المحاولة لاحقاً.',
                      ),
                    );
                  }
                  return _loadedInvoice(invoice);
                },
              );
            }
            return _loadedInvoice(header);
          },
        ),
      ),
    );
  }

  Widget _loadedInvoice(InterBranchInvoiceRead invoice) {
    return FutureBuilder<InterBranchInvoicePriceSnapshot?>(
      future: _loadProtectedPriceSnapshot(invoice),
      builder: (context, priceSnapshot) {
        final actions = _actions(invoice);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _invoiceDocument(invoice, priceSnapshot: priceSnapshot.data),
            if (actions != null) ...[const SizedBox(height: 12), actions],
            const SizedBox(height: 12),
            _statusTimeline(invoice),
            const SizedBox(height: 12),
            _history(invoice),
          ],
        );
      },
    );
  }

  bool _canViewInvoice(InterBranchInvoiceRead invoice) {
    return InterBranchInvoicePolicy.canView(
      role: widget.role,
      branchId: widget.branchId,
      invoice: invoice,
    );
  }

  Future<InterBranchInvoicePriceSnapshot?> _loadProtectedPriceSnapshot(
    InterBranchInvoiceRead invoice,
  ) async {
    if (!invoice.isVersion2 ||
        !InterBranchInvoicePolicy.mayReadProtectedPrices(widget.role)) {
      return null;
    }
    final loader = widget.protectedPriceSnapshotLoader;
    if (loader != null) {
      final result = await loader(invoice);
      return result?.matchesPublicInvoice(invoice) == true ? result : null;
    }
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(InterBranchInvoiceFields.priceCollection)
          .doc(invoice.id)
          .get();
      final data = snapshot.data();
      if (data == null) return null;
      final result = InterBranchInvoicePriceSnapshot.fromMap(snapshot.id, data);
      return result.matchesPublicInvoice(invoice) ? result : null;
    } catch (_) {
      return null;
    }
  }

  Widget _invoiceDocument(
    InterBranchInvoiceRead invoice, {
    InterBranchInvoicePriceSnapshot? priceSnapshot,
  }) {
    final date = invoice.invoiceCreatedAt ?? invoice.requestDate;
    final invoiceTitle = invoice.invoiceNumber == '-'
        ? 'طلب بانتظار إنشاء الفاتورة'
        : invoice.invoiceNumber;

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _invoiceHeader(invoice, invoiceTitle, date),
          const SizedBox(height: 16),
          _invoiceProductsTable(invoice, priceSnapshot: priceSnapshot),
          const SizedBox(height: 14),
          _invoiceSummary(invoice, priceSnapshot: priceSnapshot),
          if (invoice.invoiceNotes.trim().isNotEmpty ||
              invoice.receiverNotes.trim().isNotEmpty ||
              (priceSnapshot?.pricingNotes.trim().isNotEmpty ?? false) ||
              (priceSnapshot?.accountingNotes.trim().isNotEmpty ?? false)) ...[
            const SizedBox(height: 14),
            _invoiceNotesPanel(invoice, priceSnapshot: priceSnapshot),
          ],
        ],
      ),
    );
  }

  Widget _invoiceHeader(
    InterBranchInvoiceRead invoice,
    String invoiceTitle,
    DateTime? date,
  ) {
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
                    Icons.receipt_long_rounded,
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
                        'فاتورة بين الفروع',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        invoiceTitle,
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
                _statusChip(invoice.status),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _invoiceInfoBox(
                        'من الفرع',
                        invoice.sendingBranchName,
                        Icons.store_mall_directory_rounded,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(
                        Icons.arrow_back_rounded,
                        color: _roleColor,
                        size: 20,
                      ),
                    ),
                    Expanded(
                      child: _invoiceInfoBox(
                        'إلى الفرع',
                        invoice.receivingBranchName,
                        Icons.storefront_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _invoiceMeta(
                      'تاريخ الطلب',
                      _formatDate(invoice.requestDate),
                    ),
                    _invoiceMeta('تاريخ الفاتورة', _formatDate(date)),
                    _invoiceMeta(
                      'المرجع المحاسبي',
                      invoice.accountingReference.isEmpty
                          ? 'لم يرحل بعد'
                          : invoice.accountingReference,
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

  Widget _invoiceInfoBox(String label, String value, IconData icon) {
    return Container(
      constraints: const BoxConstraints(minHeight: 62),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: _roleColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
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
                    fontSize: 13,
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

  Widget _invoiceMeta(String label, String value) {
    return Container(
      constraints: const BoxConstraints(minWidth: 132, maxWidth: 230),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _invoiceProductsTable(
    InterBranchInvoiceRead invoice, {
    InterBranchInvoicePriceSnapshot? priceSnapshot,
  }) {
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
                dataRowMaxHeight: invoice.isVersion2 ? 100 : 58,
                horizontalMargin: 12,
                columnSpacing: 20,
                headingRowColor: WidgetStatePropertyAll(
                  _roleColor.withValues(alpha: 0.08),
                ),
                columns: [
                  const DataColumn(label: Text('#')),
                  const DataColumn(label: Text('المنتج')),
                  const DataColumn(label: Text('الوحدة')),
                  DataColumn(
                    label: Text(invoice.isVersion2 ? 'المورد' : 'المطلوب'),
                  ),
                  if (!invoice.isVersion2)
                    const DataColumn(label: Text('المعتمد')),
                  const DataColumn(label: Text('المستلم')),
                  if (invoice.isVersion2) ...[
                    const DataColumn(label: Text('تالف')),
                    const DataColumn(label: Text('ناقص')),
                  ],
                  if (_showsPrices) ...[
                    DataColumn(
                      label: Text(
                        priceSnapshot?.currency.isNotEmpty ?? false
                            ? 'سعر الوحدة (${priceSnapshot!.currency})'
                            : 'سعر الوحدة',
                      ),
                    ),
                    const DataColumn(label: Text('الإجمالي')),
                  ],
                ],
                rows: invoice.items.asMap().entries.map((entry) {
                  final item = entry.value;
                  final protectedItem = priceSnapshot?.itemById(item.itemId);
                  final unitPrice = invoice.isVersion2
                      ? protectedItem?.unitPrice
                      : item.unitPrice;
                  final lineTotal = invoice.isVersion2
                      ? protectedItem?.lineTotal
                      : item.totalPrice;
                  return DataRow(
                    cells: [
                      DataCell(Text('${entry.key + 1}')),
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 190),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name.isEmpty ? '-' : item.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (item.lineNotes.trim().isNotEmpty)
                                Text(
                                  'ملاحظة التوريد: ${item.lineNotes}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 11,
                                  ),
                                ),
                              if (item.discrepancyNotes.trim().isNotEmpty)
                                Text(
                                  'ملاحظة الفرق: ${item.discrepancyNotes}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppTheme.warningColor,
                                    fontSize: 11,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      DataCell(Text(item.unit.isEmpty ? '-' : item.unit)),
                      DataCell(Text(_formatNumber(item.requestedQuantity))),
                      if (!invoice.isVersion2)
                        DataCell(Text(_formatNumber(item.approvedQuantity))),
                      DataCell(
                        Text(
                          item.actualReceivedQuantity == null
                              ? '-'
                              : _formatNumber(item.receivedQuantity),
                        ),
                      ),
                      if (invoice.isVersion2) ...[
                        DataCell(Text(_formatNumber(item.damagedQuantity))),
                        DataCell(Text(_formatNumber(item.missingQuantity))),
                      ],
                      if (_showsPrices) ...[
                        DataCell(
                          Text(
                            unitPrice == null ? '-' : _formatNumber(unitPrice),
                          ),
                        ),
                        DataCell(
                          Text(
                            lineTotal == null ? '-' : _formatNumber(lineTotal),
                            style: const TextStyle(
                              color: AppTheme.successColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
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

  Widget _invoiceSummary(
    InterBranchInvoiceRead invoice, {
    InterBranchInvoicePriceSnapshot? priceSnapshot,
  }) {
    final totalRequested = invoice.items.fold<double>(
      0,
      (total, item) => total + item.requestedQuantity,
    );
    final totalApproved = invoice.items.fold<double>(
      0,
      (total, item) => total + item.approvedQuantity,
    );
    final totalReceived = invoice.receivedQuantity;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'ملخص الفاتورة',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _summaryTile(
                'إجمالي عدد المنتجات',
                '${invoice.items.length}',
                Icons.category_rounded,
                _roleColor,
              ),
              _summaryTile(
                invoice.isVersion2 ? 'إجمالي المورد' : 'إجمالي المطلوب',
                _formatNumber(totalRequested),
                Icons.playlist_add_check_rounded,
                AppTheme.textSecondary,
              ),
              if (!invoice.isVersion2)
                _summaryTile(
                  'إجمالي المعتمد',
                  _formatNumber(totalApproved),
                  Icons.verified_rounded,
                  AppTheme.managerColor,
                ),
              _summaryTile(
                'إجمالي المستلم',
                totalReceived == null
                    ? 'لم يؤكد بعد'
                    : _formatNumber(totalReceived),
                Icons.inventory_2_rounded,
                AppTheme.collectorColor,
              ),
              if (_showsPrices)
                _summaryTile(
                  priceSnapshot?.currency.isNotEmpty ?? false
                      ? 'إجمالي سعر الفاتورة (${priceSnapshot!.currency})'
                      : 'إجمالي سعر الفاتورة',
                  (invoice.isVersion2
                              ? priceSnapshot?.total
                              : invoice.totalPrice) ==
                          null
                      ? 'لم تدخل الأسعار بعد'
                      : _formatNumber(
                          invoice.isVersion2
                              ? priceSnapshot!.total
                              : invoice.totalPrice!,
                        ),
                  Icons.payments_rounded,
                  AppTheme.successColor,
                  wide: true,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _invoiceNotesPanel(
    InterBranchInvoiceRead invoice, {
    InterBranchInvoicePriceSnapshot? priceSnapshot,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'ملاحظات الفاتورة',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          if (invoice.invoiceNotes.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('التوريد: ${invoice.invoiceNotes}'),
          ],
          if (invoice.receiverNotes.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('الاستلام: ${invoice.receiverNotes}'),
          ],
          if (priceSnapshot?.pricingNotes.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 8),
            Text('التسعير: ${priceSnapshot!.pricingNotes}'),
          ],
          if (priceSnapshot?.accountingNotes.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 8),
            Text('الترحيل: ${priceSnapshot!.accountingNotes}'),
          ],
        ],
      ),
    );
  }

  Widget _summaryTile(
    String label,
    String value,
    IconData icon,
    Color color, {
    bool wide = false,
  }) {
    return Container(
      constraints: BoxConstraints(
        minWidth: wide ? 210 : 132,
        maxWidth: wide ? 260 : 180,
      ),
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
                    fontSize: wide ? 15 : 14,
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

  Widget _statusTimeline(InterBranchInvoiceRead invoice) {
    final steps = _timelineSteps(invoice);
    final currentIndex = _timelineIndex(invoice);
    final isException = _isExceptionStatus(invoice.status);

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
                  'مسار حالة الفاتورة',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              _statusChip(invoice.status),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: invoice.status.color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: invoice.status.color.withValues(alpha: 0.16),
              ),
            ),
            child: Text(
              'وصلت الفاتورة الآن إلى: ${invoice.status.label}',
              style: TextStyle(
                color: invoice.status.color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < steps.length; index++)
            _timelineStep(
              step: steps[index],
              isFirst: index == 0,
              isLast: index == steps.length - 1,
              isCompleted:
                  index < currentIndex ||
                  (invoice.status ==
                          InterBranchInvoiceStatus.postedToAccounting &&
                      index == currentIndex),
              isActive: index == currentIndex,
              isException: isException && index == currentIndex,
              activeLabel: index == currentIndex ? invoice.status.label : null,
            ),
        ],
      ),
    );
  }

  Widget _timelineStep({
    required _InvoiceTimelineStep step,
    required bool isFirst,
    required bool isLast,
    required bool isCompleted,
    required bool isActive,
    required bool isException,
    String? activeLabel,
  }) {
    final color = isException
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
                  size: 17,
                  color: color,
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
                const SizedBox(width: 8),
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

  List<_InvoiceTimelineStep> _timelineSteps(InterBranchInvoiceRead invoice) {
    if (invoice.isVersion2) {
      return const [
        _InvoiceTimelineStep(
          title: 'إنشاء الفاتورة المباشرة',
          subtitle: 'أنشأ الفرع المورد الفاتورة وأرسلها للمستلم',
          icon: Icons.receipt_long_rounded,
          color: AppTheme.managerColor,
        ),
        _InvoiceTimelineStep(
          title: 'تأكيد الاستلام',
          subtitle: 'تسجيل الكميات المستلمة والفروقات',
          icon: Icons.inventory_rounded,
          color: AppTheme.collectorColor,
        ),
        _InvoiceTimelineStep(
          title: 'تأكيد الأسعار',
          subtitle: 'اعتماد الأسعار المحمية من المدير العام',
          icon: Icons.price_change_rounded,
          color: AppTheme.accountantColor,
        ),
        _InvoiceTimelineStep(
          title: 'الترحيل المحاسبي',
          subtitle: 'إغلاق الفاتورة في النظام المحاسبي',
          icon: Icons.account_balance_wallet_rounded,
          color: AppTheme.successColor,
        ),
      ];
    }
    return [
      _InvoiceTimelineStep(
        title: 'طلب الفاتورة',
        subtitle: 'تم إنشاء الطلب بين الفروع',
        icon: Icons.assignment_rounded,
        color: _roleColor,
      ),
      const _InvoiceTimelineStep(
        title: 'اعتماد الفرع المورد',
        subtitle: 'مراجعة الطلب وتكوين الفاتورة',
        icon: Icons.fact_check_rounded,
        color: AppTheme.managerColor,
      ),
      const _InvoiceTimelineStep(
        title: 'مراجعة الفرع المستلم',
        subtitle: 'تأكيد الكميات المستلمة',
        icon: Icons.inventory_rounded,
        color: AppTheme.collectorColor,
      ),
      const _InvoiceTimelineStep(
        title: 'إدخال الأسعار',
        subtitle: 'تسجيل أسعار المنتجات',
        icon: Icons.price_change_rounded,
        color: AppTheme.accountantColor,
      ),
      const _InvoiceTimelineStep(
        title: 'الترحيل المحاسبي',
        subtitle: 'إغلاق الفاتورة في النظام المحاسبي',
        icon: Icons.account_balance_wallet_rounded,
        color: AppTheme.successColor,
      ),
    ];
  }

  int _timelineIndex(InterBranchInvoiceRead invoice) {
    final status = invoice.status;
    if (_isExceptionStatus(status)) {
      final rawPrevious = invoice.data[InterBranchInvoiceFields.previousStatus]
          ?.toString();
      if (rawPrevious != null && rawPrevious.isNotEmpty) {
        final previous = interBranchInvoiceStatusFromString(rawPrevious);
        if (previous != status) {
          return _timelineIndexForStatus(previous, invoice.workflowVersion);
        }
      }
    }
    return _timelineIndexForStatus(status, invoice.workflowVersion);
  }

  int _timelineIndexForStatus(
    InterBranchInvoiceStatus status,
    int workflowVersion,
  ) {
    if (workflowVersion >= 2) {
      switch (status) {
        case InterBranchInvoiceStatus.pendingReceiverReview:
          return 0;
        case InterBranchInvoiceStatus.pendingPriceEntry:
        case InterBranchInvoiceStatus.receivedByReceivingManager:
          return 1;
        case InterBranchInvoiceStatus.pendingAccountingEntry:
        case InterBranchInvoiceStatus.pricesEnteredByCollector:
          return 2;
        case InterBranchInvoiceStatus.postedToAccounting:
          return 3;
        default:
          return 0;
      }
    }
    switch (status) {
      case InterBranchInvoiceStatus.requestPending:
        return 0;
      case InterBranchInvoiceStatus.requestRejectedBySupplier:
      case InterBranchInvoiceStatus.approvedBySupplier:
      case InterBranchInvoiceStatus.invoiceCreated:
      case InterBranchInvoiceStatus.pendingReceiverReview:
        return 1;
      case InterBranchInvoiceStatus.receivedByReceivingManager:
      case InterBranchInvoiceStatus.pendingPriceEntry:
        return 2;
      case InterBranchInvoiceStatus.pricesEnteredByCollector:
      case InterBranchInvoiceStatus.pendingAccountingEntry:
        return 3;
      case InterBranchInvoiceStatus.postedToAccounting:
        return 4;
      case InterBranchInvoiceStatus.cancellationRequested:
      case InterBranchInvoiceStatus.cancellationPendingApprovals:
      case InterBranchInvoiceStatus.cancelled:
      case InterBranchInvoiceStatus.editRequested:
      case InterBranchInvoiceStatus.editPendingApprovals:
      case InterBranchInvoiceStatus.editApproved:
      case InterBranchInvoiceStatus.editRejected:
      case InterBranchInvoiceStatus.unknown:
        return 2;
    }
  }

  bool _isExceptionStatus(InterBranchInvoiceStatus status) {
    switch (status) {
      case InterBranchInvoiceStatus.requestRejectedBySupplier:
      case InterBranchInvoiceStatus.cancellationRequested:
      case InterBranchInvoiceStatus.cancellationPendingApprovals:
      case InterBranchInvoiceStatus.cancelled:
      case InterBranchInvoiceStatus.editRequested:
      case InterBranchInvoiceStatus.editPendingApprovals:
      case InterBranchInvoiceStatus.editRejected:
      case InterBranchInvoiceStatus.unknown:
        return true;
      case InterBranchInvoiceStatus.requestPending:
      case InterBranchInvoiceStatus.approvedBySupplier:
      case InterBranchInvoiceStatus.invoiceCreated:
      case InterBranchInvoiceStatus.pendingReceiverReview:
      case InterBranchInvoiceStatus.receivedByReceivingManager:
      case InterBranchInvoiceStatus.pendingPriceEntry:
      case InterBranchInvoiceStatus.pricesEnteredByCollector:
      case InterBranchInvoiceStatus.pendingAccountingEntry:
      case InterBranchInvoiceStatus.postedToAccounting:
      case InterBranchInvoiceStatus.editApproved:
        return false;
    }
  }

  Widget? _actions(InterBranchInvoiceRead invoice) {
    final allowed = InterBranchInvoicePolicy.actionsFor(
      role: widget.role,
      branchId: widget.branchId,
      invoice: invoice,
    );
    final buttons = <Widget>[];

    if (allowed.contains(InterBranchInvoiceAction.legacySupplierApprove)) {
      buttons.addAll([
        _actionButton(
          'تكوين الفاتورة',
          Icons.check_rounded,
          AppTheme.successColor,
          () => _showSupplierDecision(invoice, approved: true),
        ),
        _actionButton(
          'رفض',
          Icons.close_rounded,
          AppTheme.errorColor,
          () => _showSupplierDecision(invoice, approved: false),
        ),
      ]);
    }

    if (allowed.contains(InterBranchInvoiceAction.confirmReceipt)) {
      buttons.add(
        _actionButton(
          'تأكيد الاستلام',
          Icons.inventory_rounded,
          AppTheme.managerColor,
          () => _showReceive(invoice),
        ),
      );
    }

    if (allowed.contains(InterBranchInvoiceAction.confirmPrices)) {
      buttons.add(
        _actionButton(
          'إدخال الأسعار',
          Icons.price_change_rounded,
          AppTheme.collectorColor,
          () => _showPrices(invoice),
        ),
      );
    }

    if (allowed.contains(InterBranchInvoiceAction.postAccounting)) {
      buttons.add(
        _actionButton(
          'ترحيل محاسبي',
          Icons.verified_rounded,
          AppTheme.accountantColor,
          () => _showAccounting(invoice),
        ),
      );
    }

    if (allowed.contains(InterBranchInvoiceAction.requestEdit)) {
      buttons.add(
        _actionButton(
          'طلب تعديل',
          Icons.edit_note_rounded,
          AppTheme.warningColor,
          () => _showReason(
            title: 'طلب تعديل الفاتورة',
            label: 'سبب طلب التعديل',
            onSubmit: (reason) => _invoiceService.requestEdit(
              invoiceId: invoice.id,
              reason: reason,
            ),
          ),
        ),
      );
      if (allowed.contains(InterBranchInvoiceAction.requestCancellation)) {
        buttons.add(
          _actionButton(
            'طلب إلغاء',
            Icons.cancel_schedule_send_rounded,
            AppTheme.errorColor,
            () => _showReason(
              title: 'طلب رفض أو إلغاء الفاتورة',
              label: 'سبب الرفض أو الإلغاء',
              onSubmit: (reason) => _invoiceService.requestCancellation(
                invoiceId: invoice.id,
                reason: reason,
              ),
            ),
          ),
        );
      }
    }

    if (allowed.contains(InterBranchInvoiceAction.approveSharedRequest)) {
      final isCancel =
          invoice.status ==
          InterBranchInvoiceStatus.cancellationPendingApprovals;
      buttons.addAll([
        _actionButton(
          'اعتماد الطلب',
          Icons.done_all_rounded,
          AppTheme.successColor,
          () => _approveShared(invoice, isCancel, true),
        ),
        _actionButton(
          'رفض الطلب',
          Icons.highlight_off_rounded,
          AppTheme.errorColor,
          () => _approveShared(invoice, isCancel, false),
        ),
      ]);
    }

    if (buttons.isEmpty) return null;
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.tune_rounded, color: _roleColor, size: 18),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'إجراءات الفاتورة',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final button in buttons) ...[
                  button,
                  if (button != buttons.last) const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _history(InterBranchInvoiceRead invoice) {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'سجل حالات الفاتورة',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          if (invoice.history.isEmpty)
            const Text('لا يوجد سجل بعد')
          else
            ...invoice.history.reversed.map((entry) {
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

  Future<void> _showSupplierDecision(
    InterBranchInvoiceRead invoice, {
    required bool approved,
  }) async {
    final controllers = invoice.items
        .map(
          (item) =>
              TextEditingController(text: _formatNumber(item.approvedQuantity)),
        )
        .toList();
    final notes = TextEditingController();
    await _dialog(
      title: approved ? 'اعتماد الطلب' : 'رفض الطلب',
      children: [
        if (approved)
          ...invoice.items.asMap().entries.map((entry) {
            final item = entry.value;
            return TextField(
              controller: controllers[entry.key],
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: '${item.name} - الكمية المعتمدة',
              ),
            );
          }),
        TextField(
          controller: notes,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: approved ? 'ملاحظات' : 'سبب الرفض',
          ),
        ),
      ],
      onSubmit: () async {
        final approvedItems = invoice.items.asMap().entries.map((entry) {
          final item = entry.value;
          return InterBranchInvoiceItem(
            name: item.name,
            unit: item.unit,
            requestedQuantity: item.requestedQuantity,
            approvedQuantity: _parseNumber(controllers[entry.key].text),
          );
        }).toList();
        if (approved &&
            approvedItems.any((item) => item.approvedQuantity <= 0)) {
          throw Exception('أدخل كمية صحيحة لكل منتج');
        }
        final submitter = widget.legacySupplierDecisionSubmitter;
        if (submitter != null) {
          await submitter(
            invoiceId: invoice.id,
            approved: approved,
            approvedItems: approved ? approvedItems : null,
            notes: notes.text,
          );
        } else {
          await _invoiceService.submitSenderDecision(
            invoiceId: invoice.id,
            approved: approved,
            approvedQuantity: approved
                ? approvedItems.first.approvedQuantity
                : null,
            approvedItems: approved ? approvedItems : null,
            notes: notes.text,
          );
        }
      },
    );
  }

  Future<void> _showReceive(InterBranchInvoiceRead invoice) async {
    if (invoice.isVersion2) {
      await _showDirectReceive(invoice);
      return;
    }
    final controllers = invoice.items
        .map(
          (item) =>
              TextEditingController(text: _formatNumber(item.approvedQuantity)),
        )
        .toList();
    final notes = TextEditingController();
    await _dialog(
      title: 'تأكيد الاستلام',
      children: [
        ...invoice.items.asMap().entries.map((entry) {
          final item = entry.value;
          return TextField(
            controller: controllers[entry.key],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: '${item.name} - كمية الاستلام',
            ),
          );
        }),
        TextField(
          controller: notes,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'ملاحظات'),
        ),
      ],
      onSubmit: () async {
        final receivedItems = invoice.items.asMap().entries.map((entry) {
          final item = entry.value;
          return InterBranchInvoiceItem(
            name: item.name,
            unit: item.unit,
            requestedQuantity: item.requestedQuantity,
            approvedQuantity: item.approvedQuantity,
            receivedQuantity: _parseNumber(controllers[entry.key].text),
            unitPrice: item.unitPrice,
          );
        }).toList();
        if (receivedItems.any((item) => item.receivedQuantity <= 0)) {
          throw Exception('أدخل كمية استلام صحيحة لكل منتج');
        }
        await _invoiceService.confirmReceipt(
          invoiceId: invoice.id,
          receivedQuantity: receivedItems.first.receivedQuantity,
          receivedItems: receivedItems,
          notes: notes.text,
        );
      },
    );
  }

  Future<void> _showPrices(InterBranchInvoiceRead invoice) async {
    if (invoice.isVersion2) {
      await _showDirectPrices(invoice);
      return;
    }
    final controllers = invoice.items
        .map(
          (item) => TextEditingController(
            text: item.unitPrice == null ? '' : _formatNumber(item.unitPrice!),
          ),
        )
        .toList();
    final notes = TextEditingController();
    await _dialog(
      title: 'إدخال أسعار المنتجات',
      children: [
        ...invoice.items.asMap().entries.map((entry) {
          final item = entry.value;
          return TextField(
            controller: controllers[entry.key],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: '${item.name} - سعر الوحدة'),
          );
        }),
        TextField(
          controller: notes,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'ملاحظات'),
        ),
      ],
      onSubmit: () async {
        final pricedItems = invoice.items.asMap().entries.map((entry) {
          final item = entry.value;
          return InterBranchInvoiceItem(
            name: item.name,
            unit: item.unit,
            requestedQuantity: item.requestedQuantity,
            approvedQuantity: item.approvedQuantity,
            receivedQuantity: item.receivedQuantity,
            unitPrice: _parseNumber(controllers[entry.key].text),
          );
        }).toList();
        if (pricedItems.any(
          (item) => item.unitPrice == null || item.unitPrice! <= 0,
        )) {
          throw Exception('أدخل سعر صحيح لكل منتج');
        }
        await _invoiceService.addItemPrices(
          invoiceId: invoice.id,
          pricedItems: pricedItems,
          branchId: widget.branchId,
          notes: notes.text,
        );
      },
    );
  }

  Future<void> _showAccounting(InterBranchInvoiceRead invoice) async {
    final reference = TextEditingController();
    final notes = TextEditingController();
    final idempotencyKey = invoice.isVersion2
        ? InterBranchInvoiceApiService.generateIdempotencyKey()
        : '';
    await _dialog(
      title: 'ترحيل الفاتورة محاسبياً',
      children: [
        TextField(
          controller: reference,
          inputFormatters: const [_Utf8LengthLimitingTextInputFormatter(200)],
          decoration: const InputDecoration(
            labelText: 'رقم الفاتورة في النظام المحاسبي',
          ),
        ),
        TextField(
          controller: notes,
          inputFormatters: const [_Utf8LengthLimitingTextInputFormatter(1000)],
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'ملاحظات'),
        ),
      ],
      onSubmit: () async {
        if (reference.text.trim().isEmpty) {
          throw Exception('رقم الفاتورة في النظام المحاسبي مطلوب');
        }
        if (invoice.isVersion2) {
          final submitter = widget.directAccountingSubmitter;
          if (submitter != null) {
            await submitter(
              invoiceId: invoice.id,
              expectedRevision: invoice.revision,
              accountingReference: reference.text,
              idempotencyKey: idempotencyKey,
              accountingNotes: notes.text,
            );
          } else {
            await _invoiceService.postDirectAccounting(
              invoiceId: invoice.id,
              expectedRevision: invoice.revision,
              accountingReference: reference.text,
              idempotencyKey: idempotencyKey,
              accountingNotes: notes.text,
            );
          }
        } else {
          await _invoiceService.confirmAccounting(
            invoiceId: invoice.id,
            accountingReference: reference.text,
            branchId: widget.branchId,
            notes: notes.text,
          );
        }
      },
    );
  }

  Future<void> _showDirectReceive(InterBranchInvoiceRead invoice) async {
    final receivedControllers = invoice.items
        .map(
          (item) =>
              TextEditingController(text: _formatNumber(item.suppliedQuantity)),
        )
        .toList(growable: false);
    final damagedControllers = invoice.items
        .map((_) => TextEditingController(text: '0'))
        .toList(growable: false);
    final missingControllers = invoice.items
        .map((_) => TextEditingController(text: '0'))
        .toList(growable: false);
    final discrepancyControllers = invoice.items
        .map((item) => TextEditingController(text: item.discrepancyNotes))
        .toList(growable: false);
    final notes = TextEditingController();
    final idempotencyKey =
        InterBranchInvoiceApiService.generateIdempotencyKey();
    try {
      await _dialog(
        title: 'تأكيد الاستلام الفعلي',
        children: [
          const Text('يمكن تسجيل صفر للكمية المستلمة مع توضيح النقص أو التلف.'),
          ...invoice.items.asMap().entries.expand((entry) {
            final item = entry.value;
            final index = entry.key;
            return <Widget>[
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${item.name} (${_formatNumber(item.suppliedQuantity)} ${item.unit})',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: _quantityField(
                      controller: receivedControllers[index],
                      label: 'المستلم',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _quantityField(
                      controller: damagedControllers[index],
                      label: 'التالف',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _quantityField(
                      controller: missingControllers[index],
                      label: 'الناقص',
                    ),
                  ),
                ],
              ),
              TextField(
                controller: discrepancyControllers[index],
                inputFormatters: const [
                  _Utf8LengthLimitingTextInputFormatter(100),
                ],
                decoration: const InputDecoration(
                  labelText: 'ملاحظة الفرق (اختياري)',
                ),
              ),
              const Divider(),
            ];
          }),
          TextField(
            controller: notes,
            inputFormatters: const [
              _Utf8LengthLimitingTextInputFormatter(1000),
            ],
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'ملاحظات الاستلام'),
          ),
        ],
        onSubmit: () async {
          final confirmedItems = <InterBranchInvoiceItem>[];
          for (var index = 0; index < invoice.items.length; index++) {
            final item = invoice.items[index];
            final received = _tryParseNumber(receivedControllers[index].text);
            final damaged = _tryParseNumber(damagedControllers[index].text);
            final missing = _tryParseNumber(missingControllers[index].text);
            if (received == null ||
                damaged == null ||
                missing == null ||
                received < 0 ||
                damaged < 0 ||
                missing < 0) {
              throw Exception('أدخل كميات صحيحة غير سالبة.');
            }
            if (damaged > received) {
              throw Exception('الكمية التالفة لا يمكن أن تتجاوز المستلمة.');
            }
            final maximumMissing = (item.suppliedQuantity - received).clamp(
              0,
              double.infinity,
            );
            if (missing > maximumMissing) {
              throw Exception('الكمية الناقصة لا تتوافق مع الكمية الموردة.');
            }
            confirmedItems.add(
              item.copyWith(
                receivedQuantity: received,
                hasReceivedQuantity: true,
                damagedQuantity: damaged,
                missingQuantity: missing,
                discrepancyNotes: discrepancyControllers[index].text.trim(),
              ),
            );
          }
          final submitter = widget.directReceiptSubmitter;
          if (submitter != null) {
            await submitter(
              invoiceId: invoice.id,
              expectedRevision: invoice.revision,
              items: confirmedItems,
              idempotencyKey: idempotencyKey,
              receiverNotes: notes.text,
            );
          } else {
            await _invoiceService.confirmDirectReceipt(
              invoiceId: invoice.id,
              expectedRevision: invoice.revision,
              items: confirmedItems,
              idempotencyKey: idempotencyKey,
              receiverNotes: notes.text,
            );
          }
        },
      );
    } finally {
      // Navigator.pop completes the dialog future before the route's text
      // fields are detached. Wait for that frame before releasing controllers.
      await WidgetsBinding.instance.endOfFrame;
      for (final controller in [
        ...receivedControllers,
        ...damagedControllers,
        ...missingControllers,
        ...discrepancyControllers,
        notes,
      ]) {
        controller.dispose();
      }
    }
  }

  Future<void> _showDirectPrices(InterBranchInvoiceRead invoice) async {
    final currency = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('اختر العملة'),
        children: ProductPriceService.supportedCurrencies
            .map(
              (value) => SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, value),
                child: Text(value),
              ),
            )
            .toList(growable: false),
      ),
    );
    if (currency == null || !mounted) return;

    final suggestions = await Future.wait(
      invoice.items.map(
        (item) => _loadPriceSuggestion(
          brandId: invoice.sendingBrandId,
          productId: item.productId,
          unitId: item.unitId,
          currency: currency,
        ),
      ),
    );
    if (!mounted) return;
    final controllers = suggestions
        .map(
          (suggestion) => TextEditingController(
            text: suggestion == null ? '' : _formatNumber(suggestion.price),
          ),
        )
        .toList(growable: false);
    final notes = TextEditingController();
    final idempotencyKey =
        InterBranchInvoiceApiService.generateIdempotencyKey();
    try {
      await _dialog(
        title: 'تأكيد أسعار المنتجات ($currency)',
        children: [
          const Text(
            'الأسعار المحفوظة اقتراحات فقط. لن تصبح نهائية إلا بعد الحفظ.',
          ),
          ...invoice.items.asMap().entries.map((entry) {
            final item = entry.value;
            final suggestion = suggestions[entry.key];
            final sourceDate = suggestion?.changedAt == null
                ? ''
                : _dateFormat.format(suggestion!.changedAt!);
            final source = suggestion == null
                ? 'لا يوجد سعر سابق لهذه الوحدة'
                : 'اقتراح من فاتورة ${suggestion.sourceInvoiceId}'
                      '${sourceDate.isEmpty ? '' : ' - $sourceDate'}';
            return TextField(
              controller: controllers[entry.key],
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: InputDecoration(
                labelText:
                    '${item.name} - ${item.unit} - ${_formatNumber(item.receivedQuantity)}',
                helperText: source,
                helperMaxLines: 2,
              ),
            );
          }),
          TextField(
            controller: notes,
            inputFormatters: const [
              _Utf8LengthLimitingTextInputFormatter(1000),
            ],
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'ملاحظات التسعير'),
          ),
        ],
        onSubmit: () async {
          final inputs = <InterBranchInvoicePriceInput>[];
          for (var index = 0; index < invoice.items.length; index++) {
            final value = _tryParseNumber(controllers[index].text);
            if (value == null || value < 0) {
              throw Exception('أكد سعراً صحيحاً لكل منتج.');
            }
            inputs.add(
              InterBranchInvoicePriceInput(
                itemId: invoice.items[index].itemId,
                unitPrice: value,
              ),
            );
          }
          final submitter = widget.directPriceSubmitter;
          if (submitter != null) {
            await submitter(
              invoiceId: invoice.id,
              expectedRevision: invoice.revision,
              currency: currency,
              items: inputs,
              idempotencyKey: idempotencyKey,
              pricingNotes: notes.text,
            );
          } else {
            await _invoiceService.confirmDirectPrices(
              invoiceId: invoice.id,
              expectedRevision: invoice.revision,
              currency: currency,
              items: inputs,
              idempotencyKey: idempotencyKey,
              pricingNotes: notes.text,
            );
          }
        },
      );
    } finally {
      await WidgetsBinding.instance.endOfFrame;
      for (final controller in [...controllers, notes]) {
        controller.dispose();
      }
    }
  }

  Future<ProductPriceLatest?> _loadPriceSuggestion({
    required String brandId,
    required String productId,
    required String unitId,
    required String currency,
  }) async {
    if (brandId.isEmpty || productId.isEmpty || unitId.isEmpty) return null;
    final loader = widget.latestProductPriceLoader;
    if (loader != null) {
      return loader(
        brandId: brandId,
        productId: productId,
        unitId: unitId,
        currency: currency,
      );
    }
    try {
      return await _productPriceService.fetchLatest(
        brandId: brandId,
        productId: productId,
        unitId: unitId,
        currency: currency,
      );
    } catch (_) {
      return null;
    }
  }

  Widget _quantityField({
    required TextEditingController controller,
    required String label,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      decoration: InputDecoration(labelText: label),
    );
  }

  Future<void> _showReason({
    required String title,
    required String label,
    required Future<void> Function(String reason) onSubmit,
  }) async {
    final reason = TextEditingController();
    await _dialog(
      title: title,
      children: [
        TextField(
          controller: reason,
          maxLines: 3,
          decoration: InputDecoration(labelText: label),
        ),
      ],
      onSubmit: () async {
        if (reason.text.trim().isEmpty) throw Exception(label);
        await onSubmit(reason.text);
      },
    );
  }

  Future<void> _approveShared(
    InterBranchInvoiceRead invoice,
    bool isCancel,
    bool approved,
  ) async {
    await _showReason(
      title: approved ? 'اعتماد الطلب' : 'رفض الطلب',
      label: approved ? 'ملاحظة' : 'سبب الرفض',
      onSubmit: (reason) {
        if (isCancel) {
          return _invoiceService.approveCancellation(
            invoiceId: invoice.id,
            approved: approved,
            reason: reason,
          );
        }
        return _invoiceService.approveEdit(
          invoiceId: invoice.id,
          approved: approved,
          reason: reason,
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

  Widget _statusChip(InterBranchInvoiceStatus status) {
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

  double? _tryParseNumber(String value) {
    final result = double.tryParse(value.trim().replaceAll(',', '.'));
    return result != null && result.isFinite ? result : null;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _InvoiceTimelineStep {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _InvoiceTimelineStep({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

class _Utf8LengthLimitingTextInputFormatter extends TextInputFormatter {
  final int maxBytes;

  const _Utf8LengthLimitingTextInputFormatter(this.maxBytes);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (utf8.encode(newValue.text).length <= maxBytes) return newValue;
    final buffer = StringBuffer();
    var byteCount = 0;
    for (final character in newValue.text.characters) {
      final characterBytes = utf8.encode(character).length;
      if (byteCount + characterBytes > maxBytes) break;
      buffer.write(character);
      byteCount += characterBytes;
    }
    final text = buffer.toString();
    final offset = newValue.selection.end.clamp(0, text.length);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}
