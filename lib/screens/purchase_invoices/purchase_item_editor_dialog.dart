import 'package:flutter/material.dart';

/// The validated, price-free values returned by a purchase-item editor.
///
/// The editor owns every [TextEditingController] used to collect these values.
/// A caller receives only this immutable result after the dialog route closes.
class PurchaseItemEditorResult {
  final bool isUnmatched;
  final double quantity;
  final double? provisionalPrice;
  final String materialName;
  final String groupText;
  final String unitText;

  const PurchaseItemEditorResult.catalog({
    required this.quantity,
    this.provisionalPrice,
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
  }) : isUnmatched = true;
}

/// A self-owned modal editor for one purchase-invoice item.
///
/// Keeping controller ownership inside this state prevents the caller from
/// disposing a controller while the dialog route is still dismissing.
class PurchaseItemEditorDialog extends StatefulWidget {
  final bool isUnmatched;
  final String title;

  const PurchaseItemEditorDialog.catalog({
    super.key,
    required String productName,
    required String unitValue,
  }) : isUnmatched = false,
       title = '$productName — $unitValue';

  const PurchaseItemEditorDialog.unmatched({super.key})
    : isUnmatched = true,
      title = 'مادة غير موجودة في الكتالوج';

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

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _groupController = TextEditingController();
    _unitController = TextEditingController();
    _quantityController = TextEditingController(text: '1');
    _provisionalPriceController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _groupController.dispose();
    _unitController.dispose();
    _quantityController.dispose();
    _provisionalPriceController.dispose();
    super.dispose();
  }

  void _submit() {
    final quantity = double.tryParse(_quantityController.text.trim());
    final priceText = _provisionalPriceController.text.trim();
    final price = priceText.isEmpty ? null : double.tryParse(priceText);
    final materialName = _nameController.text.trim();
    final unitText = _unitController.text.trim();
    if (quantity == null ||
        quantity <= 0 ||
        (price != null && price < 0) ||
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
          )
        : PurchaseItemEditorResult.catalog(
            quantity: quantity,
            provisionalPrice: price,
          );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
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
              TextField(
                key: const Key('purchase-item-provisional-price'),
                controller: _provisionalPriceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'سعر المورد الأولي (اختياري وسري)',
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
          child: const Text('إضافة'),
        ),
      ],
    );
  }
}
