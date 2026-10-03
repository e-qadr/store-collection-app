import 'package:flutter/material.dart';
import 'package:store_collection_app/models/purchase_invoice_model.dart';
import 'package:store_collection_app/screens/purchase_invoices/purchase_catalog_picker.dart';
import 'package:store_collection_app/screens/products/catalog_product_editor_dialog.dart';
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
  String _filter = 'open';

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
            final filtered = tasks
                .where(_matchesFilter)
                .toList(growable: false);
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                _intro(tasks),
                const SizedBox(height: 16),
                _filters(tasks),
                const SizedBox(height: 18),
                if (filtered.isEmpty)
                  _emptyQueue()
                else
                  ...filtered.map(_taskCard),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _intro(List<ProductReviewTask> tasks) {
    final open = tasks.where((task) => _isOpen(task.status)).length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primaryOlive,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.fact_check_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'قرار واضح لكل مادة غير مطابقة',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  open == 0
                      ? 'كل المواد المعروضة تمت معالجتها أو مزامنتها.'
                      : '$open مواد تحتاج قراراً قبل اكتمال معالجتها.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.84)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filters(List<ProductReviewTask> tasks) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      _filterChip(
        'open',
        'تحتاج قراراً',
        tasks.where((task) => _isOpen(task.status)).length,
      ),
      _filterChip(
        'clarification',
        'بانتظار توضيح',
        tasks.where((task) => task.status == 'clarification_requested').length,
      ),
      _filterChip(
        'ready',
        'أُضيفت للكتالوج',
        tasks
            .where(
              (task) => const {
                'linked_material',
                'newly_created_material',
              }.contains(task.status),
            )
            .length,
      ),
      _filterChip(
        'done',
        'مكتملة',
        tasks.where((task) => task.status == 'synchronized').length,
      ),
      _filterChip('all', 'الكل', tasks.length),
    ],
  );

  Widget _filterChip(String value, String label, int count) => ChoiceChip(
    selected: _filter == value,
    onSelected: (_) => setState(() => _filter = value),
    label: Text('$label ($count)'),
  );

  bool _matchesFilter(ProductReviewTask task) => switch (_filter) {
    'open' => _isOpen(task.status),
    'clarification' => task.status == 'clarification_requested',
    'ready' => const {
      'linked_material',
      'newly_created_material',
    }.contains(task.status),
    'done' => task.status == 'synchronized',
    _ => true,
  };

  bool _isOpen(String status) =>
      const {'pending_review', 'clarification_requested'}.contains(status);

  Widget _emptyQueue() => Card(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          const Icon(
            Icons.task_alt_rounded,
            size: 46,
            color: AppTheme.oliveGreen,
          ),
          const SizedBox(height: 10),
          const Text(
            'لا توجد مواد ضمن هذا التصنيف',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            _filter == 'open'
                ? 'المواد غير المطابقة الجديدة ستظهر هنا للمراجعة.'
                : 'اختر تصنيفاً آخر أو راجع المواد المكتملة.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textHint),
          ),
        ],
      ),
    ),
  );

  Widget _taskCard(ProductReviewTask task) {
    final color = _statusColor(task.status);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_statusIcon(task.status), color: color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.originalMaterialName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'وردت من الفاتورة برقم ${task.invoiceId.isEmpty ? '-' : task.invoiceId}',
                        style: const TextStyle(
                          color: AppTheme.textHint,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                _statusBadge(task, color),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _fact(
                      'المجموعة الواردة',
                      task.originalGroupText.isEmpty
                          ? 'غير محددة'
                          : task.originalGroupText,
                    ),
                  ),
                  Container(width: 1, height: 34, color: AppTheme.dividerColor),
                  Expanded(
                    child: _fact(
                      'الوحدة الواردة',
                      task.originalUnitText.isEmpty
                          ? 'غير محددة'
                          : task.originalUnitText,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _taskInstruction(task),
              style: const TextStyle(color: AppTheme.textHint, height: 1.4),
            ),
            const SizedBox(height: 12),
            if (_submitting.contains(task.id))
              const Center(child: CircularProgressIndicator())
            else
              Wrap(spacing: 8, runSpacing: 8, children: _actions(task)),
          ],
        ),
      ),
    );
  }

  Widget _fact(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppTheme.textHint, fontSize: 11),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );

  Widget _statusBadge(ProductReviewTask task, Color color) => Container(
    constraints: const BoxConstraints(maxWidth: 116),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(
      _statusLabel(task.status),
      textAlign: TextAlign.center,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
    ),
  );

  Color _statusColor(String status) => switch (status) {
    'pending_review' => AppTheme.warningColor,
    'clarification_requested' => AppTheme.errorColor,
    'linked_material' || 'newly_created_material' => AppTheme.primaryOlive,
    'synchronized' => AppTheme.successColor,
    _ => AppTheme.textHint,
  };

  IconData _statusIcon(String status) => switch (status) {
    'pending_review' => Icons.pending_actions_rounded,
    'clarification_requested' => Icons.question_answer_rounded,
    'linked_material' => Icons.link_rounded,
    'newly_created_material' => Icons.add_box_rounded,
    'synchronized' => Icons.verified_rounded,
    _ => Icons.help_outline_rounded,
  };

  String _taskInstruction(ProductReviewTask task) => switch (task.status) {
    'pending_review' =>
      'اختر المادة الموجودة المطابقة، أو أنشئ مادة كتالوج جديدة إذا لم تكن موجودة.',
    'clarification_requested' =>
      'بانتظار معلومات إضافية قبل اتخاذ قرار الربط أو الإنشاء.',
    'linked_material' =>
      'تم ربطها بالكتالوج. ستظهر في فروع العلامة، ويربطها محاسب كل فرع محاسبيًا.',
    'newly_created_material' =>
      'أُنشئت مادة الكتالوج. ستظهر في فروع العلامة، ويربطها محاسب كل فرع محاسبيًا.',
    'synchronized' => 'اكتملت معالجة المادة ومزامنتها محاسبياً.',
    _ => 'راجع حالة هذه المادة قبل المتابعة.',
  };

  List<Widget> _actions(ProductReviewTask task) {
    if (task.status == 'pending_review') {
      return [
        FilledButton.tonalIcon(
          key: Key('link-${task.id}'),
          onPressed: () => _link(task),
          icon: const Icon(Icons.link_rounded),
          label: const Text('ربط بمادة موجودة'),
        ),
        FilledButton.tonalIcon(
          key: Key('create-${task.id}'),
          onPressed: () => _create(task),
          icon: const Icon(Icons.add_box_rounded),
          label: const Text('إنشاء مادة جديدة'),
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
      return const [];
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
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${product.name} — ${unit.displayValue}'),
        content: const Text(
          'سيُربط هذا السطر بمادة الكتالوج. الربط المحاسبي يُنجزه محاسب كل فرع من لوحة المواد.',
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
        idempotencyKey: PurchaseInvoiceApiService.generateIdempotencyKey(),
      ),
    );
  }

  Future<void> _create(ProductReviewTask task) async {
    final groups = await _catalog.watchGroups(brandId: task.brandId).first;
    if (!mounted) return;
    if (groups.where((group) => group.active).isEmpty) {
      _message('لا توجد مجموعة مواد نشطة لهذه العلامة. أضف المجموعة أولاً.');
      return;
    }
    final draft = await showCatalogProductEditor(
      context,
      groups: groups,
      initialName: task.originalMaterialName,
      initialPrimaryUnit: task.originalUnitText,
    );
    if (!mounted || draft == null) return;
    final invoiceRevision = await _invoiceRevision(task);
    if (invoiceRevision == null) return;
    await _run(
      task,
      () => _api.reviewTask(
        taskId: task.id,
        expectedRevision: task.revision,
        expectedInvoiceRevision: invoiceRevision,
        action: 'create_product',
        groupId: draft.groupId,
        materialName: draft.name,
        legacyCode: draft.legacyCode,
        units: draft.units,
        primaryUnitId: draft.primaryUnitId,
        idempotencyKey: PurchaseInvoiceApiService.generateIdempotencyKey(),
      ),
    );
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
    'linked_material' => 'أُضيفت للكتالوج',
    'newly_created_material' => 'أُنشئت في الكتالوج',
    'synchronized' => 'متزامنة محاسبيًا',
    _ => 'حالة غير معروفة',
  };

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }
}
