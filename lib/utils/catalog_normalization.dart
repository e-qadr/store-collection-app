import 'dart:convert';

const uncategorizedProductGroupSystemKey = 'uncategorized';
const uncategorizedProductGroupDisplayName = 'غير مصنف';

/// Stable Firestore document ID for the single system fallback group of a brand.
String uncategorizedProductGroupDocumentId(String brandId) {
  final cleanBrandId = brandId.trim();
  if (cleanBrandId.isEmpty) throw ArgumentError('Brand ID is required.');
  if (cleanBrandId.contains('/')) {
    throw ArgumentError('Brand ID cannot contain a path separator.');
  }
  return 'system-group-$cleanBrandId-$uncategorizedProductGroupSystemKey';
}

/// Stable Firestore document ID for a normal, brand-scoped product group.
///
/// The display name is normalized only for identity generation. Callers must
/// continue to preserve the original Arabic display value separately.
String productGroupDocumentId({
  required String brandId,
  required String groupName,
}) {
  final cleanBrandId = brandId.trim();
  if (cleanBrandId.isEmpty) throw ArgumentError('Brand ID is required.');
  if (cleanBrandId.contains('/')) {
    throw ArgumentError('Brand ID cannot contain a path separator.');
  }
  final normalizedName = normalizeCatalogText(groupName);
  if (normalizedName.isEmpty) throw ArgumentError('Group name is required.');
  return 'group-${catalogKeyFragment('$cleanBrandId\u001F$normalizedName')}';
}

/// Normalization used only for duplicate detection and deterministic keys.
///
/// The original display value is always stored separately. In particular, this
/// helper must not be used to silently replace an Arabic product or unit name.
String normalizeCatalogText(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u06D6-\u06ED]'), '')
      .replaceAll('\u0640', '')
      .replaceAll(RegExp('[\u0622\u0623\u0625\u0671]'), '\u0627')
      .replaceAll('\u0649', '\u064A')
      .replaceAll(RegExp(r'\s+'), ' ');
}

String normalizeLegacyCode(String? value) {
  if (value == null) return '';
  return value.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
}

/// Firestore-safe, reversible key fragment with no slash characters.
String catalogKeyFragment(String value) {
  final encoded = base64Url.encode(utf8.encode(value));
  return encoded.replaceAll('=', '');
}

String productUniqueKeyId({
  required String brandId,
  required String keyType,
  required String normalizedValue,
}) {
  final brand = brandId.trim();
  final type = keyType.trim();
  if (brand.isEmpty || type.isEmpty || normalizedValue.isEmpty) {
    throw ArgumentError('Brand, key type, and normalized value are required.');
  }
  return '${catalogKeyFragment(brand)}-$type-${catalogKeyFragment(normalizedValue)}';
}

String productPriceLatestKey({
  required String brandId,
  required String productId,
  required String unitId,
  required String currency,
}) {
  final parts = [
    brandId,
    productId,
    unitId,
    currency,
  ].map((value) => value.trim()).toList(growable: false);
  if (parts.any((value) => value.isEmpty)) {
    throw ArgumentError('Brand, product, unit, and currency are required.');
  }
  return catalogKeyFragment(parts.join('\u001F'));
}
