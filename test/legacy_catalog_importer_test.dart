import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:store_collection_app/services/legacy_catalog_importer.dart';
import 'package:store_collection_app/utils/catalog_normalization.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'legacy_catalog_importer_test_',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('SHA-256 implementation matches the published abc vector', () {
    expect(
      sha256Hex(utf8.encode('abc')),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });

  test('Uncategorized system group ID is deterministic and brand scoped', () {
    expect(
      legacyCatalogUncategorizedGroupId('TlOswncJiWX7mwsf3U4e'),
      'system-group-TlOswncJiWX7mwsf3U4e-uncategorized',
    );
    expect(
      legacyCatalogUncategorizedGroupId('WLMnMVT6u1H2VQ0qziJ3'),
      'system-group-WLMnMVT6u1H2VQ0qziJ3-uncategorized',
    );
    expect(legacyCatalogUncategorizedGroupKey, 'uncategorized');
    expect(legacyCatalogUncategorizedGroupName, 'غير مصنف');
  });

  test('Normal product group ID is deterministic and brand scoped', () {
    final alAsalahGroupId = productGroupDocumentId(
      brandId: 'TlOswncJiWX7mwsf3U4e',
      groupName: 'Perfume Group',
    );
    final eqlidGroupId = productGroupDocumentId(
      brandId: 'WLMnMVT6u1H2VQ0qziJ3',
      groupName: 'Perfume Group',
    );

    expect(
      productGroupDocumentId(
        brandId: 'TlOswncJiWX7mwsf3U4e',
        groupName: '  PERFUME   GROUP ',
      ),
      alAsalahGroupId,
    );
    expect(alAsalahGroupId, startsWith('group-'));
    expect(eqlidGroupId, startsWith('group-'));
    expect(alAsalahGroupId, isNot(eqlidGroupId));
  });

  test(
    'Al-Asalah profile preserves raw values and ignores price columns',
    () async {
      final source = await _writeWorkbook(
        temporaryDirectory,
        name: 'al_asalah.xls',
        materialColumn: 7,
        groupColumn: 13,
        productRows: const [
          _FixtureProductRow(
            material: '1001-عطر الاختبار',
            group: '1-العطور',
            primaryUnit: 'حبه',
            unit2: 'علبه',
            unit3: 'اوقيه',
            ignoredPrice: '999.99',
          ),
        ],
      );

      final report = await const LegacyCatalogImporter().createDryRun(
        sourceFile: source,
        profileId: LegacyCatalogSourceProfileId.alAsalahLegacyCatalog,
        brandSelection: const LegacyCatalogBrandSelection.validated(
          documentId: 'TlOswncJiWX7mwsf3U4e',
          name: 'الأصالة',
          exists: true,
          evidence: LegacyBrandDocumentEvidence.localFixture,
        ),
      );

      expect(report.records, hasLength(1));
      final record = report.records.single;
      expect(record.legacyCode, '1001');
      expect(record.productName, 'عطر الاختبار');
      expect(record.rawMaterialValue, '1001-عطر الاختبار');
      expect(record.rawGroupValue, '1-العطور');
      expect(record.rawPrimaryUnit, 'حبه');
      expect(record.rawUnit2, 'علبه');
      expect(record.rawUnit3, 'اوقيه');
      expect(record.unitSuggestions, hasLength(3));
      expect(
        report.realGroupReady.single.toProductSourceMetadata(
          importId: 'preview-1',
        ),
        {
          'source_profile': 'al_asalah_legacy_catalog',
          'source_file_sha256': report.sourceHash,
          'source_sheet': 'Page1',
          'source_row': record.rowNumber,
          'raw_material_value': '1001-عطر الاختبار',
          'raw_group_value': '1-العطور',
          'raw_primary_unit': 'حبه',
          'raw_unit_2': 'علبه',
          'raw_unit_3': 'اوقيه',
          'original_group_missing': false,
          'fallback_system_group_assigned': false,
          'import_id': 'preview-1',
        },
      );
      expect(record.canUseFallbackSystemGroup, isFalse);
      expect(report.realGroupReady, hasLength(1));
      final expectedGroupId = productGroupDocumentId(
        brandId: record.brandId,
        groupName: record.groupName!,
      );
      expect(report.realGroupReady.single.assignedGroupId, expectedGroupId);
      expect(
        report.realGroupReady.single.toJson()['assigned_group_id'],
        expectedGroupId,
      );
      expect(report.normalGroupPlans, hasLength(1));
      final normalGroupPlan = report.normalGroupPlans.single;
      expect(normalGroupPlan.groupId, expectedGroupId);
      expect(normalGroupPlan.brandId, record.brandId);
      expect(normalGroupPlan.name, record.groupName);
      expect(normalGroupPlan.sourceLegacyCodes, [record.groupLegacyCode]);
      expect(normalGroupPlan.rawGroupValues, [record.rawGroupValue]);
      expect(normalGroupPlan.sourceRows, [record.rowNumber]);
      expect(
        normalGroupPlan.toJson(),
        containsPair('action', 'ensure_or_validate'),
      );
      expect(report.normalGroupsToEnsureOrValidateCount, 1);
      expect(report.uncategorizedReady, isEmpty);
      expect(report.blockedOtherRecords, isEmpty);
      expect(report.systemGroupPlans, isEmpty);
      expect(report.systemGroupsToEnsureCount, 0);
      expect(report.creates, hasLength(1));
      expect(report.toDetailedJson().toString(), isNot(contains('999.99')));
      expect(jsonEncode(report.toDetailedJson()), isNot(contains('"price"')));
    },
  );

  test(
    'Eqlid profile retains missing groups and makes suggestions only',
    () async {
      final source = await _writeWorkbook(
        temporaryDirectory,
        name: 'eqlid.xls',
        materialColumn: 8,
        groupColumn: 12,
        productRows: const [
          _FixtureProductRow(
            material: '09-100-عطر معروف',
            group: '9-عطور',
            primaryUnit: 'حبه',
          ),
          _FixtureProductRow(
            material: '09-101-عطر بلا مجموعة',
            group: '',
            primaryUnit: 'حيه',
          ),
        ],
      );

      final report = await const LegacyCatalogImporter().createDryRun(
        sourceFile: source,
        profileId: LegacyCatalogSourceProfileId.eqlidLegacyCatalog,
        brandSelection: const LegacyCatalogBrandSelection.validated(
          documentId: 'WLMnMVT6u1H2VQ0qziJ3',
          name: 'اقليد',
          exists: true,
          evidence: LegacyBrandDocumentEvidence.firestoreEmulator,
        ),
      );

      expect(report.missingGroupCount, 1);
      final missing = report.records.singleWhere(
        (record) => record.hasMissingGroup,
      );
      expect(missing.rawGroupValue, isEmpty);
      expect(missing.groupSuggestion?.groupLegacyCode, '9');
      expect(
        missing.groupSuggestion?.confidence,
        LegacySuggestionConfidence.high,
      );
      expect(missing.groupSuggestion?.reason, isNotEmpty);
      expect(missing.groupSuggestion?.toJson()['approved'], isFalse);
      expect(report.prefixMappingCandidates, hasLength(1));
      expect(report.prefixMappingCandidates.single.sourceRows, [
        missing.rowNumber,
      ]);
      expect(
        report.prefixMappingCandidates.single.toJson()['approved'],
        isFalse,
      );
      expect(missing.unitSuggestions.single.suggestedValue, 'حبة');
      expect(missing.unitSuggestions.single.toJson()['approved'], isFalse);
      expect(missing.canUseFallbackSystemGroup, isTrue);
      final fallbackEntry = report.uncategorizedReady.single;
      expect(fallbackEntry.assignsUncategorizedGroup, isTrue);
      expect(
        fallbackEntry.assignedSystemGroupId,
        'system-group-WLMnMVT6u1H2VQ0qziJ3-uncategorized',
      );
      final sourceMetadata = fallbackEntry.toProductSourceMetadata();
      expect(sourceMetadata['raw_group_value'], isEmpty);
      expect(sourceMetadata, containsPair('original_group_missing', true));
      expect(
        sourceMetadata,
        containsPair('fallback_system_group_assigned', true),
      );
      expect(report.creates, hasLength(2));
      expect(report.realGroupReady, hasLength(1));
      expect(report.realGroupReady.single.assignedGroupId, isNotEmpty);
      expect(report.normalGroupPlans, hasLength(1));
      expect(
        report.normalGroupPlans.single.groupId,
        report.realGroupReady.single.assignedGroupId,
      );
      expect(report.uncategorizedReady, hasLength(1));
      expect(report.blockedOtherRecords, isEmpty);
      expect(report.systemGroupPlans, hasLength(1));
      expect(report.systemGroupsToEnsureCount, 1);
      expect(report.systemGroupPlans.single.toJson()['action'], 'ensure');
      expect(
        report.systemGroupPlans.single.groupId,
        'system-group-WLMnMVT6u1H2VQ0qziJ3-uncategorized',
      );
    },
  );

  test(
    'missing primary unit and ambiguous values are blocking findings',
    () async {
      final source = await _writeWorkbook(
        temporaryDirectory,
        name: 'eqlid_invalid.xls',
        materialColumn: 8,
        groupColumn: 12,
        productRows: const [
          _FixtureProductRow(
            material: '27014-....',
            group: '',
            primaryUnit: '',
          ),
          _FixtureProductRow(material: '1-1', group: '', primaryUnit: 'حيه'),
        ],
      );

      final report = await const LegacyCatalogImporter().createDryRun(
        sourceFile: source,
        profileId: LegacyCatalogSourceProfileId.eqlidLegacyCatalog,
        brandSelection: const LegacyCatalogBrandSelection.contractOnly(
          documentId: 'WLMnMVT6u1H2VQ0qziJ3',
          name: 'اقليد',
        ),
      );

      expect(report.records, hasLength(2));
      expect(report.invalidRecords, hasLength(2));
      expect(report.creates, isEmpty);
      expect(report.uncategorizedReady, isEmpty);
      expect(report.blockedOtherRecords, hasLength(2));
      expect(report.systemGroupPlans, isEmpty);
      expect(
        report.records.every((record) => !record.canUseFallbackSystemGroup),
        isTrue,
      );
      expect(
        (report.toDetailedJson()['blocked_other'] as List<dynamic>).every(
          (entry) =>
              !((entry as Map<String, dynamic>)['group_resolution']
                      as Map<String, dynamic>)
                  .containsKey('fallback_system_group_id'),
        ),
        isTrue,
      );
      expect(report.missingPrimaryUnitCount, 1);
      expect(
        report.invalidRecords
            .expand((entry) => entry.issues)
            .map((issue) => issue.code),
        containsAll({'missing_primary_unit', 'ambiguous_product_name'}),
      );
    },
  );

  test(
    'profile validation aborts when configured columns do not match',
    () async {
      final source = await _writeWorkbook(
        temporaryDirectory,
        name: 'wrong_profile.xls',
        materialColumn: 7,
        groupColumn: 13,
        productRows: const [
          _FixtureProductRow(
            material: '1001-منتج',
            group: '1-مجموعة',
            primaryUnit: 'حبه',
          ),
        ],
      );

      expect(
        () => const LegacyCatalogImporter().createDryRun(
          sourceFile: source,
          profileId: LegacyCatalogSourceProfileId.eqlidLegacyCatalog,
          brandSelection: const LegacyCatalogBrandSelection.contractOnly(
            documentId: 'WLMnMVT6u1H2VQ0qziJ3',
            name: 'اقليد',
          ),
        ),
        throwsA(isA<LegacyCatalogImportException>()),
      );
    },
  );

  test(
    'brand contract rejects wrong IDs, names, and missing documents',
    () async {
      final source = await _writeWorkbook(
        temporaryDirectory,
        name: 'brand_contract.xls',
        materialColumn: 7,
        groupColumn: 13,
        productRows: const [
          _FixtureProductRow(
            material: '1001-منتج',
            group: '1-مجموعة',
            primaryUnit: 'حبه',
          ),
        ],
      );
      const importer = LegacyCatalogImporter();

      for (final selection in const [
        LegacyCatalogBrandSelection.contractOnly(
          documentId: 'wrong',
          name: 'الأصالة',
        ),
        LegacyCatalogBrandSelection.contractOnly(
          documentId: 'TlOswncJiWX7mwsf3U4e',
          name: 'اسم غير مطابق',
        ),
        LegacyCatalogBrandSelection.validated(
          documentId: 'TlOswncJiWX7mwsf3U4e',
          name: 'الأصالة',
          exists: false,
          evidence: LegacyBrandDocumentEvidence.firestoreEmulator,
        ),
      ]) {
        expect(
          () => importer.createDryRun(
            sourceFile: source,
            profileId: LegacyCatalogSourceProfileId.alAsalahLegacyCatalog,
            brandSelection: selection,
          ),
          throwsA(isA<LegacyCatalogImportException>()),
        );
      }
    },
  );

  test(
    'content-based skipping classifies headers, blanks, and totals',
    () async {
      final source = await _writeWorkbook(
        temporaryDirectory,
        name: 'report_rows.xls',
        materialColumn: 7,
        groupColumn: 13,
        productRows: const [
          _FixtureProductRow(
            material: '1001-منتج',
            group: '1-مجموعة',
            primaryUnit: 'حبه',
          ),
        ],
        addRepeatedHeader: true,
        addBlankAndTotals: true,
      );

      final report = await const LegacyCatalogImporter().createDryRun(
        sourceFile: source,
        profileId: LegacyCatalogSourceProfileId.alAsalahLegacyCatalog,
        brandSelection: const LegacyCatalogBrandSelection.contractOnly(
          documentId: 'TlOswncJiWX7mwsf3U4e',
          name: 'الأصالة',
        ),
      );

      expect(report.records, hasLength(1));
      expect(
        report.skippedRows.map((row) => row.reason),
        containsAll({
          'report_title',
          'repeated_page_header',
          'blank_row',
          'report_summary',
          'report_total',
        }),
      );
    },
  );

  test('duplicates are reported and do not become create operations', () async {
    final source = await _writeWorkbook(
      temporaryDirectory,
      name: 'duplicates.xls',
      materialColumn: 7,
      groupColumn: 13,
      productRows: const [
        _FixtureProductRow(
          material: '1001-المنتج الأول',
          group: '1-مجموعة',
          primaryUnit: 'حبه',
        ),
        _FixtureProductRow(
          material: '1001-المنتج الثاني',
          group: '1-مجموعة',
          primaryUnit: 'حبه',
        ),
        _FixtureProductRow(
          material: '1002-المنتج الأول',
          group: '1-مجموعة',
          primaryUnit: 'حبه',
        ),
      ],
    );

    final report = await const LegacyCatalogImporter().createDryRun(
      sourceFile: source,
      profileId: LegacyCatalogSourceProfileId.alAsalahLegacyCatalog,
      brandSelection: const LegacyCatalogBrandSelection.contractOnly(
        documentId: 'TlOswncJiWX7mwsf3U4e',
        name: 'الأصالة',
      ),
    );

    expect(report.duplicates.map((duplicate) => duplicate.keyType), {
      'legacy_code',
      'normalized_name',
    });
    expect(report.creates, isEmpty);
    expect(report.blockedOtherRecords, hasLength(3));
    expect(report.duplicateRecordCount, 3);
    expect(
      report.toSummaryJson()['blocking_rows'],
      unorderedEquals(
        report.blockedOtherRecords.map((record) => record.rowNumber),
      ),
    );
  });

  test(
    'blocked missing-group duplicates never claim a fallback assignment',
    () async {
      final source = await _writeWorkbook(
        temporaryDirectory,
        name: 'missing_group_duplicates.xls',
        materialColumn: 8,
        groupColumn: 12,
        productRows: const [
          _FixtureProductRow(
            material: '09-100-المنتج الأول',
            group: '',
            primaryUnit: 'حبه',
          ),
          _FixtureProductRow(
            material: '09-100-المنتج الثاني',
            group: '',
            primaryUnit: 'حبه',
          ),
        ],
      );
      final report = await const LegacyCatalogImporter().createDryRun(
        sourceFile: source,
        profileId: LegacyCatalogSourceProfileId.eqlidLegacyCatalog,
        brandSelection: const LegacyCatalogBrandSelection.contractOnly(
          documentId: 'WLMnMVT6u1H2VQ0qziJ3',
          name: 'اقليد',
        ),
      );

      expect(report.creates, isEmpty);
      expect(report.blockedOtherRecords, hasLength(2));
      expect(report.systemGroupPlans, isEmpty);
      final blocked = report.toDetailedJson()['blocked_other'] as List<dynamic>;
      expect(
        blocked.every((entry) {
          final record = entry as Map<String, dynamic>;
          final resolution = record['group_resolution'] as Map<String, dynamic>;
          return resolution['original_group_missing'] == true &&
              resolution['fallback_system_group_assigned'] == false &&
              !resolution.containsKey('fallback_system_group_id');
        }),
        isTrue,
      );
    },
  );

  test(
    'a repeated plan is idempotent and respects manual corrections',
    () async {
      final source = await _writeWorkbook(
        temporaryDirectory,
        name: 'idempotent.xls',
        materialColumn: 7,
        groupColumn: 13,
        productRows: const [
          _FixtureProductRow(
            material: '1001-منتج ثابت',
            group: '',
            primaryUnit: 'حبه',
          ),
        ],
      );
      const importer = LegacyCatalogImporter();
      const brand = LegacyCatalogBrandSelection.contractOnly(
        documentId: 'TlOswncJiWX7mwsf3U4e',
        name: 'الأصالة',
      );
      final first = await importer.createDryRun(
        sourceFile: source,
        profileId: LegacyCatalogSourceProfileId.alAsalahLegacyCatalog,
        brandSelection: brand,
      );
      final record = first.records.single;
      final fallbackGroupId = legacyCatalogUncategorizedGroupId(record.brandId);
      expect(first.creates, hasLength(1));
      expect(first.uncategorizedReady, hasLength(1));
      expect(first.systemGroupsToEnsureCount, 1);
      expect(first.systemGroupPlans.single.groupId, fallbackGroupId);

      final repeated = await importer.createDryRun(
        sourceFile: source,
        profileId: LegacyCatalogSourceProfileId.alAsalahLegacyCatalog,
        brandSelection: brand,
        existingProducts: [
          ExistingLegacyCatalogProduct(
            productId: 'product-1',
            brandId: record.brandId,
            legacyCode: record.legacyCode,
            normalizedName: normalizeCatalogText(record.productName!),
            sourceFingerprint: record.fingerprint,
          ),
        ],
      );
      expect(repeated.creates, isEmpty);
      expect(repeated.updates, isEmpty);
      expect(repeated.unchanged, hasLength(1));
      expect(repeated.uncategorizedReady, hasLength(1));
      expect(repeated.systemGroupsToEnsureCount, 1);
      expect(repeated.systemGroupPlans.single.groupId, fallbackGroupId);
      expect(repeated.systemGroupPlans.single.toJson()['action'], 'ensure');
      expect(repeated.duplicates, isEmpty);

      final protected = await importer.createDryRun(
        sourceFile: source,
        profileId: LegacyCatalogSourceProfileId.alAsalahLegacyCatalog,
        brandSelection: brand,
        existingProducts: [
          ExistingLegacyCatalogProduct(
            productId: 'product-1',
            brandId: record.brandId,
            legacyCode: record.legacyCode,
            normalizedName: normalizeCatalogText(record.productName!),
            sourceFingerprint: 'older-import-fingerprint',
            hasManualCorrections: true,
          ),
        ],
      );
      expect(protected.updates, isEmpty);
      expect(protected.blockedOtherRecords, hasLength(1));
      expect(protected.systemGroupPlans, isEmpty);
      expect(
        protected.invalidRecords.single.issues.single.code,
        'manual_correction_conflict',
      );
    },
  );

  final userProfile = Platform.environment['USERPROFILE'];
  final alAsalahSource = File(
    Platform.environment['AL_ASALAH_LEGACY_CATALOG_PATH'] ??
        '${userProfile ?? ''}\\Downloads\\الاصناف مع الوحدات - الاصالة.xls',
  );
  final eqlidSource = File(
    Platform.environment['EQLID_LEGACY_CATALOG_PATH'] ??
        '${userProfile ?? ''}\\Downloads\\دليل المواد - فرع اقليد جبران.xls',
  );

  test(
    'real Al-Asalah source independently matches its measured structure',
    () async {
      final report = await const LegacyCatalogImporter().createDryRun(
        sourceFile: alAsalahSource,
        profileId: LegacyCatalogSourceProfileId.alAsalahLegacyCatalog,
        brandSelection: const LegacyCatalogBrandSelection.contractOnly(
          documentId: 'TlOswncJiWX7mwsf3U4e',
          name: 'الأصالة',
        ),
      );

      expect(
        report.sourceHash,
        '745b544c00d608929a694326a78dfcd00857f9a5569a6452491feeb5d7c47001',
      );
      expect(report.worksheetName, 'Page1');
      expect(report.records, hasLength(91));
      expect(report.distinctPopulatedGroupCount, 10);
      expect(report.missingGroupCount, 0);
      expect(report.missingPrimaryUnitCount, 0);
      expect(report.unit2Count, 30);
      expect(report.unit3Count, 21);
      expect(report.invalidRecords, isEmpty);
      expect(report.duplicates, isEmpty);
      expect(report.skippedRows, hasLength(14));
      expect(report.creates, hasLength(91));
      expect(report.realGroupReady, hasLength(91));
      expect(report.normalGroupPlans, hasLength(10));
      final plannedGroupIds = report.normalGroupPlans
          .map((plan) => plan.groupId)
          .toSet();
      expect(
        report.realGroupReady.every(
          (entry) => plannedGroupIds.contains(entry.assignedGroupId),
        ),
        isTrue,
      );
      expect(report.uncategorizedReady, isEmpty);
      expect(report.blockedOtherRecords, isEmpty);
      expect(report.systemGroupPlans, isEmpty);
      expect(report.systemGroupsToEnsureCount, 0);
    },
    skip: alAsalahSource.existsSync()
        ? false
        : 'Set AL_ASALAH_LEGACY_CATALOG_PATH to run this read-only source test.',
  );

  test(
    'real Eqlid source independently matches its measured structure',
    () async {
      final report = await const LegacyCatalogImporter().createDryRun(
        sourceFile: eqlidSource,
        profileId: LegacyCatalogSourceProfileId.eqlidLegacyCatalog,
        brandSelection: const LegacyCatalogBrandSelection.contractOnly(
          documentId: 'WLMnMVT6u1H2VQ0qziJ3',
          name: 'اقليد',
        ),
      );

      expect(
        report.sourceHash,
        '0da67bbb869da6c60316deb91c8768aadb654d73b17709eec07f4d5b4743b098',
      );
      expect(report.worksheetName, 'Page1');
      expect(report.records, hasLength(2138));
      expect(report.distinctPopulatedGroupCount, 22);
      expect(report.missingGroupCount, 1293);
      expect(report.missingPrimaryUnitCount, 1);
      expect(report.unit2Count, 564);
      expect(report.unit3Count, 25);
      expect(report.duplicates, isEmpty);
      expect(report.invalidRecords, hasLength(7));
      expect(report.invalidRecords.map((entry) => entry.record.rowNumber), {
        1035,
        1177,
        1655,
        1664,
        1739,
        1960,
        2180,
      });
      expect(report.skippedRows, hasLength(124));
      expect(report.creates, hasLength(2131));
      expect(report.realGroupReady, hasLength(845));
      expect(report.normalGroupPlans, hasLength(22));
      final plannedGroupIds = report.normalGroupPlans
          .map((plan) => plan.groupId)
          .toSet();
      expect(
        report.realGroupReady.every(
          (entry) => plannedGroupIds.contains(entry.assignedGroupId),
        ),
        isTrue,
      );
      expect(report.uncategorizedReady, hasLength(1286));
      expect(report.blockedOtherRecords, hasLength(7));
      expect(report.systemGroupsToEnsureCount, 1);
      expect(
        report.systemGroupPlans.single.groupId,
        'system-group-WLMnMVT6u1H2VQ0qziJ3-uncategorized',
      );
      expect(report.groupSuggestionCount, 1287);
    },
    skip: eqlidSource.existsSync()
        ? false
        : 'Set EQLID_LEGACY_CATALOG_PATH to run this read-only source test.',
  );
}

class _FixtureProductRow {
  final String material;
  final String group;
  final String primaryUnit;
  final String unit2;
  final String unit3;
  final String? ignoredPrice;

  const _FixtureProductRow({
    required this.material,
    required this.group,
    required this.primaryUnit,
    this.unit2 = '',
    this.unit3 = '',
    this.ignoredPrice,
  });
}

Future<File> _writeWorkbook(
  Directory directory, {
  required String name,
  required int materialColumn,
  required int groupColumn,
  required List<_FixtureProductRow> productRows,
  bool addRepeatedHeader = false,
  bool addBlankAndTotals = false,
}) async {
  final rows = <String>[
    _row({2: 'جرد المواد'}),
    _row({1: 'الوحدة', materialColumn: 'المادة', groupColumn: 'المجموعة'}),
    _row({1: 'الوحدة 3', 4: 'الوحدة 2', 6: 'الوحدة'}),
    for (final product in productRows)
      _row({
        if (product.unit3.isNotEmpty) 1: product.unit3,
        if (product.unit2.isNotEmpty) 4: product.unit2,
        if (product.primaryUnit.isNotEmpty) 6: product.primaryUnit,
        materialColumn: product.material,
        if (product.ignoredPrice != null) 10: product.ignoredPrice!,
        if (product.group.isNotEmpty) groupColumn: product.group,
      }),
    if (addRepeatedHeader)
      _row({1: 'الوحدة', materialColumn: 'المادة', groupColumn: 'المجموعة'}),
    if (addRepeatedHeader) _row({1: 'الوحدة 3', 4: 'الوحدة 2', 6: 'الوحدة'}),
    if (addBlankAndTotals) '<Row/>',
    if (addBlankAndTotals)
      _row({3: 'الكمية', 5: 'الخارج', 8: 'داخل', 11: 'المجموع'}),
    if (addBlankAndTotals) _row({3: '10.00', 5: '5.00', 8: '15.00'}),
  ];
  final file = File('${directory.path}${Platform.pathSeparator}$name');
  await file.writeAsString('''<?xml version="1.0"?>
<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"
 xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">
 <Worksheet ss:Name="Page1">
  <Table>
   ${rows.join('\n   ')}
  </Table>
 </Worksheet>
</Workbook>''');
  return file;
}

String _row(Map<int, String> cells) {
  final sortedColumns = cells.keys.toList()..sort();
  return '<Row>${sortedColumns.map((column) {
    final value = const HtmlEscape(HtmlEscapeMode.element).convert(cells[column]!);
    return '<Cell ss:Index="$column"><Data ss:Type="String">$value</Data></Cell>';
  }).join()}</Row>';
}
