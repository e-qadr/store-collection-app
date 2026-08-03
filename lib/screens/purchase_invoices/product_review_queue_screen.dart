import 'package:flutter/material.dart';
import 'package:store_collection_app/models/product_catalog_model.dart';
import 'package:store_collection_app/models/purchase_invoice_model.dart';
import 'package:store_collection_app/screens/purchase_invoices/purchase_catalog_picker.dart';
import 'package:store_collection_app/services/product_catalog_service.dart';
import 'package:store_collection_app/services/purchase_invoice_api_service.dart';
import 'package:store_collection_app/services/purchase_invoice_service.dart';
import 'package:store_collection_app/theme/app_theme.dart';

class ProductReviewQueueScreen extends StatefulWidget {
  final Stream<List<ProductReviewTask>>? taskStream;

  const ProductReviewQueueScreen({super.key, this.taskStream});

  @override
  State<ProductReviewQueueScreen> createState() =>
      _ProductReviewQueueScreenState();
}

class _ProductReviewQueueScreenState extends State<ProductReviewQueueScreen> {
  late final PurchaseInvoiceService _service = PurchaseInvoiceService();
  late final PurchaseInvoiceApiService _api = PurchaseInvoiceApiService();
  late final ProductCatalogService _catalog = ProductCatalogService();
  final Set<String> _submitting = {};

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(title: const Text('مراجعة مواد المشتريات')),
        body: StreamBuilder<List<ProductReviewTask>>(
          stream: widget.taskStream ?? _service.watchReviewQueue(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return const Center(child: Text('تعذر تحميل قائمة المراجعة.'));
            }
            final tasks = snapshot.data ?? const [];
            if (tasks.isEmpty) {
              return const Center(
                child: Text('لا توجد مواد في قائمة المراجعة.'),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: tasks.length,
              itemBuilder: (context, index) {
                final task = tasks[index];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.originalMaterialName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'المجموعة الأصلية: ${task.originalGroupText.isEmpty ? 'غير مصنف' : task.originalGroupText}',
                        ),
                        Text('الوحدة الأصلية: ${task.originalUnitText}'),
                        Text('الحالة: ${_statusLabel(task.status)}'),
                        const SizedBox(height: 10),
                        if (_submitting.contains(task.id))
                          const Center(child: CircularProgressIndicator())
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _actions(task),
                          ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  List<Widget> _actions(ProductReviewTask task) {
    if (task.status == 'pending_review') {
      return [
        FilledButton.tonalIcon(
          key: Key('link-${task.id}'),
          onPressed: () => _link(task),
          icon: const Icon(Icons.link_rounded),
          label: const Text('ربط بمادة'),
        ),
        FilledButton.tonalIcon(
          key: Key('create-${task.id}'),
          onPressed: () => _create(task),
          icon: const Icon(Icons.add_box_rounded),
          label: const Text('إنشاء مادة'),
        ),
        OutlinedButton.icon(
          onPressed: () => _simpleAction(
            task,
            action: 'request_clarification',
            title: 'طلب توضيح',
          ),
          icon: const Icon(Icons.question_answer_rounded),
          label: const Text('طلب توضيح'),
        ),
      ];
    }
    if (task.status == 'clarification_requested') {
      return [
        FilledButton.tonalIcon(
          onPressed: () => _simpleAction(
            task,
            action: 'return_to_pending',
            title: 'إعادة المادة إلى المراجعة',
          ),
          icon: const Icon(Icons.replay_rounded),
          label: const Text('إعادة للمراجعة'),
        ),
      ];
    }
    if (const {
      'linked_material',
      'newly_created_material',
    }.contains(task.status)) {
      return [
        FilledButton.tonalIcon(
          onPressed: () => _synchronize(task),
          icon: const Icon(Icons.sync_rounded),
          label: const Text('تأكيد المرجع والمزامنة'),
        ),
      ];
    }
    return const [];
  }

  Future<int?> _invoiceRevision(ProductReviewTask task) async {
    try {
      return (await _service.loadInvoiceWithItems(task.invoiceId)).revision;
    } catch (error) {
      if (mounted) _message(error.toString());
      return null;
    }
  }

  Future<void> _link(ProductReviewTask task) async {
    final selection = await showPurchaseCatalogPicker(
      context,
      brandId: task.brandId,
      service: _catalog,
      title: 'ربط بمادة موجودة',
    );
    if (!mounted || selection == null) return;
    final product = selection.product;
    final unit = selection.unit;
    final reference = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${product.name} — ${unit.displayValue}'),
        content: TextField(
          controller: reference,
          decoration: const InputDecoration(
            labelText: 'مرجع النظام المحاسبي (اختياري)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('ربط'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    final invoiceRevision = await _invoiceRevision(task);
    if (invoiceRevision == null) return;
    await _run(
      task,
      () => _api.reviewTask(
        taskId: task.id,
        expectedRevision: task.revision,
        expectedInvoiceRevision: invoiceRevision,
        action: 'link_existing',
        productId: product.id,
        unitId: unit.id,
        accountingReference: reference.text,
        idempotencyKey: PurchaseInvoiceApiService.generateIdempotencyKey(),
      ),
    );
    reference.dispose();
  }

  Future<void> _create(ProductReviewTask task) async {
    final groups = await _catalog.watchGroups(brandId: task.brandId).first;
    if (!mounted) return;
    ProductGroupModel? group = task.originalGroupText.isEmpty
        ? null
        : groups.firstOrNull;
    final name = TextEditingController(text: task.originalMaterialName);
    final legacyCode = TextEditingController();
    final primaryUnit = TextEditingController(text: task.originalUnitText);
    final unit2 = TextEditingController();
    final unit3 = TextEditingController();
    final reference = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إنشاء مادة كتالوج جديدة'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (groups.isNotEmpty || task.originalGroupText.isEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: group?.id ?? '',
                    decoration: const InputDecoration(labelText: 'المجموعة'),
                    items: [
                      if (task.originalGroupText.isEmpty)
                        const DropdownMenuItem(
                          value: '',
                          child: Text('غير مصنف (المجموعة الآمنة)'),
                        ),
                      ...groups.map(
                        (value) => DropdownMenuItem(
                          value: value.id,
                          child: Text(value.name),
                        ),
                      ),
                    ],
                    onChanged: (value) => group = value == null || value.isEmpty
                        ? null
                        : groups
                              .where((entry) => entry.id == value)
                              .firstOrNull,
                  )
                else if (task.originalGroupText.isNotEmpty)
                  const Text('يلزم إنشاء مجموعة كتالوج مناسبة أولًا.'),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'اسم المادة المصحح',
                  ),
                ),
                TextField(
                  controller: legacyCode,
                  decoration: const InputDecoration(
                    labelText: 'الكود القديم (اختياري)',
                  ),
                ),
                TextField(
                  controller: primaryUnit,
                  decoration: const InputDecoration(
                    labelText: 'الوحدة الأساسية',
                  ),
                ),
                TextField(
                  controller: unit2,
                  decoration: const InputDecoration(
                    labelText: 'الوحدة 2 (اختيارية)',
                  ),
                ),
                TextField(
                  controller: unit3,
                  decoration: const InputDecoration(
                    labelText: 'الوحدة 3 (اختيارية)',
                  ),
                ),
                TextField(
                  controller: reference,
                  decoration: const InputDecoration(
                    labelText: 'مرجع النظام المحاسبي (اختياري)',
                  ),
                ),
                const SizedBox(height: 8),
                const Text('لا تُطبق أي نسب تحويل؛ كل وحدة مستقلة.'),
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
            child: const Text('إنشاء وربط'),
          ),
        ],
      ),
    );
    if (accepted != true ||
        name.text.trim().isEmpty ||
        primaryUnit.text.trim().isEmpty ||
        (task.originalGroupText.isNotEmpty && group == null)) {
      return;
    }
    final invoiceRevision = await _invoiceRevision(task);
    if (invoiceRevision == null) return;
    final units = <CatalogUnit>[
      CatalogUnit(
        id: 'primary',
        displayValue: primaryUnit.text.trim(),
        rawValue: task.originalUnitText,
      ),
      if (unit2.text.trim().isNotEmpty)
        CatalogUnit(
          id: 'unit2',
          displayValue: unit2.text.trim(),
          rawValue: unit2.text.trim(),
        ),
      if (unit3.text.trim().isNotEmpty)
        CatalogUnit(
          id: 'unit3',
          displayValue: unit3.text.trim(),
          rawValue: unit3.text.trim(),
        ),
    ];
    await _run(
      task,
      () => _api.reviewTask(
        taskId: task.id,
        expectedRevision: task.revision,
        expectedInvoiceRevision: invoiceRevision,
        action: 'create_product',
        groupId: group?.id,
        materialName: name.text,
        legacyCode: legacyCode.text,
        units: units,
        primaryUnitId: 'primary',
        accountingReference: reference.text,
        idempotencyKey: PurchaseInvoiceApiService.generateIdempotencyKey(),
      ),
    );
    name.dispose();
    legacyCode.dispose();
    primaryUnit.dispose();
    unit2.dispose();
    unit3.dispose();
    reference.dispose();
  }

  Future<void> _simpleAction(
    ProductReviewTask task, {
    required String action,
    required String title,
  }) async {
    final note = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: note,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'الملاحظة الإلزامية'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (accepted != true || note.text.trim().isEmpty) return;
    final invoiceRevision = await _invoiceRevision(task);
    if (invoiceRevision == null) return;
    await _run(
      task,
      () => _api.reviewTask(
        taskId: task.id,
        expectedRevision: task.revision,
        expectedInvoiceRevision: invoiceRevision,
        action: action,
        note: note.text,
        idempotencyKey: PurchaseInvoiceApiService.generateIdempotencyKey(),
      ),
    );
    note.dispose();
  }

  Future<void> _synchronize(ProductReviewTask task) async {
    final reference = TextEditingController(text: task.accountingReference);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد المزامنة المحاسبية'),
        content: TextField(
          controller: reference,
          decoration: const InputDecoration(labelText: 'مرجع النظام المحاسبي'),
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
    if (accepted != true || reference.text.trim().isEmpty) return;
    final invoiceRevision = await _invoiceRevision(task);
    if (invoiceRevision == null) return;
    await _run(
      task,
      () => _api.reviewTask(
        taskId: task.id,
        expectedRevision: task.revision,
        expectedInvoiceRevision: invoiceRevision,
        action: 'mark_synchronized',
        accountingReference: reference.text,
        syncState: 'synced',
        idempotencyKey: PurchaseInvoiceApiService.generateIdempotencyKey(),
      ),
    );
    reference.dispose();
  }

  Future<void> _run(
    ProductReviewTask task,
    Future<Object?> Function() operation,
  ) async {
    setState(() => _submitting.add(task.id));
    try {
      await operation();
      if (mounted) _message('تم حفظ قرار المراجعة.');
    } catch (error) {
      if (mounted) _message(error.toString());
    } finally {
      if (mounted) setState(() => _submitting.remove(task.id));
    }
  }

  String _statusLabel(String status) => switch (status) {
    'pending_review' => 'بانتظار المراجعة',
    'clarification_requested' => 'طُلب توضيح',
    'linked_material' => 'مرتبطة بمادة موجودة',
    'newly_created_material' => 'أُنشئت مادة جديدة',
    'synchronized' => 'متزامنة محاسبيًا',
    _ => 'حالة غير معروفة',
  };

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }
}
