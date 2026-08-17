import 'dart:convert';
import 'dart:io';

import '../utils/catalog_normalization.dart';

const legacyCatalogUncategorizedGroupKey = uncategorizedProductGroupSystemKey;
const legacyCatalogUncategorizedGroupName =
    uncategorizedProductGroupDisplayName;

String legacyCatalogUncategorizedGroupId(String brandId) =>
    uncategorizedProductGroupDocumentId(brandId);

enum LegacyCatalogSourceProfileId {
  alAsalahLegacyCatalog('al_asalah_legacy_catalog'),
  eqlidLegacyCatalog('eqlid_legacy_catalog');

  const LegacyCatalogSourceProfileId(this.value);

  final String value;

  static LegacyCatalogSourceProfileId parse(String value) {
    return values.firstWhere(
      (candidate) => candidate.value == value,
      orElse: () => throw LegacyCatalogImportException(
        'Unknown legacy catalog source profile: $value',
      ),
    );
  }
}

class LegacyCatalogSourceProfile {
  final LegacyCatalogSourceProfileId id;
  final String expectedBrandId;
  final String expectedBrandName;
  final String worksheetName;
  final int unit3Column;
  final int unit2Column;
  final int primaryUnitColumn;
  final int materialColumn;
  final int groupColumn;

  const LegacyCatalogSourceProfile({
    required this.id,
    required this.expectedBrandId,
    required this.expectedBrandName,
    this.worksheetName = 'Page1',
    required this.unit3Column,
    required this.unit2Column,
    required this.primaryUnitColumn,
    required this.materialColumn,
    required this.groupColumn,
  });

  static const alAsalah = LegacyCatalogSourceProfile(
    id: LegacyCatalogSourceProfileId.alAsalahLegacyCatalog,
    expectedBrandId: 'TlOswncJiWX7mwsf3U4e',
    expectedBrandName: 'الأصالة',
    unit3Column: 1,
    unit2Column: 4,
    primaryUnitColumn: 6,
    materialColumn: 7,
    groupColumn: 13,
  );

  static const eqlid = LegacyCatalogSourceProfile(
    id: LegacyCatalogSourceProfileId.eqlidLegacyCatalog,
    expectedBrandId: 'WLMnMVT6u1H2VQ0qziJ3',
    expectedBrandName: 'إقليد',
    unit3Column: 1,
    unit2Column: 4,
    primaryUnitColumn: 6,
    materialColumn: 8,
    groupColumn: 12,
  );

  static LegacyCatalogSourceProfile forId(
    LegacyCatalogSourceProfileId profileId,
  ) {
    return switch (profileId) {
      LegacyCatalogSourceProfileId.alAsalahLegacyCatalog => alAsalah,
      LegacyCatalogSourceProfileId.eqlidLegacyCatalog => eqlid,
    };
  }

  Map<String, dynamic> toJson() => {
    'id': id.value,
    'expected_brand_id': expectedBrandId,
    'expected_brand_name': expectedBrandName,
    'worksheet': worksheetName,
    'columns': {
      'unit_3': unit3Column,
      'unit_2': unit2Column,
      'primary_unit': primaryUnitColumn,
      'material': materialColumn,
      'group': groupColumn,
    },
  };
}

/// Describes where the caller obtained the brand-document evidence.
///
/// This importer never contacts Firebase. A contract-only selection is enough
/// for a local preview, but is deliberately not sufficient for a production
/// import. A future production executor must first supply a document snapshot
/// validated by its authenticated backend.
enum LegacyBrandDocumentEvidence {
  contractOnly,
  localFixture,
  firestoreEmulator,
  productionDocument,
}

class LegacyCatalogBrandSelection {
  final String documentId;
  final String name;
  final bool? documentExists;
  final LegacyBrandDocumentEvidence evidence;

  const LegacyCatalogBrandSelection.contractOnly({
    required this.documentId,
    required this.name,
  }) : documentExists = null,
       evidence = LegacyBrandDocumentEvidence.contractOnly;

  const LegacyCatalogBrandSelection.validated({
    required this.documentId,
    required this.name,
    required bool exists,
    required this.evidence,
  }) : documentExists = exists;

  bool get isDocumentValidated =>
      evidence != LegacyBrandDocumentEvidence.contractOnly &&
      documentExists == true;

  bool get productionValidationPending =>
      evidence != LegacyBrandDocumentEvidence.productionDocument ||
      documentExists != true;
}

enum LegacyCatalogIssueSeverity { warning, error }

class LegacyCatalogIssue {
  final String code;
  final LegacyCatalogIssueSeverity severity;
  final String message;

  const LegacyCatalogIssue({
    required this.code,
    required this.severity,
    required this.message,
  });

  Map<String, dynamic> toJson() => {
    'code': code,
    'severity': severity.name,
    'message': message,
  };
}

enum LegacySuggestionConfidence { high, medium, low }

class LegacyGroupSuggestion {
  final String leadingCodeSegment;
  final String groupLegacyCode;
  final String groupName;
  final LegacySuggestionConfidence confidence;
  final String reason;

  const LegacyGroupSuggestion({
    required this.leadingCodeSegment,
    required this.groupLegacyCode,
    required this.groupName,
    required this.confidence,
    required this.reason,
  });

  Map<String, dynamic> toJson() => {
    'leading_code_segment': leadingCodeSegment,
    'suggested_group_legacy_code': groupLegacyCode,
    'suggested_group_name': groupName,
    'confidence': confidence.name,
    'reason': reason,
    'approved': false,
  };
}

class LegacyPrefixGroupMappingCandidate {
  final String leadingCodeSegment;
  final String groupLegacyCode;
  final String groupName;
  final LegacySuggestionConfidence confidence;
  final String reason;
  final List<int> sourceRows;

  const LegacyPrefixGroupMappingCandidate({
    required this.leadingCodeSegment,
    required this.groupLegacyCode,
    required this.groupName,
    required this.confidence,
    required this.reason,
    required this.sourceRows,
  });

  Map<String, dynamic> toJson() => {
    'leading_code_segment': leadingCodeSegment,
    'suggested_group_legacy_code': groupLegacyCode,
    'suggested_group_name': groupName,
    'confidence': confidence.name,
    'reason': reason,
    'source_rows': sourceRows,
    'record_count': sourceRows.length,
    'approved': false,
  };
}

class LegacyUnitNormalizationSuggestion {
  final String slot;
  final String rawValue;
  final String suggestedValue;
  final LegacySuggestionConfidence confidence;
  final String reason;

  const LegacyUnitNormalizationSuggestion({
    required this.slot,
    required this.rawValue,
    required this.suggestedValue,
    required this.confidence,
    required this.reason,
  });

  Map<String, dynamic> toJson() => {
    'slot': slot,
    'raw_value': rawValue,
    'suggested_value': suggestedValue,
    'confidence': confidence.name,
    'reason': reason,
    'approved': false,
  };
}

class LegacyCatalogRecord {
  final LegacyCatalogSourceProfileId sourceProfile;
  final String sourceHash;
  final String sheetName;
  final int rowNumber;
  final String brandId;
  final String rawMaterialValue;
  final String rawGroupValue;
  final String rawPrimaryUnit;
  final String rawUnit2;
  final String rawUnit3;
  final String? legacyCode;
  final String? productName;
  final String? groupLegacyCode;
  final String? groupName;
  final String fingerprint;
  final List<LegacyCatalogIssue> issues;
  final LegacyGroupSuggestion? groupSuggestion;
  final List<LegacyUnitNormalizationSuggestion> unitSuggestions;

  const LegacyCatalogRecord({
    required this.sourceProfile,
    required this.sourceHash,
    required this.sheetName,
    required this.rowNumber,
    required this.brandId,
    required this.rawMaterialValue,
    required this.rawGroupValue,
    required this.rawPrimaryUnit,
    required this.rawUnit2,
    required this.rawUnit3,
    required this.legacyCode,
    required this.productName,
    required this.groupLegacyCode,
    required this.groupName,
    required this.fingerprint,
    required this.issues,
    required this.groupSuggestion,
    required this.unitSuggestions,
  });

  bool get hasBlockingIssue =>
      issues.any((issue) => issue.severity == LegacyCatalogIssueSeverity.error);

  bool get hasMissingGroup => rawGroupValue.trim().isEmpty;

  bool get originalGroupMissing => hasMissingGroup;

  bool get canUseFallbackSystemGroup => hasMissingGroup && !hasBlockingIssue;

  LegacyCatalogRecord copyWith({LegacyGroupSuggestion? groupSuggestion}) {
    return LegacyCatalogRecord(
      sourceProfile: sourceProfile,
      sourceHash: sourceHash,
      sheetName: sheetName,
      rowNumber: rowNumber,
      brandId: brandId,
      rawMaterialValue: rawMaterialValue,
      rawGroupValue: rawGroupValue,
      rawPrimaryUnit: rawPrimaryUnit,
      rawUnit2: rawUnit2,
      rawUnit3: rawUnit3,
      legacyCode: legacyCode,
      productName: productName,
      groupLegacyCode: groupLegacyCode,
      groupName: groupName,
      fingerprint: fingerprint,
      issues: issues,
      groupSuggestion: groupSuggestion ?? this.groupSuggestion,
      unitSuggestions: unitSuggestions,
    );
  }

  Map<String, dynamic> toJson({bool fallbackAssignmentConfirmed = false}) {
    final fallbackAssigned =
        canUseFallbackSystemGroup && fallbackAssignmentConfirmed;
    return {
      'source_profile': sourceProfile.value,
      'source_hash': sourceHash,
      'source_sheet': sheetName,
      'source_row': rowNumber,
      'brand_id': brandId,
      'raw_material_value': rawMaterialValue,
      'raw_group_value': rawGroupValue,
      'raw_units': {
        'primary': rawPrimaryUnit,
        'unit_2': rawUnit2,
        'unit_3': rawUnit3,
      },
      'legacy_code': legacyCode,
      'product_name': productName,
      'group_legacy_code': groupLegacyCode,
      'group_name': groupName,
      'group_resolution': {
        'original_group_missing': originalGroupMissing,
        'fallback_system_group_assigned': fallbackAssigned,
        if (fallbackAssigned)
          'fallback_system_group_key': legacyCatalogUncategorizedGroupKey,
        if (fallbackAssigned)
          'fallback_system_group_id': legacyCatalogUncategorizedGroupId(
            brandId,
          ),
      },
      'fingerprint': fingerprint,
      'issues': issues.map((issue) => issue.toJson()).toList(),
      'group_suggestion': groupSuggestion?.toJson(),
      'unit_normalization_suggestions': unitSuggestions
          .map((suggestion) => suggestion.toJson())
          .toList(),
    };
  }

  /// Flattened metadata aligned with the catalog product source contract.
  ///
  /// This helper does not write anything; the importer remains dry-run only.
  Map<String, dynamic> _toProductSourceMetadata({
    String? importId,
    required bool fallbackAssignmentConfirmed,
  }) {
    final fallbackAssigned =
        canUseFallbackSystemGroup && fallbackAssignmentConfirmed;
    return {
      'source_profile': sourceProfile.value,
      'source_file_sha256': sourceHash,
      'source_sheet': sheetName,
      'source_row': rowNumber,
      'raw_material_value': rawMaterialValue,
      'raw_group_value': rawGroupValue,
      'raw_primary_unit': rawPrimaryUnit,
      'raw_unit_2': rawUnit2,
      'raw_unit_3': rawUnit3,
      'source_fingerprint': fingerprint,
      'original_group_missing': originalGroupMissing,
      'fallback_system_group_assigned': fallbackAssigned,
      if (fallbackAssigned)
        'fallback_system_group_key': legacyCatalogUncategorizedGroupKey,
      if (fallbackAssigned)
        'fallback_system_group_id': legacyCatalogUncategorizedGroupId(brandId),
      if (importId != null && importId.trim().isNotEmpty)
        'import_id': importId.trim(),
    };
  }
}

class LegacyCatalogSkippedRow {
  final int rowNumber;
  final String reason;

  const LegacyCatalogSkippedRow({
    required this.rowNumber,
    required this.reason,
  });

  Map<String, dynamic> toJson() => {'source_row': rowNumber, 'reason': reason};
}

class ExistingLegacyCatalogProduct {
  final String productId;
  final String brandId;
  final String? legacyCode;
  final String normalizedName;
  final String sourceFingerprint;
  final bool hasManualCorrections;

  const ExistingLegacyCatalogProduct({
    required this.productId,
    required this.brandId,
    required this.legacyCode,
    required this.normalizedName,
    required this.sourceFingerprint,
    this.hasManualCorrections = false,
  });
}

class LegacyCatalogPlanEntry {
  final LegacyCatalogRecord record;
  final String action;
  final String? existingProductId;

  const LegacyCatalogPlanEntry({
    required this.record,
    required this.action,
    this.existingProductId,
  });

  bool get assignsUncategorizedGroup => record.originalGroupMissing;

  bool get assignsNormalSourceGroup => !assignsUncategorizedGroup;

  String? get assignedSystemGroupId => assignsUncategorizedGroup
      ? legacyCatalogUncategorizedGroupId(record.brandId)
      : null;

  String get assignedGroupId {
    if (assignsUncategorizedGroup) {
      return legacyCatalogUncategorizedGroupId(record.brandId);
    }
    final groupName = record.groupName?.trim() ?? '';
    if (groupName.isEmpty) {
      throw StateError(
        'A ready legacy product with a populated source group must have a '
        'parsed group name.',
      );
    }
    return productGroupDocumentId(
      brandId: record.brandId,
      groupName: groupName,
    );
  }

  Map<String, dynamic> toProductSourceMetadata({String? importId}) =>
      record._toProductSourceMetadata(
        importId: importId,
        fallbackAssignmentConfirmed: assignsUncategorizedGroup,
      );

  Map<String, dynamic> toJson() => {
    'action': action,
    'existing_product_id': existingProductId,
    'assigned_group_id': assignedGroupId,
    'assigned_group_kind': assignsUncategorizedGroup
        ? 'system_uncategorized'
        : 'normal_source_group',
    'record': record.toJson(
      fallbackAssignmentConfirmed: assignsUncategorizedGroup,
    ),
  };
}

class LegacyCatalogNormalGroupPlan {
  final String brandId;
  final String groupId;
  final String name;
  final String normalizedName;
  final List<String> sourceLegacyCodes;
  final List<String> rawGroupValues;
  final List<int> sourceRows;

  const LegacyCatalogNormalGroupPlan({
    required this.brandId,
    required this.groupId,
    required this.name,
    required this.normalizedName,
    required this.sourceLegacyCodes,
    required this.rawGroupValues,
    required this.sourceRows,
  });

  Map<String, dynamic> toJson() => {
    'brand_id': brandId,
    'group_id': groupId,
    'name': name,
    'normalized_name': normalizedName,
    'source_legacy_codes': sourceLegacyCodes,
    'raw_group_values': rawGroupValues,
    'source_rows': sourceRows,
    'record_count': sourceRows.length,
    'action': 'ensure_or_validate',
    'system_managed': false,
    'production_validation_required': true,
  };
}

class LegacyCatalogSystemGroupPlan {
  final String brandId;
  final String groupId;
  final String key;
  final String name;
  const LegacyCatalogSystemGroupPlan({
    required this.brandId,
    required this.groupId,
    required this.key,
    required this.name,
  });

  Map<String, dynamic> toJson() => {
    'brand_id': brandId,
    'group_id': groupId,
    'key': key,
    'name': name,
    'action': 'ensure',
    'system_managed': true,
    'production_validation_required': true,
  };
}

class LegacyCatalogInvalidEntry {
  final LegacyCatalogRecord record;
  final List<LegacyCatalogIssue> issues;

  const LegacyCatalogInvalidEntry({required this.record, required this.issues});

  Map<String, dynamic> toJson() => {
    'record': record.toJson(),
    'blocking_issues': issues.map((issue) => issue.toJson()).toList(),
  };
}

class LegacyCatalogDuplicate {
  final String keyType;
  final String normalizedValue;
  final List<int> sourceRows;
  final List<String> existingProductIds;

  const LegacyCatalogDuplicate({
    required this.keyType,
    required this.normalizedValue,
    required this.sourceRows,
    this.existingProductIds = const [],
  });

  Map<String, dynamic> toJson() => {
    'key_type': keyType,
    'normalized_value': normalizedValue,
    'source_rows': sourceRows,
    'existing_product_ids': existingProductIds,
  };
}

class LegacyCatalogDryRunReport {
  final LegacyCatalogSourceProfile profile;
  final LegacyCatalogBrandSelection brandSelection;
  final String sourcePath;
  final String sourceHash;
  final String worksheetName;
  final int sourceRowCount;
  final List<int> validatedHeaderRows;
  final List<LegacyCatalogRecord> records;
  final List<LegacyCatalogPlanEntry> creates;
  final List<LegacyCatalogPlanEntry> updates;
  final List<LegacyCatalogPlanEntry> unchanged;
  final List<LegacyCatalogNormalGroupPlan> normalGroupPlans;
  final List<LegacyCatalogSystemGroupPlan> systemGroupPlans;
  final List<LegacyCatalogDuplicate> duplicates;
  final List<LegacyCatalogInvalidEntry> invalidRecords;
  final List<LegacyCatalogSkippedRow> skippedRows;

  const LegacyCatalogDryRunReport({
    required this.profile,
    required this.brandSelection,
    required this.sourcePath,
    required this.sourceHash,
    required this.worksheetName,
    required this.sourceRowCount,
    required this.validatedHeaderRows,
    required this.records,
    required this.creates,
    required this.updates,
    required this.unchanged,
    required this.normalGroupPlans,
    required this.systemGroupPlans,
    required this.duplicates,
    required this.invalidRecords,
    required this.skippedRows,
  });

  int get missingGroupCount =>
      records.where((record) => record.hasMissingGroup).length;

  int get missingPrimaryUnitCount =>
      records.where((record) => record.rawPrimaryUnit.trim().isEmpty).length;

  int get unit2Count =>
      records.where((record) => record.rawUnit2.trim().isNotEmpty).length;

  int get unit3Count =>
      records.where((record) => record.rawUnit3.trim().isNotEmpty).length;

  int get distinctPopulatedGroupCount => records
      .map((record) => record.rawGroupValue.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .length;

  int get groupSuggestionCount =>
      records.where((record) => record.groupSuggestion != null).length;

  int get missingGroupWithoutSuggestionCount => records
      .where(
        (record) => record.hasMissingGroup && record.groupSuggestion == null,
      )
      .length;

  int get unitSuggestionCount =>
      records.fold(0, (count, record) => count + record.unitSuggestions.length);

  List<LegacyCatalogPlanEntry> get readyEntries =>
      List.unmodifiable([...creates, ...updates, ...unchanged]);

  List<LegacyCatalogPlanEntry> get realGroupReady => List.unmodifiable(
    readyEntries.where((entry) => !entry.record.originalGroupMissing),
  );

  List<LegacyCatalogPlanEntry> get uncategorizedReady => List.unmodifiable(
    readyEntries.where((entry) => entry.record.originalGroupMissing),
  );

  List<LegacyCatalogRecord> get blockedOtherRecords {
    final readyRows = readyEntries
        .map((entry) => entry.record.rowNumber)
        .toSet();
    return List.unmodifiable(
      records.where((record) => !readyRows.contains(record.rowNumber)),
    );
  }

  int get invalidOrAmbiguousCount => records.where((record) {
    return record.issues.any(
      (issue) =>
          issue.code.startsWith('invalid_') ||
          issue.code.startsWith('ambiguous_'),
    );
  }).length;

  int get duplicateRecordCount =>
      duplicates.expand((duplicate) => duplicate.sourceRows).toSet().length;

  int get systemGroupsToEnsureCount => systemGroupPlans.length;

  int get normalGroupsToEnsureOrValidateCount => normalGroupPlans.length;

  bool isReadyRecord(LegacyCatalogRecord record) =>
      readyEntries.any((entry) => entry.record.rowNumber == record.rowNumber);

  Map<String, int> get groupSuggestionsByConfidence => _countValues(
    records
        .map((record) => record.groupSuggestion?.confidence.name)
        .whereType<String>(),
  );

  Map<String, int> get unitSuggestionsByConfidence => _countValues(
    records
        .expand((record) => record.unitSuggestions)
        .map((suggestion) => suggestion.confidence.name),
  );

  Map<String, int> get blockingIssueCounts => _countValues(
    invalidRecords.expand((entry) => entry.issues).map((issue) => issue.code),
  );

  List<LegacyPrefixGroupMappingCandidate> get prefixMappingCandidates {
    final grouped = <String, List<LegacyCatalogRecord>>{};
    for (final record in records.where((record) => record.hasMissingGroup)) {
      final suggestion = record.groupSuggestion;
      if (suggestion == null) continue;
      final key = [
        suggestion.leadingCodeSegment,
        suggestion.groupLegacyCode,
        suggestion.confidence.name,
      ].join('\u001f');
      grouped.putIfAbsent(key, () => []).add(record);
    }
    final candidates = grouped.values.map((matchingRecords) {
      final suggestion = matchingRecords.first.groupSuggestion!;
      return LegacyPrefixGroupMappingCandidate(
        leadingCodeSegment: suggestion.leadingCodeSegment,
        groupLegacyCode: suggestion.groupLegacyCode,
        groupName: suggestion.groupName,
        confidence: suggestion.confidence,
        reason: suggestion.reason,
        sourceRows: matchingRecords
            .map((record) => record.rowNumber)
            .toList(growable: false),
      );
    }).toList();
    candidates.sort(
      (left, right) =>
          left.leadingCodeSegment.compareTo(right.leadingCodeSegment),
    );
    return List.unmodifiable(candidates);
  }

  Map<String, dynamic> toSummaryJson() => {
    'dry_run': true,
    'writes_performed': false,
    'prices_parsed': false,
    'profile': profile.toJson(),
    'brand_contract': {
      'selected_brand_id': brandSelection.documentId,
      'selected_brand_name': brandSelection.name,
      'evidence': brandSelection.evidence.name,
      'document_validated': brandSelection.isDocumentValidated,
      'production_document_validation_pending':
          brandSelection.productionValidationPending,
    },
    'source': {
      'path': sourcePath,
      'sha256': sourceHash,
      'worksheet': worksheetName,
      'source_rows': sourceRowCount,
      'validated_header_rows': validatedHeaderRows,
    },
    'counts': {
      'product_records': records.length,
      'records_to_create': creates.length,
      'records_to_update': updates.length,
      'unchanged_records': unchanged.length,
      'real_group_ready': realGroupReady.length,
      'uncategorized_ready': uncategorizedReady.length,
      'blocked_other': blockedOtherRecords.length,
      'normal_groups_to_ensure_or_validate':
          normalGroupsToEnsureOrValidateCount,
      'system_groups_to_ensure': systemGroupsToEnsureCount,
      'duplicate_groups': duplicates.length,
      'duplicate_records': duplicateRecordCount,
      'invalid_records': invalidRecords.length,
      'invalid_or_ambiguous_records': invalidOrAmbiguousCount,
      'skipped_report_rows': skippedRows.length,
      'distinct_populated_groups': distinctPopulatedGroupCount,
      'missing_group': missingGroupCount,
      'missing_primary_unit': missingPrimaryUnitCount,
      'unit_2_populated': unit2Count,
      'unit_3_populated': unit3Count,
      'group_suggestions': groupSuggestionCount,
      'bulk_prefix_mapping_candidates': prefixMappingCandidates.length,
      'missing_group_without_suggestion': missingGroupWithoutSuggestionCount,
      'unit_normalization_suggestions': unitSuggestionCount,
    },
    'finding_breakdown': {
      'blocking_issues': blockingIssueCounts,
      'group_suggestions_by_confidence': groupSuggestionsByConfidence,
      'unit_suggestions_by_confidence': unitSuggestionsByConfidence,
    },
    'blocking_rows': blockedOtherRecords
        .map((record) => record.rowNumber)
        .toList(),
  };

  Map<String, dynamic> toDetailedJson() => {
    ...toSummaryJson(),
    'creates': creates.map((entry) => entry.toJson()).toList(),
    'updates': updates.map((entry) => entry.toJson()).toList(),
    'unchanged': unchanged.map((entry) => entry.toJson()).toList(),
    'real_group_ready': realGroupReady.map((entry) => entry.toJson()).toList(),
    'uncategorized_ready': uncategorizedReady
        .map((entry) => entry.toJson())
        .toList(),
    'blocked_other': blockedOtherRecords
        .map((record) => record.toJson())
        .toList(),
    'normal_group_plans': normalGroupPlans
        .map((plan) => plan.toJson())
        .toList(),
    'system_group_plans': systemGroupPlans
        .map((plan) => plan.toJson())
        .toList(),
    'bulk_prefix_mapping_candidates': prefixMappingCandidates
        .map((candidate) => candidate.toJson())
        .toList(),
    'duplicates': duplicates.map((duplicate) => duplicate.toJson()).toList(),
    'invalid_records': invalidRecords.map((entry) => entry.toJson()).toList(),
    'skipped_rows': skippedRows.map((row) => row.toJson()).toList(),
    'missing_group_records': records
        .where((record) => record.hasMissingGroup)
        .map(
          (record) =>
              record.toJson(fallbackAssignmentConfirmed: isReadyRecord(record)),
        )
        .toList(),
  };
}

Map<String, int> _countValues(Iterable<String> values) {
  final counts = <String, int>{};
  for (final value in values) {
    counts.update(value, (count) => count + 1, ifAbsent: () => 1);
  }
  return counts;
}

class LegacyCatalogImportException implements Exception {
  final String message;

  const LegacyCatalogImportException(this.message);

  @override
  String toString() => 'LegacyCatalogImportException: $message';
}

class LegacyCatalogImporter {
  const LegacyCatalogImporter();

  Future<LegacyCatalogDryRunReport> createDryRun({
    required File sourceFile,
    required LegacyCatalogSourceProfileId profileId,
    required LegacyCatalogBrandSelection brandSelection,
    List<ExistingLegacyCatalogProduct> existingProducts = const [],
  }) async {
    final profile = LegacyCatalogSourceProfile.forId(profileId);
    _validateBrandSelection(profile, brandSelection);

    if (!await sourceFile.exists()) {
      throw LegacyCatalogImportException(
        'Legacy catalog source does not exist: ${sourceFile.path}',
      );
    }

    final bytes = await sourceFile.readAsBytes();
    final sourceHash = sha256Hex(bytes);
    late final String xml;
    try {
      xml = utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      throw const LegacyCatalogImportException(
        'The source is not valid UTF-8 SpreadsheetML XML.',
      );
    }

    final workbook = _SpreadsheetMlWorkbook.parse(xml);
    if (workbook.worksheets.length != 1) {
      throw LegacyCatalogImportException(
        'Profile ${profile.id.value} requires exactly one worksheet; '
        'found ${workbook.worksheets.length}.',
      );
    }
    final worksheet = workbook.worksheets.single;
    if (worksheet.name != profile.worksheetName) {
      throw LegacyCatalogImportException(
        'Profile ${profile.id.value} requires worksheet '
        '${profile.worksheetName}; found ${worksheet.name}.',
      );
    }

    final headerRows = _validateSourceSchema(profile, worksheet);
    final parsed = _parseRows(
      worksheet: worksheet,
      profile: profile,
      brandId: brandSelection.documentId,
      sourceHash: sourceHash,
    );

    final recordsWithSuggestions = _attachMissingGroupSuggestions(
      parsed.records,
    );
    final plan = _buildPlan(
      records: recordsWithSuggestions,
      brandId: brandSelection.documentId,
      existingProducts: existingProducts,
    );
    final readyEntries = <LegacyCatalogPlanEntry>[
      ...plan.creates,
      ...plan.updates,
      ...plan.unchanged,
    ];
    final needsUncategorizedGroup = readyEntries.any(
      (entry) => entry.record.originalGroupMissing,
    );
    final fallbackGroupId = legacyCatalogUncategorizedGroupId(
      brandSelection.documentId,
    );
    final systemGroupPlans = needsUncategorizedGroup
        ? <LegacyCatalogSystemGroupPlan>[
            LegacyCatalogSystemGroupPlan(
              brandId: brandSelection.documentId,
              groupId: fallbackGroupId,
              key: legacyCatalogUncategorizedGroupKey,
              name: legacyCatalogUncategorizedGroupName,
            ),
          ]
        : const <LegacyCatalogSystemGroupPlan>[];
    final normalGroupPlans = _buildNormalGroupPlans(readyEntries);

    return LegacyCatalogDryRunReport(
      profile: profile,
      brandSelection: brandSelection,
      sourcePath: sourceFile.absolute.path,
      sourceHash: sourceHash,
      worksheetName: worksheet.name,
      sourceRowCount: worksheet.rows.length,
      validatedHeaderRows: headerRows,
      records: recordsWithSuggestions,
      creates: plan.creates,
      updates: plan.updates,
      unchanged: plan.unchanged,
      normalGroupPlans: normalGroupPlans,
      systemGroupPlans: systemGroupPlans,
      duplicates: plan.duplicates,
      invalidRecords: plan.invalidRecords,
      skippedRows: parsed.skippedRows,
    );
  }

  List<LegacyCatalogNormalGroupPlan> _buildNormalGroupPlans(
    List<LegacyCatalogPlanEntry> readyEntries,
  ) {
    final entriesByGroupId = <String, List<LegacyCatalogPlanEntry>>{};
    for (final entry in readyEntries.where(
      (candidate) => candidate.assignsNormalSourceGroup,
    )) {
      entriesByGroupId.putIfAbsent(entry.assignedGroupId, () => []).add(entry);
    }

    final plans = entriesByGroupId.entries.map((groupEntries) {
      final entries = groupEntries.value;
      final firstRecord = entries.first.record;
      final groupName = firstRecord.groupName!.trim();
      final sourceLegacyCodes =
          entries
              .map((entry) => entry.record.groupLegacyCode?.trim() ?? '')
              .where((value) => value.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      final rawGroupValues =
          entries.map((entry) => entry.record.rawGroupValue).toSet().toList()
            ..sort();
      final sourceRows = entries.map((entry) => entry.record.rowNumber).toList()
        ..sort();
      return LegacyCatalogNormalGroupPlan(
        brandId: firstRecord.brandId,
        groupId: groupEntries.key,
        name: groupName,
        normalizedName: normalizeCatalogText(groupName),
        sourceLegacyCodes: List.unmodifiable(sourceLegacyCodes),
        rawGroupValues: List.unmodifiable(rawGroupValues),
        sourceRows: List.unmodifiable(sourceRows),
      );
    }).toList();
    plans.sort((left, right) => left.groupId.compareTo(right.groupId));
    return List.unmodifiable(plans);
  }

  void _validateBrandSelection(
    LegacyCatalogSourceProfile profile,
    LegacyCatalogBrandSelection selection,
  ) {
    if (selection.documentId != profile.expectedBrandId) {
      throw LegacyCatalogImportException(
        'Profile ${profile.id.value} may only target brand document '
        '${profile.expectedBrandId}.',
      );
    }
    if (selection.name.trim() != profile.expectedBrandName) {
      throw LegacyCatalogImportException(
        'Brand name does not match the ${profile.id.value} contract.',
      );
    }
    if (selection.evidence != LegacyBrandDocumentEvidence.contractOnly &&
        selection.documentExists != true) {
      throw const LegacyCatalogImportException(
        'The selected brand document was not found in the supplied validation '
        'source. The importer never creates brands.',
      );
    }
  }

  List<int> _validateSourceSchema(
    LegacyCatalogSourceProfile profile,
    _SpreadsheetMlWorksheet worksheet,
  ) {
    final headerRows = <int>[];
    for (var index = 0; index < worksheet.rows.length; index++) {
      final row = worksheet.rows[index];
      if (_trimmedCell(row, profile.materialColumn) != 'المادة' ||
          _trimmedCell(row, profile.groupColumn) != 'المجموعة') {
        continue;
      }
      if (index + 1 >= worksheet.rows.length) continue;
      final unitRow = worksheet.rows[index + 1];
      if (_trimmedCell(unitRow, profile.unit3Column) == 'الوحدة 3' &&
          _trimmedCell(unitRow, profile.unit2Column) == 'الوحدة 2' &&
          _trimmedCell(unitRow, profile.primaryUnitColumn) == 'الوحدة') {
        headerRows.add(row.rowNumber);
      }
    }

    if (headerRows.isEmpty) {
      throw LegacyCatalogImportException(
        'The worksheet headers do not match profile ${profile.id.value}. '
        'Expected material column ${profile.materialColumn}, group column '
        '${profile.groupColumn}, and unit columns '
        '${profile.unit3Column}/${profile.unit2Column}/'
        '${profile.primaryUnitColumn}.',
      );
    }

    final materialCells = worksheet.rows
        .map((row) => _trimmedCell(row, profile.materialColumn))
        .where((value) => value.isNotEmpty && value != 'المادة')
        .toList();
    if (materialCells.isEmpty) {
      throw LegacyCatalogImportException(
        'Profile ${profile.id.value} matched headers but contained no material '
        'records in column ${profile.materialColumn}.',
      );
    }

    final plausibleRecords = materialCells.where(_isPlausibleMaterial).length;
    if (plausibleRecords / materialCells.length < 0.90) {
      throw LegacyCatalogImportException(
        'Material content does not match profile ${profile.id.value}; fewer '
        'than 90% of populated material cells contain a legacy code and name.',
      );
    }
    return headerRows;
  }

  _ParsedRows _parseRows({
    required _SpreadsheetMlWorksheet worksheet,
    required LegacyCatalogSourceProfile profile,
    required String brandId,
    required String sourceHash,
  }) {
    final records = <LegacyCatalogRecord>[];
    final skippedRows = <LegacyCatalogSkippedRow>[];

    for (final row in worksheet.rows) {
      final rawMaterial = row.cells[profile.materialColumn] ?? '';
      final material = rawMaterial.trim();
      if (material.isEmpty || material == 'المادة') {
        skippedRows.add(
          LegacyCatalogSkippedRow(
            rowNumber: row.rowNumber,
            reason: _classifySkippedRow(row),
          ),
        );
        continue;
      }

      final rawGroup = row.cells[profile.groupColumn] ?? '';
      final rawPrimaryUnit = row.cells[profile.primaryUnitColumn] ?? '';
      final rawUnit2 = row.cells[profile.unit2Column] ?? '';
      final rawUnit3 = row.cells[profile.unit3Column] ?? '';
      final materialParts = _parseCodeAndName(material);
      final groupParts = rawGroup.trim().isEmpty
          ? null
          : _parseCodeAndName(rawGroup.trim());
      final issues = <LegacyCatalogIssue>[];

      if (materialParts == null) {
        issues.add(
          const LegacyCatalogIssue(
            code: 'invalid_material_value',
            severity: LegacyCatalogIssueSeverity.error,
            message:
                'Material value does not contain a safely parsed legacy '
                'code and display name.',
          ),
        );
      } else if (!_containsLetter(materialParts.name)) {
        issues.add(
          const LegacyCatalogIssue(
            code: 'ambiguous_product_name',
            severity: LegacyCatalogIssueSeverity.error,
            message:
                'The parsed product name contains no Arabic or Latin '
                'letters and requires accountant review.',
          ),
        );
      }

      if (rawPrimaryUnit.trim().isEmpty) {
        issues.add(
          const LegacyCatalogIssue(
            code: 'missing_primary_unit',
            severity: LegacyCatalogIssueSeverity.error,
            message: 'Primary unit is missing and must not be guessed.',
          ),
        );
      }
      if (rawGroup.trim().isEmpty) {
        issues.add(
          const LegacyCatalogIssue(
            code: 'missing_group',
            severity: LegacyCatalogIssueSeverity.warning,
            message:
                'Source group is empty. Any prefix-based group is only a '
                'review suggestion.',
          ),
        );
      } else if (groupParts == null || !_containsLetter(groupParts.name)) {
        issues.add(
          const LegacyCatalogIssue(
            code: 'invalid_group_value',
            severity: LegacyCatalogIssueSeverity.error,
            message: 'Populated group value cannot be parsed safely.',
          ),
        );
      }
      if (rawUnit3.trim().isNotEmpty && rawUnit2.trim().isEmpty) {
        issues.add(
          const LegacyCatalogIssue(
            code: 'unit_3_without_unit_2',
            severity: LegacyCatalogIssueSeverity.warning,
            message:
                'Unit 3 is populated while Unit 2 is empty; the raw '
                'source is preserved for review.',
          ),
        );
      }

      final fingerprintPayload = <String>[
        profile.id.value,
        brandId,
        rawMaterial,
        rawGroup,
        rawPrimaryUnit,
        rawUnit2,
        rawUnit3,
      ].join('\u001f');
      records.add(
        LegacyCatalogRecord(
          sourceProfile: profile.id,
          sourceHash: sourceHash,
          sheetName: worksheet.name,
          rowNumber: row.rowNumber,
          brandId: brandId,
          rawMaterialValue: rawMaterial,
          rawGroupValue: rawGroup,
          rawPrimaryUnit: rawPrimaryUnit,
          rawUnit2: rawUnit2,
          rawUnit3: rawUnit3,
          legacyCode: materialParts?.code,
          productName: materialParts?.name,
          groupLegacyCode: groupParts?.code,
          groupName: groupParts?.name,
          fingerprint: sha256Hex(utf8.encode(fingerprintPayload)),
          issues: List.unmodifiable(issues),
          groupSuggestion: null,
          unitSuggestions: List.unmodifiable(
            _unitSuggestions(
              primary: rawPrimaryUnit,
              unit2: rawUnit2,
              unit3: rawUnit3,
            ),
          ),
        ),
      );
    }

    return _ParsedRows(records: records, skippedRows: skippedRows);
  }

  List<LegacyCatalogRecord> _attachMissingGroupSuggestions(
    List<LegacyCatalogRecord> records,
  ) {
    final knownGroups = <String, _CodeAndName>{};
    for (final record in records) {
      final code = record.groupLegacyCode;
      final name = record.groupName;
      if (code != null && name != null) {
        knownGroups.putIfAbsent(code, () => _CodeAndName(code, name));
      }
    }

    return List.unmodifiable(
      records.map((record) {
        if (!record.hasMissingGroup || record.legacyCode == null) return record;
        return record.copyWith(
          groupSuggestion: _suggestGroup(record.legacyCode!, knownGroups),
        );
      }),
    );
  }

  LegacyGroupSuggestion? _suggestGroup(
    String productCode,
    Map<String, _CodeAndName> knownGroups,
  ) {
    final leadingSegment = productCode.split('-').first;
    final normalizedLeading = _normalizeNumericCode(leadingSegment);
    final exactMatches = knownGroups.values.where(
      (group) => _normalizeNumericCode(group.code) == normalizedLeading,
    );
    if (productCode.contains('-') && exactMatches.length == 1) {
      final match = exactMatches.single;
      return LegacyGroupSuggestion(
        leadingCodeSegment: normalizedLeading,
        groupLegacyCode: match.code,
        groupName: match.name,
        confidence: LegacySuggestionConfidence.high,
        reason:
            'The normalized leading hyphen-delimited product-code segment '
            'exactly matches one populated legacy group code.',
      );
    }

    final normalizedProduct = _normalizeNumericCode(
      productCode.replaceAll('-', ''),
    );
    final prefixMatches = knownGroups.values.where((group) {
      final normalizedGroup = _normalizeNumericCode(group.code);
      return normalizedGroup.isNotEmpty &&
          normalizedProduct.startsWith(normalizedGroup);
    }).toList();
    if (prefixMatches.isEmpty) return null;
    prefixMatches.sort(
      (left, right) => _normalizeNumericCode(
        right.code,
      ).length.compareTo(_normalizeNumericCode(left.code).length),
    );
    final longestLength = _normalizeNumericCode(
      prefixMatches.first.code,
    ).length;
    final longest = prefixMatches
        .where(
          (group) => _normalizeNumericCode(group.code).length == longestLength,
        )
        .toList();
    if (longest.length != 1) return null;
    final match = longest.single;
    return LegacyGroupSuggestion(
      leadingCodeSegment: _normalizeNumericCode(match.code),
      groupLegacyCode: match.code,
      groupName: match.name,
      confidence: LegacySuggestionConfidence.medium,
      reason:
          'The longest known populated legacy group code is a numeric '
          'prefix of the compact product code. Accountant approval is required.',
    );
  }

  _ImportPlan _buildPlan({
    required List<LegacyCatalogRecord> records,
    required String brandId,
    required List<ExistingLegacyCatalogProduct> existingProducts,
  }) {
    final creates = <LegacyCatalogPlanEntry>[];
    final updates = <LegacyCatalogPlanEntry>[];
    final unchanged = <LegacyCatalogPlanEntry>[];
    final invalidRecords = <LegacyCatalogInvalidEntry>[];
    final duplicates = <LegacyCatalogDuplicate>[];
    final duplicateRows = <int>{};

    final sourceCodeGroups = <String, List<LegacyCatalogRecord>>{};
    final sourceNameGroups = <String, List<LegacyCatalogRecord>>{};
    for (final record in records) {
      final code = normalizeLegacyCode(record.legacyCode);
      if (code.isNotEmpty) {
        sourceCodeGroups.putIfAbsent(code, () => []).add(record);
      }
      final name = normalizeCatalogText(record.productName ?? '');
      if (name.isNotEmpty) {
        sourceNameGroups.putIfAbsent(name, () => []).add(record);
      }
    }
    for (final entry in sourceCodeGroups.entries.where(
      (entry) => entry.value.length > 1,
    )) {
      duplicates.add(
        LegacyCatalogDuplicate(
          keyType: 'legacy_code',
          normalizedValue: entry.key,
          sourceRows: entry.value.map((record) => record.rowNumber).toList(),
        ),
      );
      duplicateRows.addAll(entry.value.map((record) => record.rowNumber));
    }
    for (final entry in sourceNameGroups.entries.where(
      (entry) => entry.value.length > 1,
    )) {
      duplicates.add(
        LegacyCatalogDuplicate(
          keyType: 'normalized_name',
          normalizedValue: entry.key,
          sourceRows: entry.value.map((record) => record.rowNumber).toList(),
        ),
      );
      duplicateRows.addAll(entry.value.map((record) => record.rowNumber));
    }

    final inBrand = existingProducts
        .where((product) => product.brandId == brandId)
        .toList();
    final existingByCode = <String, List<ExistingLegacyCatalogProduct>>{};
    final existingByName = <String, List<ExistingLegacyCatalogProduct>>{};
    for (final product in inBrand) {
      final code = normalizeLegacyCode(product.legacyCode);
      if (code.isNotEmpty) {
        existingByCode.putIfAbsent(code, () => []).add(product);
      }
      if (product.normalizedName.trim().isNotEmpty) {
        existingByName
            .putIfAbsent(product.normalizedName.trim(), () => [])
            .add(product);
      }
    }

    for (final record in records) {
      final blocking = record.issues
          .where((issue) => issue.severity == LegacyCatalogIssueSeverity.error)
          .toList();
      if (blocking.isNotEmpty) {
        invalidRecords.add(
          LegacyCatalogInvalidEntry(record: record, issues: blocking),
        );
        continue;
      }
      if (duplicateRows.contains(record.rowNumber)) continue;

      final code = normalizeLegacyCode(record.legacyCode);
      final codeMatches = existingByCode[code] ?? const [];
      final normalizedName = normalizeCatalogText(record.productName ?? '');
      final nameMatches = existingByName[normalizedName] ?? const [];
      if (codeMatches.length > 1) {
        duplicates.add(
          LegacyCatalogDuplicate(
            keyType: 'existing_legacy_code',
            normalizedValue: code,
            sourceRows: [record.rowNumber],
            existingProductIds: codeMatches
                .map((product) => product.productId)
                .toList(),
          ),
        );
        continue;
      }
      if (codeMatches.length == 1) {
        final existing = codeMatches.single;
        final conflictingNameMatches = nameMatches
            .where((product) => product.productId != existing.productId)
            .toList();
        if (conflictingNameMatches.isNotEmpty) {
          invalidRecords.add(
            LegacyCatalogInvalidEntry(
              record: record,
              issues: const [
                LegacyCatalogIssue(
                  code: 'normalized_name_conflict',
                  severity: LegacyCatalogIssueSeverity.error,
                  message:
                      'Another existing product has the same normalized '
                      'display name. Manual review is required.',
                ),
              ],
            ),
          );
          continue;
        }
        if (existing.sourceFingerprint == record.fingerprint) {
          unchanged.add(
            LegacyCatalogPlanEntry(
              record: record,
              action: 'unchanged',
              existingProductId: existing.productId,
            ),
          );
        } else if (existing.hasManualCorrections) {
          invalidRecords.add(
            LegacyCatalogInvalidEntry(
              record: record,
              issues: const [
                LegacyCatalogIssue(
                  code: 'manual_correction_conflict',
                  severity: LegacyCatalogIssueSeverity.error,
                  message:
                      'Existing product contains manual corrections and '
                      'must not be overwritten by the import plan.',
                ),
              ],
            ),
          );
        } else {
          updates.add(
            LegacyCatalogPlanEntry(
              record: record,
              action: 'update',
              existingProductId: existing.productId,
            ),
          );
        }
        continue;
      }

      if (nameMatches.isNotEmpty) {
        invalidRecords.add(
          LegacyCatalogInvalidEntry(
            record: record,
            issues: const [
              LegacyCatalogIssue(
                code: 'normalized_name_conflict',
                severity: LegacyCatalogIssueSeverity.error,
                message:
                    'An existing product has the same normalized display '
                    'name but a different identity. Manual review is required.',
              ),
            ],
          ),
        );
        continue;
      }
      creates.add(LegacyCatalogPlanEntry(record: record, action: 'create'));
    }

    return _ImportPlan(
      creates: creates,
      updates: updates,
      unchanged: unchanged,
      duplicates: duplicates,
      invalidRecords: invalidRecords,
    );
  }
}

class _ParsedRows {
  final List<LegacyCatalogRecord> records;
  final List<LegacyCatalogSkippedRow> skippedRows;

  const _ParsedRows({required this.records, required this.skippedRows});
}

class _ImportPlan {
  final List<LegacyCatalogPlanEntry> creates;
  final List<LegacyCatalogPlanEntry> updates;
  final List<LegacyCatalogPlanEntry> unchanged;
  final List<LegacyCatalogDuplicate> duplicates;
  final List<LegacyCatalogInvalidEntry> invalidRecords;

  const _ImportPlan({
    required this.creates,
    required this.updates,
    required this.unchanged,
    required this.duplicates,
    required this.invalidRecords,
  });
}

class _CodeAndName {
  final String code;
  final String name;

  const _CodeAndName(this.code, this.name);
}

_CodeAndName? _parseCodeAndName(String value) {
  final match = RegExp(r'^([0-9]+(?:-[0-9]+)*)-(.+)$').firstMatch(value.trim());
  if (match == null) return null;
  final code = match.group(1)!.trim();
  final name = match.group(2)!.trim();
  if (code.isEmpty || name.isEmpty) return null;
  return _CodeAndName(code, name);
}

bool _isPlausibleMaterial(String value) => _parseCodeAndName(value) != null;

bool _containsLetter(String value) =>
    RegExp(r'[A-Za-z\u0600-\u06FF]').hasMatch(value);

String _normalizeNumericCode(String value) {
  final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return '';
  final withoutLeadingZeros = digits.replaceFirst(RegExp(r'^0+'), '');
  return withoutLeadingZeros.isEmpty ? '0' : withoutLeadingZeros;
}

String _trimmedCell(_SpreadsheetMlRow row, int column) =>
    (row.cells[column] ?? '').trim();

String _classifySkippedRow(_SpreadsheetMlRow row) {
  final values = row.cells.values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList();
  if (values.isEmpty) return 'blank_row';
  final joined = values.join(' ');
  if (values.contains('المادة') ||
      values.contains('المجموعة') ||
      values.contains('الوحدة 2') ||
      values.contains('الوحدة 3')) {
    return 'repeated_page_header';
  }
  if (joined.contains('جرد المواد') ||
      joined.contains('تفصيل الوحدات') ||
      joined.contains('ريال سعودي')) {
    return 'report_title';
  }
  if (values.any(
    const {'الكمية', 'الخارج', 'داخل', 'المجموع', 'طبيعة التسعير'}.contains,
  )) {
    return 'report_summary';
  }
  if (values.every((value) => RegExp(r'^[\d,.\-]+$').hasMatch(value))) {
    return 'report_total';
  }
  return 'non_product_report_row';
}

List<LegacyUnitNormalizationSuggestion> _unitSuggestions({
  required String primary,
  required String unit2,
  required String unit3,
}) {
  final suggestions = <LegacyUnitNormalizationSuggestion>[];
  for (final entry in <String, String>{
    'primary': primary,
    'unit_2': unit2,
    'unit_3': unit3,
  }.entries) {
    final suggestion = _suggestUnit(entry.key, entry.value);
    if (suggestion != null) suggestions.add(suggestion);
  }
  return suggestions;
}

LegacyUnitNormalizationSuggestion? _suggestUnit(String slot, String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;

  String? suggested;
  var confidence = LegacySuggestionConfidence.high;
  var reason =
      'Common Arabic spelling normalization; source spelling remains '
      'unchanged until accountant approval.';

  if (value == 'حبه') {
    suggested = 'حبة';
  } else if (value == 'حيه' || value == 'جبه') {
    suggested = 'حبة';
    confidence = LegacySuggestionConfidence.medium;
    reason =
        'Likely typographical variant of حبة; accountant confirmation is '
        'required.';
  } else if (value.startsWith('علبه')) {
    suggested = value.replaceFirst('علبه', 'علبة');
    if (suggested.endsWith(' صغير')) {
      suggested = '${suggested.substring(0, suggested.length - 5)} صغيرة';
    } else if (suggested.endsWith(' صغيره')) {
      suggested = '${suggested.substring(0, suggested.length - 6)} صغيرة';
    } else if (suggested.endsWith(' كبير')) {
      suggested = '${suggested.substring(0, suggested.length - 5)} كبيرة';
    }
  } else if (value == 'علبة صغير') {
    suggested = 'علبة صغيرة';
  } else if (value == 'توله') {
    suggested = 'تولة';
  } else if (value == 'نوله') {
    suggested = 'تولة';
    confidence = LegacySuggestionConfidence.low;
    reason =
        'Possible typographical variant of تولة; this low-confidence '
        'suggestion must be reviewed individually.';
  } else if (value == 'نص توله') {
    suggested = 'نصف تولة';
  } else if (value == 'اوقيه' || value == 'اوقية') {
    suggested = 'أوقية';
  } else if (value == 'نص اوقيه') {
    suggested = 'نصف أوقية';
  }
  if (suggested == null || suggested == value) return null;
  return LegacyUnitNormalizationSuggestion(
    slot: slot,
    rawValue: raw,
    suggestedValue: suggested,
    confidence: confidence,
    reason: reason,
  );
}

class _SpreadsheetMlWorkbook {
  final List<_SpreadsheetMlWorksheet> worksheets;

  const _SpreadsheetMlWorkbook(this.worksheets);

  static _SpreadsheetMlWorkbook parse(String xml) {
    if (!RegExp(r'<(?:[A-Za-z_][\w.-]*:)?Workbook\b').hasMatch(xml)) {
      throw const LegacyCatalogImportException(
        'Source is not SpreadsheetML XML.',
      );
    }
    final worksheetPattern = RegExp(
      r'<(?:[A-Za-z_][\w.-]*:)?Worksheet\b([^>]*)>(.*?)</(?:[A-Za-z_][\w.-]*:)?Worksheet\s*>',
      dotAll: true,
      caseSensitive: false,
    );
    final worksheets = <_SpreadsheetMlWorksheet>[];
    for (final match in worksheetPattern.allMatches(xml)) {
      final attributes = match.group(1) ?? '';
      final name = _attributeValue(attributes, 'Name');
      if (name == null || name.isEmpty) {
        throw const LegacyCatalogImportException(
          'SpreadsheetML worksheet is missing its name.',
        );
      }
      final worksheetBody = match.group(2) ?? '';
      final tableMatch = RegExp(
        r'<(?:[A-Za-z_][\w.-]*:)?Table\b[^>]*>(.*?)</(?:[A-Za-z_][\w.-]*:)?Table\s*>',
        dotAll: true,
        caseSensitive: false,
      ).firstMatch(worksheetBody);
      if (tableMatch == null) {
        throw LegacyCatalogImportException(
          'Worksheet $name does not contain a SpreadsheetML table.',
        );
      }
      worksheets.add(
        _SpreadsheetMlWorksheet(
          name: name,
          rows: _parseSpreadsheetRows(tableMatch.group(1) ?? ''),
        ),
      );
    }
    if (worksheets.isEmpty) {
      throw const LegacyCatalogImportException(
        'SpreadsheetML source contains no worksheets.',
      );
    }
    return _SpreadsheetMlWorkbook(worksheets);
  }
}

class _SpreadsheetMlWorksheet {
  final String name;
  final List<_SpreadsheetMlRow> rows;

  const _SpreadsheetMlWorksheet({required this.name, required this.rows});
}

class _SpreadsheetMlRow {
  final int rowNumber;
  final Map<int, String> cells;

  const _SpreadsheetMlRow({required this.rowNumber, required this.cells});
}

List<_SpreadsheetMlRow> _parseSpreadsheetRows(String tableBody) {
  final rowPattern = RegExp(
    r'<(?:[A-Za-z_][\w.-]*:)?Row\b([^>]*?)(?:/\s*>|>(.*?)</(?:[A-Za-z_][\w.-]*:)?Row\s*>)',
    dotAll: true,
    caseSensitive: false,
  );
  final cellPattern = RegExp(
    r'<(?:[A-Za-z_][\w.-]*:)?Cell\b([^>]*?)(?:/\s*>|>(.*?)</(?:[A-Za-z_][\w.-]*:)?Cell\s*>)',
    dotAll: true,
    caseSensitive: false,
  );
  final dataPattern = RegExp(
    r'<(?:[A-Za-z_][\w.-]*:)?Data\b[^>]*>(.*?)</(?:[A-Za-z_][\w.-]*:)?Data\s*>',
    dotAll: true,
    caseSensitive: false,
  );

  final rows = <_SpreadsheetMlRow>[];
  var currentRow = 0;
  for (final rowMatch in rowPattern.allMatches(tableBody)) {
    final rowAttributes = rowMatch.group(1) ?? '';
    currentRow =
        int.tryParse(_attributeValue(rowAttributes, 'Index') ?? '') ??
        currentRow + 1;
    final rowBody = rowMatch.group(2) ?? '';
    final cells = <int, String>{};
    var currentColumn = 0;
    for (final cellMatch in cellPattern.allMatches(rowBody)) {
      final cellAttributes = cellMatch.group(1) ?? '';
      currentColumn =
          int.tryParse(_attributeValue(cellAttributes, 'Index') ?? '') ??
          currentColumn + 1;
      final dataMatch = dataPattern.firstMatch(cellMatch.group(2) ?? '');
      if (dataMatch != null) {
        final withoutTags = (dataMatch.group(1) ?? '').replaceAll(
          RegExp(r'<[^>]+>'),
          '',
        );
        cells[currentColumn] = _decodeXmlEntities(withoutTags);
      }
      final mergeAcross = int.tryParse(
        _attributeValue(cellAttributes, 'MergeAcross') ?? '',
      );
      if (mergeAcross != null) currentColumn += mergeAcross;
    }
    rows.add(_SpreadsheetMlRow(rowNumber: currentRow, cells: cells));
  }
  return rows;
}

String? _attributeValue(String attributes, String localName) {
  final match = RegExp(
    '(?:[A-Za-z_][\\w.-]*:)?${RegExp.escape(localName)}\\s*=\\s*(["\\\'])(.*?)\\1',
    dotAll: true,
    caseSensitive: false,
  ).firstMatch(attributes);
  return match == null ? null : _decodeXmlEntities(match.group(2) ?? '');
}

String _decodeXmlEntities(String value) {
  return value.replaceAllMapped(
    RegExp(r'&(?:#x[0-9A-Fa-f]+|#[0-9]+|amp|lt|gt|quot|apos);'),
    (match) {
      final entity = match.group(0)!;
      if (entity == '&amp;') return '&';
      if (entity == '&lt;') return '<';
      if (entity == '&gt;') return '>';
      if (entity == '&quot;') return '"';
      if (entity == '&apos;') return "'";
      if (entity.startsWith('&#x')) {
        return String.fromCharCode(
          int.parse(entity.substring(3, entity.length - 1), radix: 16),
        );
      }
      return String.fromCharCode(
        int.parse(entity.substring(2, entity.length - 1)),
      );
    },
  );
}

String sha256Hex(List<int> input) {
  const initialHash = <int>[
    0x6a09e667,
    0xbb67ae85,
    0x3c6ef372,
    0xa54ff53a,
    0x510e527f,
    0x9b05688c,
    0x1f83d9ab,
    0x5be0cd19,
  ];
  const constants = <int>[
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
  ];

  final bytes = List<int>.from(input);
  final bitLength = bytes.length * 8;
  bytes.add(0x80);
  while (bytes.length % 64 != 56) {
    bytes.add(0);
  }
  for (var shift = 56; shift >= 0; shift -= 8) {
    bytes.add((bitLength >> shift) & 0xff);
  }

  final hash = List<int>.from(initialHash);
  final words = List<int>.filled(64, 0);
  for (var offset = 0; offset < bytes.length; offset += 64) {
    for (var index = 0; index < 16; index++) {
      final start = offset + index * 4;
      words[index] =
          ((bytes[start] << 24) |
              (bytes[start + 1] << 16) |
              (bytes[start + 2] << 8) |
              bytes[start + 3]) &
          0xffffffff;
    }
    for (var index = 16; index < 64; index++) {
      final s0 =
          _rotateRight(words[index - 15], 7) ^
          _rotateRight(words[index - 15], 18) ^
          (words[index - 15] >> 3);
      final s1 =
          _rotateRight(words[index - 2], 17) ^
          _rotateRight(words[index - 2], 19) ^
          (words[index - 2] >> 10);
      words[index] =
          (words[index - 16] + s0 + words[index - 7] + s1) & 0xffffffff;
    }

    var a = hash[0];
    var b = hash[1];
    var c = hash[2];
    var d = hash[3];
    var e = hash[4];
    var f = hash[5];
    var g = hash[6];
    var h = hash[7];
    for (var index = 0; index < 64; index++) {
      final sum1 =
          _rotateRight(e, 6) ^ _rotateRight(e, 11) ^ _rotateRight(e, 25);
      final choose = (e & f) ^ ((~e) & g);
      final temp1 =
          (h + sum1 + choose + constants[index] + words[index]) & 0xffffffff;
      final sum0 =
          _rotateRight(a, 2) ^ _rotateRight(a, 13) ^ _rotateRight(a, 22);
      final majority = (a & b) ^ (a & c) ^ (b & c);
      final temp2 = (sum0 + majority) & 0xffffffff;
      h = g;
      g = f;
      f = e;
      e = (d + temp1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) & 0xffffffff;
    }
    hash[0] = (hash[0] + a) & 0xffffffff;
    hash[1] = (hash[1] + b) & 0xffffffff;
    hash[2] = (hash[2] + c) & 0xffffffff;
    hash[3] = (hash[3] + d) & 0xffffffff;
    hash[4] = (hash[4] + e) & 0xffffffff;
    hash[5] = (hash[5] + f) & 0xffffffff;
    hash[6] = (hash[6] + g) & 0xffffffff;
    hash[7] = (hash[7] + h) & 0xffffffff;
  }
  return hash.map((value) => value.toRadixString(16).padLeft(8, '0')).join();
}

int _rotateRight(int value, int amount) =>
    ((value >> amount) | (value << (32 - amount))) & 0xffffffff;
