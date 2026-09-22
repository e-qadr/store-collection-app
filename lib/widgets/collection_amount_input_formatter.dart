import 'package:flutter/services.dart';

/// Keeps Collection amount entry consistent across the collector and
/// accountant review forms while preserving the editing cursor position.
class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;

    final selectionText = newValue.text.replaceAll(',', '');
    final parts = selectionText.split('.');
    var formatted = parts[0].replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]},',
    );
    if (parts.length > 1) formatted += '.${parts[1]}';

    var commasBefore = 0;
    for (
      var index = 0;
      index < newValue.selection.end && index < newValue.text.length;
      index++
    ) {
      if (newValue.text[index] == ',') commasBefore++;
    }
    final rawCharsBefore = newValue.selection.end - commasBefore;
    var newSelectionIndex = 0;
    var count = 0;
    while (newSelectionIndex < formatted.length && count < rawCharsBefore) {
      if (formatted[newSelectionIndex] != ',') count++;
      newSelectionIndex++;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: newSelectionIndex),
    );
  }
}
