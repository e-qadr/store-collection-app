import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:store_collection_app/utils/catalog_normalization.dart';

class ProductCatalogCollections {
  ProductCatalogCollections._();

  static const groups = 'product_groups';
  static const products = 'products';
  static const uniqueKeys = 'product_unique_keys';
  static const auditEvents = 'product_audit_events';
  static const accountingProfiles = 'product_accounting_profiles';
}

class ProductCatalogFields {
  ProductCatalogFields._();

  static const id = 'id';
  static const brandId = 'brand_id';
  static const groupId = 'group_id';
  static const name = 'name';
  static const normalizedName = 'normalized_name';
  static const legacyCode = 'legacy_code';
  static const units = 'units';
  static const primaryUnitId = 'primary_unit_id';
  static const active = 'active';
  static const version = 'version';
  static const nameUniqueKeyId = 'name_unique_key_id';
  static const legacyCodeUniqueKeyId = 'legacy_code_unique_key_id';
  static const sourceMetadata = 'source_metadata';
  static const lastAuditEventId = 'last_audit_event_id';
  static const isSystemGroup = 'is_system_group';
  static const systemKey = 'system_key';
  static const createdBy = 'created_by';
  static const createdByName = 'created_by_name';
  static const createdAt = 'created_at';
  static const updatedBy = 'updated_by';
  static const updatedByName = 'updated_by_name';
  static const updatedAt = 'updated_at';
  static const archivedBy = 'archived_by';
  static const archivedByName = 'archived_by_name';
  static const archivedAt = 'archived_at';
}

class ProductSourceMetadataFields {
  ProductSourceMetadataFields._();

  static const originalGroupMissing = 'original_group_missing';
  static const fallbackSystemGroupAssigned = 'fallback_system_group_assigned';
  static const fallbackSystemGroupKey = 'fallback_system_group_key';
  static const fallbackSystemGroupId = 'fallback_system_group_id';
  static const sourceFingerprint = 'source_fingerprint';
}

class CatalogActor {
  final String uid;
  final String name;
  final String role;
  final bool active;

  const CatalogActor({
    required this.uid,
    required this.name,
    required this.role,
    this.active = true,
  });

  bool get isAccountant => active && role == 'accountant';

  bool get canReadProtectedPrices =>
      active &&
      (role == 'collector' || role == 'accountant' || role == 'admin');

  bool get canWriteProtectedPrices => active && role == 'collector';
}

class UncategorizedProductGroupContract {
  UncategorizedProductGroupContract._();

  static const systemKey = uncategorizedProductGroupSystemKey;
  static const displayName = uncategorizedProductGroupDisplayName;

  static String documentIdForBrand(String brandId) =>
      uncategorizedProductGroupDocumentId(brandId);

  static bool isReservedIdentity({required String name, String? legacyCode}) {
    final normalizedName = normalizeCatalogText(name);
    return normalizedName == normalizeCatalogText(displayName) ||
        normalizedName == systemKey ||
        normalizeLegacyCode(legacyCode).toLowerCase() == systemKey;
  }

  static bool matchesExistingDocument({
    required String documentId,
    required String brandId,
    required Map<String, dynamic> data,
  }) {
    final cleanBrandId = brandId.trim();
    return documentId == documentIdForBrand(cleanBrandId) &&
        data[ProductCatalogFields.id] == documentId &&
        data[ProductCatalogFields.brandId] == cleanBrandId &&
        data[ProductCatalogFields.name] == displayName &&
        data[ProductCatalogFields.normalizedName] ==
            normalizeCatalogText(displayName) &&
        data[ProductCatalogFields.isSystemGroup] == true &&
        data[ProductCatalogFields.systemKey] == systemKey &&
        data[ProductCatalogFields.active] == true &&
        data[ProductCatalogFields.lastAuditEventId] is String &&
        (data[ProductCatalogFields.lastAuditEventId] as String).isNotEmpty;
  }
}

class CatalogUnit {
  final String id;
  final String displayValue;
  final String rawValue;

  /// Present only after an accountant explicitly approves a normalized value.
  final String? normalizedValue;

  const CatalogUnit({
    required this.id,
    required this.displayValue,
    required this.rawValue,
    this.normalizedValue,
  });

  factory CatalogUnit.fromMap(Map<dynamic, dynamic> data) {
    return CatalogUnit(
      id: data['unit_id']?.toString() ?? '',
      displayValue: data['display_value']?.toString() ?? '',
      rawValue:
          data['raw_value']?.toString() ??
          data['display_value']?.toString() ??
          '',
      normalizedValue: _nonEmptyString(data['normalized_value']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'unit_id': id,
      'display_value': displayValue,
      'raw_value': rawValue,
      if (normalizedValue != null && normalizedValue!.trim().isNotEmpty)
        'normalized_value': normalizedValue!.trim(),
    };
  }
}

class ProductGroupModel {
  final String id;
  final String brandId;
  final String name;
  final String normalizedName;
  final String? legacyCode;
  final bool active;
  final String lastAuditEventId;
  final bool isSystemGroup;
  final String? systemKey;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ProductGroupModel({
    required this.id,
    required this.brandId,
    required this.name,
    required this.normalizedName,
    this.legacyCode,
    this.active = true,
    this.lastAuditEventId = '',
    this.isSystemGroup = false,
    this.systemKey,
    this.createdAt,
    this.updatedAt,
  });

  factory ProductGroupModel.fromMap(
    String documentId,
    Map<String, dynamic> data,
  ) {
    return ProductGroupModel(
      id: data[ProductCatalogFields.id]?.toString() ?? documentId,
      brandId: data[ProductCatalogFields.brandId]?.toString() ?? '',
      name: data[ProductCatalogFields.name]?.toString() ?? '',
      normalizedName:
          data[ProductCatalogFields.normalizedName]?.toString() ?? '',
      legacyCode: _nonEmptyString(data[ProductCatalogFields.legacyCode]),
      active: data[ProductCatalogFields.active] as bool? ?? true,
      lastAuditEventId:
          data[ProductCatalogFields.lastAuditEventId]?.toString() ?? '',
      isSystemGroup: data[ProductCatalogFields.isSystemGroup] as bool? ?? false,
      systemKey: _nonEmptyString(data[ProductCatalogFields.systemKey]),
      createdAt: _dateTimeOf(data[ProductCatalogFields.createdAt]),
      updatedAt: _dateTimeOf(data[ProductCatalogFields.updatedAt]),
    );
  }

  bool get canBeArchived => !isSystemGroup;
}

class ProductCatalogModel {
  final String id;
  final String brandId;
  final String groupId;
  final String name;
  final String normalizedName;
  final String? legacyCode;
  final List<CatalogUnit> units;
  final String primaryUnitId;
  final bool active;
  final int version;
  final String nameUniqueKeyId;
  final String? legacyCodeUniqueKeyId;
  final Map<String, dynamic> sourceMetadata;
  final String lastAuditEventId;
  final String createdBy;
  final String createdByName;
  final DateTime? createdAt;
  final String updatedBy;
  final String updatedByName;
  final DateTime? updatedAt;
  final String? archivedBy;
  final String? archivedByName;
  final DateTime? archivedAt;

  const ProductCatalogModel({
    required this.id,
    required this.brandId,
    required this.groupId,
    required this.name,
    required this.normalizedName,
    required this.units,
    required this.primaryUnitId,
    required this.nameUniqueKeyId,
    this.legacyCode,
    this.active = true,
    this.version = 1,
    this.legacyCodeUniqueKeyId,
    this.sourceMetadata = const {},
    this.lastAuditEventId = '',
    this.createdBy = '',
    this.createdByName = '',
    this.createdAt,
    this.updatedBy = '',
    this.updatedByName = '',
    this.updatedAt,
    this.archivedBy,
    this.archivedByName,
    this.archivedAt,
  });

  factory ProductCatalogModel.fromMap(
    String documentId,
    Map<String, dynamic> data,
  ) {
    final rawUnits = data[ProductCatalogFields.units];
    return ProductCatalogModel(
      id: data[ProductCatalogFields.id]?.toString() ?? documentId,
      brandId: data[ProductCatalogFields.brandId]?.toString() ?? '',
      groupId: data[ProductCatalogFields.groupId]?.toString() ?? '',
      name: data[ProductCatalogFields.name]?.toString() ?? '',
      normalizedName:
          data[ProductCatalogFields.normalizedName]?.toString() ?? '',
      legacyCode: _nonEmptyString(data[ProductCatalogFields.legacyCode]),
      units: rawUnits is List
          ? rawUnits
                .whereType<Map>()
                .map(CatalogUnit.fromMap)
                .toList(growable: false)
          : const [],
      primaryUnitId: data[ProductCatalogFields.primaryUnitId]?.toString() ?? '',
      active: data[ProductCatalogFields.active] as bool? ?? true,
      version: (data[ProductCatalogFields.version] as num?)?.toInt() ?? 1,
      nameUniqueKeyId:
          data[ProductCatalogFields.nameUniqueKeyId]?.toString() ?? '',
      legacyCodeUniqueKeyId: _nonEmptyString(
        data[ProductCatalogFields.legacyCodeUniqueKeyId],
      ),
      sourceMetadata: _stringMap(data[ProductCatalogFields.sourceMetadata]),
      lastAuditEventId:
          data[ProductCatalogFields.lastAuditEventId]?.toString() ?? '',
      createdBy: data[ProductCatalogFields.createdBy]?.toString() ?? '',
      createdByName: data[ProductCatalogFields.createdByName]?.toString() ?? '',
      createdAt: _dateTimeOf(data[ProductCatalogFields.createdAt]),
      updatedBy: data[ProductCatalogFields.updatedBy]?.toString() ?? '',
      updatedByName: data[ProductCatalogFields.updatedByName]?.toString() ?? '',
      updatedAt: _dateTimeOf(data[ProductCatalogFields.updatedAt]),
      archivedBy: _nonEmptyString(data[ProductCatalogFields.archivedBy]),
      archivedByName: _nonEmptyString(
        data[ProductCatalogFields.archivedByName],
      ),
      archivedAt: _dateTimeOf(data[ProductCatalogFields.archivedAt]),
    );
  }

  CatalogUnit? unitById(String unitId) {
    for (final unit in units) {
      if (unit.id == unitId) return unit;
    }
    return null;
  }
}

class ProductAuditEvent {
  final String id;
  final String entityType;
  final String entityId;
  final String brandId;
  final String action;
  final Map<String, dynamic> before;
  final Map<String, dynamic> after;
  final String? reason;
  final String actorUid;
  final String actorName;
  final String actorRole;
  final DateTime? createdAt;

  const ProductAuditEvent({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.brandId,
    required this.action,
    required this.actorUid,
    required this.actorName,
    required this.actorRole,
    this.before = const {},
    this.after = const {},
    this.reason,
    this.createdAt,
  });

  factory ProductAuditEvent.fromMap(
    String documentId,
    Map<String, dynamic> data,
  ) {
    return ProductAuditEvent(
      id: data['id']?.toString() ?? documentId,
      entityType: data['entity_type']?.toString() ?? '',
      entityId: data['entity_id']?.toString() ?? '',
      brandId: data['brand_id']?.toString() ?? '',
      action: data['action']?.toString() ?? '',
      before: _stringMap(data['before']),
      after: _stringMap(data['after']),
      reason: _nonEmptyString(data['reason']),
      actorUid: data['actor_uid']?.toString() ?? '',
      actorName: data['actor_name']?.toString() ?? '',
      actorRole: data['actor_role']?.toString() ?? '',
      createdAt: _dateTimeOf(data['created_at']),
    );
  }
}

class ProductAccountingProfile {
  final String id;
  final String productId;
  final String brandId;
  final String? accountingReference;
  final String syncState;
  final String? notes;
  final DateTime? updatedAt;
  final String lastAuditEventId;

  const ProductAccountingProfile({
    this.id = '',
    required this.productId,
    required this.brandId,
    this.accountingReference,
    this.syncState = 'not_synced',
    this.notes,
    this.updatedAt,
    this.lastAuditEventId = '',
  });

  factory ProductAccountingProfile.fromMap(Map<String, dynamic> data) {
    return ProductAccountingProfile(
      id: data['id']?.toString() ?? data['product_id']?.toString() ?? '',
      productId: data['product_id']?.toString() ?? '',
      brandId: data['brand_id']?.toString() ?? '',
      accountingReference: _nonEmptyString(data['accounting_reference']),
      syncState: data['sync_state']?.toString() ?? 'not_synced',
      notes: _nonEmptyString(data['notes']),
      updatedAt: _dateTimeOf(data['updated_at']),
      lastAuditEventId: data['last_audit_event_id']?.toString() ?? '',
    );
  }
}

DateTime? _dateTimeOf(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

String? _nonEmptyString(dynamic value) {
  final result = value?.toString().trim();
  return result == null || result.isEmpty ? null : result;
}

Map<String, dynamic> _stringMap(dynamic value) {
  if (value is! Map) return const {};
  return Map<String, dynamic>.from(value);
}
