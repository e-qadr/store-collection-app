import 'package:flutter/material.dart';
import 'package:store_collection_app/models/product_catalog_model.dart';

/// Immutable values returned after an item editor route has completely closed.
/// Controllers remain owned by the dialog to avoid use-after-dispose errors.
class PurchaseItemEditorResult {
  final bool isUnmatched;
  final double quantity;
  final double? provisionalPrice;
  final String materialName;
  final String groupText;
  final String unitText;
  final List<CatalogUnit> proposedUnits;
  final String? catalogUnitId;
  final String lineNotes;

  const PurchaseItemEditorResult.catalog({
    required this.quantity,
    this.provisionalPrice,
    this.catalogUnitId,
    this.lineNotes = '',
  }) : isUnmatched = false,
       materialName = '',
       groupText = '',
       unitText = '',
       proposedUnits = const [];

  const PurchaseItemEditorResult.unmatched({
    required this.materialName,
    required this.groupText,
    required this.unitText,
    this.proposedUnits = const [],
    required this.quantity,
    this.provisionalPrice,
    this.lineNotes = '',
  }) : isUnmatched = true,
       catalogUnitId = null;
}

class PurchaseItemEditorDialog extends StatefulWidget {
  final bool isUnmatched;
  final String title;
  final List<CatalogUnit> catalogUnits;
  final String? initialCatalogUnitId;
  final double initialQuantity;
  final double? initialProvisionalPrice;
  final String initialMaterialName;
  final String initialGroupText;
  final String initialUnitText;
  final List<CatalogUnit> initialProposedUnits;
  final String initialLineNotes;
  final String? priceHelperText;
  final bool showPricing;
  final String confirmLabel;

  const PurchaseItemEditorDialog.catalog({
    super.key,
    required String productName,
    required String unitValue,
    this.catalogUnits = const [],
    this.initialCatalogUnitId,
    this.initialQuantity = 1,
    this.initialProvisionalPrice,
    this.initialLineNotes = '',
    this.priceHelperText,
    this.showPricing = true,
    this.confirmLabel = 'حفظ',
  }) : isUnmatched = false,
       title = '$productName — $unitValue',
       initialMaterialName = '',
       initialGroupText = '',
       initialUnitText = '',
       initialProposedUnits = const [];

  const PurchaseItemEditorDialog.unmatched({
    super.key,
    this.initialMaterialName = '',
    this.initialGroupText = '',
    this.initialUnitText = '',
    this.initialProposedUnits = const [],
    this.initialQuantity = 1,
    this.initialProvisionalPrice,
    this.initialLineNotes = '',
    this.priceHelperText,
    this.showPricing = true,
    this.confirmLabel = 'حفظ',
  }) : isUnmatched = true,
       title = 'مادة غير موجودة في الكتالوج',
       catalogUnits = const [],
       initialCatalogUnitId = null;

  @override
  State<PurchaseItemEditorDialog> createState() =>
      _PurchaseItemEditorDialogState();
}

class _PurchaseItemEditorDialogState extends State<PurchaseItemEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _groupController;
  late final TextEditingController _unitController;
  late final TextEditingController _quantityController;
  late final TextEditingController _provisionalPriceController;
  late final TextEditingController _notesController;
  String? _catalogUnitId;
  String? _validationError;
  late List<_UnmatchedUnitDraft> _proposedUnits;
  int _invoiceUnitIndex = 0;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialMaterialName);
    _groupController = TextEditingController(text: widget.initialGroupText);
    _unitController = TextEditingController(text: widget.initialUnitText);
    _proposedUnits = widget.isUnmatched
        ? (widget.initialProposedUnits.isEmpty
              ? [
                  _UnmatchedUnitDraft.primary(
                    widget.initialUnitText.trim().isEmpty
                        ? ''
                        : widget.initialUnitText.trim(),
                  ),
                ]
              : widget.initialProposedUnits
                    .map(_UnmatchedUnitDraft.fromUnit)
                    .toList(growable: true))
        : const [];
    final initialInvoiceUnit = widget.initialUnitText.trim();
    final selected = _proposedUnits.indexWhere(
      (unit) => unit.nameController.text.trim() == initialInvoiceUnit,
    );
    _invoiceUnitIndex = selected < 0 ? 0 : selected;
    _quantityController = TextEditingController(
      text: _number(widget.initialQuantity),
    );
    _provisionalPriceController = TextEditingController(
      text: widget.initialProvisionalPrice == null
          ? ''
          : _number(widget.initialProvisionalPrice!),
    );
    _notesController = TextEditingController(text: widget.initialLineNotes);
    _catalogUnitId =
        widget.initialCatalogUnitId ??
        (widget.catalogUnits.length == 1
            ? widget.catalogUnits.single.id
            : null);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _groupController.dispose();
    _unitController.dispose();
    for (final unit in _proposedUnits) {
      unit.dispose();
    }
    _quantityController.dispose();
    _provisionalPriceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _submit() {
    final quantity = double.tryParse(_quantityController.text.trim());
    final priceText = _provisionalPriceController.text.trim();
    final price = priceText.isEmpty ? null : double.tryParse(priceText);
    final materialName = _nameController.text.trim();
    final proposedUnits = widget.isUnmatched
        ? _proposedUnits
        : const <_UnmatchedUnitDraft>[];
    final unitText = widget.isUnmatched
        ? (_invoiceUnitIndex >= 0 && _invoiceUnitIndex < proposedUnits.length
              ? proposedUnits[_invoiceUnitIndex].nameController.text.trim()
              : '')
        : _unitController.text.trim();
    final validCatalogUnit =
        widget.isUnmatched ||
        widget.catalogUnits.isEmpty ||
        widget.catalogUnits.any((unit) => unit.id == _catalogUnitId);
    if (quantity == null ||
        quantity <= 0 ||
        (price != null && price < 0) ||
        !validCatalogUnit ||
        (widget.isUnmatched && (materialName.isEmpty || unitText.isEmpty))) {
      setState(() {
        _validationError = widget.isUnmatched
            ? 'اكتب اسم المادة ووحدتها، ثم أدخل كمية صحيحة.'
            : 'اختر وحدة صحيحة وأدخل كمية صحيحة.';
      });
      return;
    }
    if (widget.isUnmatched) {
      final invalidUnit = proposedUnits.any((unit) {
        final factor = double.tryParse(unit.factorController.text.trim());
        return unit.nameController.text.trim().isEmpty ||
            factor == null ||
            !factor.isFinite ||
            factor <= 0;
      });
      if (invalidUnit) {
        setState(() {
          _validationError = 'أدخل اسم كل وحدة ومعامل تحويل موجباً.';
        });
        return;
      }
    }
    final result = widget.isUnmatched
        ? PurchaseItemEditorResult.unmatched(
            materialName: materialName,
            groupText: _groupController.text.trim(),
            unitText: unitText,
            proposedUnits: proposedUnits
                .map(
                  (unit) => CatalogUnit(
                    id: unit.id,
                    displayValue: unit.nameController.text.trim(),
                    rawValue: unit.nameController.text.trim(),
                    baseUnitFactor: unit == proposedUnits.first
                        ? 1
                        : double.parse(unit.factorController.text.trim()),
                  ),
                )
                .toList(growable: false),
            quantity: quantity,
            provisionalPrice: price,
            lineNotes: _notesController.text.trim(),
          )
        : PurchaseItemEditorResult.catalog(
            quantity: quantity,
            provisionalPrice: price,
            catalogUnitId: _catalogUnitId,
            lineNotes: _notesController.text.trim(),
          );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: widget.isUnmatched
                        ? Colors.orange.withValues(alpha: 0.09)
                        : Colors.green.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        widget.isUnmatched
                            ? Icons.pending_actions_rounded
                            : Icons.inventory_2_rounded,
                        color: widget.isUnmatched
                            ? Colors.orange.shade800
                            : Colors.green.shade700,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          widget.isUnmatched
                              ? 'سجّل وحدات المادة وتحويلاتها الآن. ستبقى مع طلب المراجعة حتى يعتمدها المحاسب في الكتالوج.'
                              : 'هذه مادة موجودة في الكتالوج. اختر الوحدة والكمية المطلوبة للفاتورة.',
                          style: const TextStyle(height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (widget.isUnmatched) ...[
                  TextField(
                    key: const Key('purchase-item-name'),
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'اسم المادة كما ورد *',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const Key('purchase-item-group'),
                    controller: _groupController,
                    decoration: const InputDecoration(
                      labelText: 'المجموعة (اختيارية)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'وحدات المادة',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._proposedUnits.indexed.expand((entry) {
                    final index = entry.$1;
                    final unit = entry.$2;
                    return [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: index == 0
                              ? Colors.green.withValues(alpha: .06)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                IconButton(
                                  tooltip: 'استخدم كوحدة الفاتورة',
                                  onPressed: () =>
                                      setState(() => _invoiceUnitIndex = index),
                                  icon: Icon(
                                    _invoiceUnitIndex == index
                                        ? Icons.radio_button_checked_rounded
                                        : Icons.radio_button_unchecked_rounded,
                                    color: _invoiceUnitIndex == index
                                        ? Colors.green.shade700
                                        : null,
                                  ),
                                ),
                                const Expanded(
                                  child: Text('وحدة هذه الفاتورة'),
                                ),
                                if (index > 0)
                                  IconButton(
                                    tooltip: 'حذف الوحدة',
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                    ),
                                    onPressed: () => setState(() {
                                      _proposedUnits.removeAt(index).dispose();
                                      if (_invoiceUnitIndex >=
                                          _proposedUnits.length) {
                                        _invoiceUnitIndex = 0;
                                      }
                                    }),
                                  ),
                              ],
                            ),
                            TextField(
                              key: index == 0
                                  ? const Key('purchase-item-unit')
                                  : null,
                              controller: unit.nameController,
                              decoration: InputDecoration(
                                labelText: index == 0
                                    ? 'الوحدة الأساسية *'
                                    : 'اسم الوحدة الإضافية *',
                                helperText: index == 0
                                    ? 'تمثل وحدة واحدة دائماً.'
                                    : 'مثل كرتون أو صندوق.',
                              ),
                            ),
                            if (index > 0) ...[
                              const SizedBox(height: 8),
                              TextField(
                                controller: unit.factorController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'تعادل كم وحدة أساسية؟ *',
                                  helperText:
                                      'مثال: كرتون فيه 12 حبة، اكتب 12.',
                                  prefixIcon: Icon(Icons.swap_horiz_rounded),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ];
                  }),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: _proposedUnits.length >= maxCatalogUnits
                          ? null
                          : () => setState(() {
                              _proposedUnits.add(
                                _UnmatchedUnitDraft.additional(
                                  _proposedUnits.length,
                                ),
                              );
                            }),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('إضافة وحدة أخرى'),
                    ),
                  ),
                  const SizedBox(height: 10),
                ] else if (widget.catalogUnits.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    key: const Key('purchase-item-catalog-unit'),
                    initialValue: _catalogUnitId,
                    decoration: InputDecoration(
                      labelText: 'وحدة المادة',
                      helperText: widget.catalogUnits.length == 1
                          ? 'هذه هي الوحدة المتاحة للمادة.'
                          : 'اختر الوحدة المطلوبة لهذه المادة.',
                    ),
                    items: widget.catalogUnits
                        .map(
                          (unit) => DropdownMenuItem(
                            value: unit.id,
                            child: Text(unit.displayValue),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: widget.catalogUnits.length == 1
                        ? null
                        : (value) => setState(() => _catalogUnitId = value),
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(
                  key: const Key('purchase-item-quantity'),
                  controller: _quantityController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'الكمية'),
                ),
                const SizedBox(height: 10),
                if (widget.showPricing) ...[
                  TextField(
                    key: const Key('purchase-item-provisional-price'),
                    controller: _provisionalPriceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'سعر الوحدة (اختياري وسري)',
                      helperText: widget.priceHelperText,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(
                  key: const Key('purchase-item-notes'),
                  controller: _notesController,
                  minLines: 2,
                  maxLines: 5,
                  maxLength: 1000,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات البند (اختيارية)',
                    helperText: 'يمكن كتابة ملاحظة تفصيلية حتى 1000 حرف.',
                  ),
                ),
                if (_validationError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _validationError!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('cancel-purchase-item'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            key: const Key('confirm-purchase-item'),
            onPressed: _submit,
            child: Text(widget.confirmLabel),
          ),
        ],
      ),
    );
  }
}

String _number(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();

class _UnmatchedUnitDraft {
  final String id;
  final TextEditingController nameController;
  final TextEditingController factorController;

  _UnmatchedUnitDraft._({
    required this.id,
    required String name,
    required double factor,
  }) : nameController = TextEditingController(text: name),
       factorController = TextEditingController(
         text: factor == factor.roundToDouble()
             ? factor.toInt().toString()
             : factor.toString(),
       );

  factory _UnmatchedUnitDraft.primary(String name) =>
      _UnmatchedUnitDraft._(id: 'primary', name: name, factor: 1);

  factory _UnmatchedUnitDraft.additional(int index) =>
      _UnmatchedUnitDraft._(id: 'unit_${index + 1}', name: '', factor: 1);

  factory _UnmatchedUnitDraft.fromUnit(CatalogUnit unit) =>
      _UnmatchedUnitDraft._(
        id: unit.id,
        name: unit.rawValue,
        factor: unit.baseUnitFactor,
      );

  void dispose() {
    nameController.dispose();
    factorController.dispose();
  }
}
