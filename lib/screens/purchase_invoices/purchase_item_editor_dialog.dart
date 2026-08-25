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
       unitText = '';

  const PurchaseItemEditorResult.unmatched({
    required this.materialName,
    required this.groupText,
    required this.unitText,
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
       initialUnitText = '';

  const PurchaseItemEditorDialog.unmatched({
    super.key,
    this.initialMaterialName = '',
    this.initialGroupText = '',
    this.initialUnitText = '',
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

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialMaterialName);
    _groupController = TextEditingController(text: widget.initialGroupText);
    _unitController = TextEditingController(text: widget.initialUnitText);
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
    final unitText = _unitController.text.trim();
    final validCatalogUnit =
        widget.isUnmatched ||
        widget.catalogUnits.isEmpty ||
        widget.catalogUnits.any((unit) => unit.id == _catalogUnitId);
    if (quantity == null ||
        quantity <= 0 ||
        (price != null && price < 0) ||
        !validCatalogUnit ||
        (widget.isUnmatched && (materialName.isEmpty || unitText.isEmpty))) {
      return;
    }
    final result = widget.isUnmatched
        ? PurchaseItemEditorResult.unmatched(
            materialName: materialName,
            groupText: _groupController.text.trim(),
            unitText: unitText,
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
                if (widget.isUnmatched) ...[
                  TextField(
                    key: const Key('purchase-item-name'),
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'اسم المادة'),
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
                  TextField(
                    key: const Key('purchase-item-unit'),
                    controller: _unitController,
                    decoration: const InputDecoration(
                      labelText: 'الوحدة كما وردت',
                    ),
                  ),
                  const SizedBox(height: 10),
                ] else if (widget.catalogUnits.length > 1) ...[
                  DropdownButtonFormField<String>(
                    key: const Key('purchase-item-catalog-unit'),
                    initialValue: _catalogUnitId,
                    decoration: const InputDecoration(labelText: 'الوحدة'),
                    items: widget.catalogUnits
                        .map(
                          (unit) => DropdownMenuItem(
                            value: unit.id,
                            child: Text(unit.displayValue),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) =>
                        setState(() => _catalogUnitId = value),
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
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات البند (اختيارية)',
                  ),
                ),
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
