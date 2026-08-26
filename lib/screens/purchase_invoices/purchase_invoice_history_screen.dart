import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/models/purchase_invoice_model.dart';
import 'package:store_collection_app/screens/purchase_invoices/purchase_invoice_details_screen.dart';
import 'package:store_collection_app/services/purchase_invoice_service.dart';
import 'package:store_collection_app/theme/app_theme.dart';

enum _HistorySort {
  newestCreated,
  oldestCreated,
  latestUpdated,
  purchaseNumber,
}

class PurchaseInvoiceHistoryScreen extends StatefulWidget {
  final UserRole role;
  final String? branchId;
  final String branchName;
  final Stream<List<PurchaseInvoiceRead>>? invoiceStream;

  const PurchaseInvoiceHistoryScreen({
    super.key,
    required this.role,
    required this.branchName,
    this.branchId,
    this.invoiceStream,
  });

  @override
  State<PurchaseInvoiceHistoryScreen> createState() =>
      _PurchaseInvoiceHistoryScreenState();
}

class _PurchaseInvoiceHistoryScreenState
    extends State<PurchaseInvoiceHistoryScreen> {
  final _search = TextEditingController();
  late final PurchaseInvoiceService _service = PurchaseInvoiceService();
  PurchaseInvoiceStatus? _status;
  bool _amendmentsOnly = false;
  _HistorySort _sort = _HistorySort.latestUpdated;

  @override
  void initState() {
    super.initState();
    _search.addListener(_refresh);
  }

  @override
  void dispose() {
    _search
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      appBar: AppBar(title: const Text('سجل فواتير المشتريات')),
      body: StreamBuilder<List<PurchaseInvoiceRead>>(
        stream:
            widget.invoiceStream ??
            _service.watchHistory(role: widget.role, branchId: widget.branchId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(
              child: Text('تعذر تحميل سجل فواتير المشتريات.'),
            );
          }
          final invoices = _filtered(snapshot.data ?? const []);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _filters(),
              const SizedBox(height: 14),
              if (invoices.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(child: Text('لا توجد فواتير مطابقة للبحث.')),
                )
              else
                ...invoices.map(_card),
            ],
          );
        },
      ),
    ),
  );

  Widget _filters() => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          TextField(
            key: const Key('purchase-history-search'),
            controller: _search,
            decoration: const InputDecoration(
              labelText: 'ابحث بالرقم أو المورد أو الفرع',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('كل الحالات'),
                selected: _status == null,
                onSelected: (_) => setState(() => _status = null),
              ),
              ...PurchaseInvoiceStatus.values
                  .where((status) => status != PurchaseInvoiceStatus.unknown)
                  .map(
                    (status) => ChoiceChip(
                      label: Text(status.label),
                      selected: _status == status,
                      onSelected: (_) => setState(() => _status = status),
                    ),
                  ),
              FilterChip(
                key: const Key('purchase-history-amendments-filter'),
                label: const Text('طلب تعديل بانتظار الإجراء'),
                selected: _amendmentsOnly,
                onSelected: (value) => setState(() => _amendmentsOnly = value),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<_HistorySort>(
            key: const Key('purchase-history-sort'),
            initialValue: _sort,
            decoration: const InputDecoration(
              labelText: 'الترتيب',
              prefixIcon: Icon(Icons.sort_rounded),
            ),
            items: const [
              DropdownMenuItem(
                value: _HistorySort.latestUpdated,
                child: Text('آخر تحديث'),
              ),
              DropdownMenuItem(
                value: _HistorySort.newestCreated,
                child: Text('الأحدث إنشاءً'),
              ),
              DropdownMenuItem(
                value: _HistorySort.oldestCreated,
                child: Text('الأقدم إنشاءً'),
              ),
              DropdownMenuItem(
                value: _HistorySort.purchaseNumber,
                child: Text('رقم الفاتورة'),
              ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _sort = value);
            },
          ),
        ],
      ),
    ),
  );

  List<PurchaseInvoiceRead> _filtered(List<PurchaseInvoiceRead> source) {
    final query = _search.text.trim().toLowerCase();
    final result = source
        .where((invoice) {
          final matchesQuery =
              query.isEmpty ||
              [
                invoice.purchaseNumber,
                invoice.supplierName,
                invoice.receivingBranchName,
              ].any((value) => value.toLowerCase().contains(query));
          return matchesQuery &&
              (_status == null || invoice.status == _status) &&
              (!_amendmentsOnly || invoice.hasPendingAmendment);
        })
        .toList(growable: false);
    result.sort((left, right) {
      return switch (_sort) {
        _HistorySort.newestCreated =>
          (right.createdAt ?? DateTime(0)).compareTo(
            left.createdAt ?? DateTime(0),
          ),
        _HistorySort.oldestCreated => (left.createdAt ?? DateTime(0)).compareTo(
          right.createdAt ?? DateTime(0),
        ),
        _HistorySort.latestUpdated =>
          (right.lastUpdated ?? DateTime(0)).compareTo(
            left.lastUpdated ?? DateTime(0),
          ),
        _HistorySort.purchaseNumber => left.purchaseNumber.compareTo(
          right.purchaseNumber,
        ),
      };
    });
    return result;
  }

  Widget _card(PurchaseInvoiceRead invoice) {
    final created = invoice.createdAt == null
        ? '-'
        : DateFormat('yyyy/MM/dd HH:mm').format(invoice.createdAt!);
    final updated = invoice.lastUpdated == null
        ? '-'
        : DateFormat('yyyy/MM/dd HH:mm').format(invoice.lastUpdated!);
    return Card(
      child: ListTile(
        key: Key('purchase-history-${invoice.id}'),
        isThreeLine: true,
        leading: CircleAvatar(
          backgroundColor: invoice.status.color.withValues(alpha: .12),
          child: Icon(Icons.receipt_long_rounded, color: invoice.status.color),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                invoice.purchaseNumber,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            if (invoice.hasPendingAmendment)
              const Tooltip(
                message: 'يوجد طلب تعديل بانتظار الإجراء',
                child: Icon(
                  Icons.edit_note_rounded,
                  color: AppTheme.warningColor,
                ),
              ),
          ],
        ),
        subtitle: Text(
          '${invoice.supplierName.isEmpty ? 'بدون مورد' : invoice.supplierName} • '
          '${invoice.receivingBranchName}\n'
          '${invoice.status.label} — المسؤول: ${invoice.currentResponsibleParty}\n'
          'أنشئت: $created • آخر تحديث: $updated'
          '${invoice.supplierInvoiceDate.isEmpty ? '' : ' • تاريخ المورد: ${invoice.supplierInvoiceDate}'}',
        ),
        trailing: const Icon(Icons.chevron_left_rounded),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PurchaseInvoiceDetailsScreen(
              invoiceId: invoice.id,
              role: widget.role,
              branchId: widget.branchId,
            ),
          ),
        ),
      ),
    );
  }
}
