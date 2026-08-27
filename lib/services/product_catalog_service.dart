import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:store_collection_app/models/product_catalog_model.dart';
import 'package:store_collection_app/utils/catalog_normalization.dart';

class ProductCatalogPage {
  final List<ProductCatalogModel> products;
  final int nextOffset;
  final bool hasMore;

  const ProductCatalogPage({
    required this.products,
    required this.nextOffset,
    required this.hasMore,
  });
}

/// Applies the same Arabic-aware normalized search everywhere the catalog is
/// presented.  Firestore can efficiently search a prefix, but not an arbitrary
/// substring, so callers use this after loading a brand's active catalog.
List<ProductCatalogModel> filterCatalogProducts(
  Iterable<ProductCatalogModel> products,
  String searchText,
) {
  final normalizedSearch = normalizeCatalogText(searchText);
  final searchTokens = tokenizeCatalogSearch(searchText);
  final source = products.toList(growable: false);
  if (searchTokens.isEmpty) return source;

  String normalizedProductName(ProductCatalogModel product) {
    final stored = product.normalizedName.trim();
    return stored.isEmpty ? normalizeCatalogText(product.name) : stored;
  }

  final matches = source
      .where((product) {
        final name = normalizedProductName(product);
        final legacyCode = normalizeCatalogText(product.legacyCode ?? '');
        return searchTokens.every(name.contains) ||
            (searchTokens.length == 1 && legacyCode.contains(normalizedSearch));
      })
      .toList(growable: false);
  matches.sort((left, right) {
    int rank(ProductCatalogModel product) {
      final name = normalizedProductName(product);
      if (name == normalizedSearch) return 0;
      if (name.startsWith(normalizedSearch)) return 1;
      if (searchTokens.length > 1 &&
          _catalogTokensAppearInOrder(name, searchTokens)) {
        return 2;
      }
      if (searchTokens.every(name.contains)) return 3;
      return 4; // A legacy-code-only match.
    }

    final rankComparison = rank(left).compareTo(rank(right));
    if (rankComparison != 0) return rankComparison;
    final nameComparison = normalizedProductName(
      left,
    ).compareTo(normalizedProductName(right));
    return nameComparison != 0 ? nameComparison : left.id.compareTo(right.id);
  });
  return matches;
}

bool _catalogTokensAppearInOrder(String name, List<String> tokens) {
  var searchStart = 0;
  for (final token in tokens) {
    final tokenIndex = name.indexOf(token, searchStart);
    if (tokenIndex < 0) return false;
    searchStart = tokenIndex + token.length;
  }
  return true;
}

class ProductCatalogService {
  final FirebaseFirestore? _providedFirestore;
  // Catalog selection is public to the same signed-in session.  The default
  // Firestore client is shared by all screens, so share its per-brand cache as
  // well: reopening Purchase, Consumption, or Transfer does not re-download
  // the same active catalog. Injected clients deliberately keep isolated
  // caches for tests and previews.
  static final Map<String, Future<List<ProductCatalogModel>>>
  _sharedActiveCatalogCache = <String, Future<List<ProductCatalogModel>>>{};
  static final Map<String, Future<Map<String, String>>>
  _sharedActiveGroupNamesCache = <String, Future<Map<String, String>>>{};
  final Map<String, Future<List<ProductCatalogModel>>>
  _localActiveCatalogCache = <String, Future<List<ProductCatalogModel>>>{};
  final Map<String, Future<Map<String, String>>> _localActiveGroupNamesCache =
      <String, Future<Map<String, String>>>{};
  final Map<String, Stream<List<ProductGroupModel>>> _groupStreams =
      <String, Stream<List<ProductGroupModel>>>{};
  final Map<String, Stream<List<ProductCatalogModel>>> _productStreams =
      <String, Stream<List<ProductCatalogModel>>>{};

  ProductCatalogService({FirebaseFirestore? firestore})
    : _providedFirestore = firestore;

  FirebaseFirestore get _firestore =>
      _providedFirestore ?? FirebaseFirestore.instance;

  Map<String, Future<List<ProductCatalogModel>>> get _activeCatalogCache =>
      _providedFirestore == null
      ? _sharedActiveCatalogCache
      : _localActiveCatalogCache;

  Map<String, Future<Map<String, String>>> get _activeGroupNamesCache =>
      _providedFirestore == null
      ? _sharedActiveGroupNamesCache
      : _localActiveGroupNamesCache;

  void _invalidateBrandCache(String brandId) {
    final cacheKey = _cacheKey(brandId);
    _activeCatalogCache.remove(cacheKey);
    _activeGroupNamesCache.remove(cacheKey);
  }

  /// Clears the active, local-search candidate cache after the backend tells a
  /// caller that a selected product/unit snapshot is no longer authoritative.
  void invalidateActiveCatalog({required String brandId}) {
    _invalidateBrandCache(_required(brandId, 'Brand ID'));
  }

  String _cacheKey(String brandId) {
    // Keep cached catalog identities scoped to the signed-in Firebase user;
    // a sign-out or account switch must never inherit another session cache.
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
    return '$uid\u001f$brandId';
  }

  CollectionReference<Map<String, dynamic>> get _groups =>
      _firestore.collection(ProductCatalogCollections.groups);

  CollectionReference<Map<String, dynamic>> get _products =>
      _firestore.collection(ProductCatalogCollections.products);

  CollectionReference<Map<String, dynamic>> get _uniqueKeys =>
      _firestore.collection(ProductCatalogCollections.uniqueKeys);

  CollectionReference<Map<String, dynamic>> get _auditEvents =>
      _firestore.collection(ProductCatalogCollections.auditEvents);

  Stream<List<ProductGroupModel>> watchGroups({
    required String brandId,
    bool activeOnly = true,
  }) {
    _requireValue(brandId, 'Brand ID');
    Query<Map<String, dynamic>> query = _groups.where(
      ProductCatalogFields.brandId,
      isEqualTo: brandId.trim(),
    );
    if (activeOnly) {
      query = query.where(ProductCatalogFields.active, isEqualTo: true);
    }
    final cacheKey = '${_cacheKey(brandId.trim())}|$activeOnly';
    return _groupStreams.putIfAbsent(
      cacheKey,
      () => query
          .orderBy(ProductCatalogFields.normalizedName)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map((doc) => ProductGroupModel.fromMap(doc.id, doc.data()))
                .toList(growable: false),
          ),
    );
  }

  Stream<List<ProductCatalogModel>> watchProducts({
    required String brandId,
    String? groupId,
    bool activeOnly = true,
  }) {
    _requireValue(brandId, 'Brand ID');
    Query<Map<String, dynamic>> query = _products.where(
      ProductCatalogFields.brandId,
      isEqualTo: brandId.trim(),
    );
    final selectedGroup = groupId?.trim() ?? '';
    if (selectedGroup.isNotEmpty) {
      query = query.where(
        ProductCatalogFields.groupId,
        isEqualTo: selectedGroup,
      );
    }
    if (activeOnly) {
      query = query.where(ProductCatalogFields.active, isEqualTo: true);
    }
    final cacheKey = '${_cacheKey(brandId.trim())}|$selectedGroup|$activeOnly';
    return _productStreams.putIfAbsent(
      cacheKey,
      () => query
          .orderBy(ProductCatalogFields.normalizedName)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map((doc) => ProductCatalogModel.fromMap(doc.id, doc.data()))
                .toList(growable: false),
          ),
    );
  }

  /// Loads one catalog record after a successful managed creation flow. The
  /// caller still receives the canonical server-validated product identity.
  Future<ProductCatalogModel?> fetchProduct(String productId) async {
    final cleanProductId = _required(productId, 'Product ID');
    final snapshot = await _products.doc(cleanProductId).get();
    final data = snapshot.data();
    return data == null ? null : ProductCatalogModel.fromMap(snapshot.id, data);
  }

  Future<ProductCatalogPage> fetchActiveProductsPage({
    required String brandId,
    String? groupId,
    String search = '',
    int offset = 0,
    int pageSize = 30,
  }) async {
    final cleanBrandId = _required(brandId, 'Brand ID');
    if (pageSize < 1) throw ArgumentError.value(pageSize, 'pageSize');
    final activeProducts = await _activeProductsForBrand(cleanBrandId);
    final cleanGroupId = groupId?.trim() ?? '';
    final groupProducts = cleanGroupId.isEmpty
        ? activeProducts
        : activeProducts
              .where((product) => product.groupId == cleanGroupId)
              .toList(growable: false);
    final matches = filterCatalogProducts(groupProducts, search);
    final safeOffset = offset < 0
        ? 0
        : offset > matches.length
        ? matches.length
        : offset;
    final nextOffset = (safeOffset + pageSize).clamp(0, matches.length);
    return ProductCatalogPage(
      products: matches.sublist(safeOffset, nextOffset),
      nextOffset: nextOffset,
      hasMore: nextOffset < matches.length,
    );
  }

  /// Resolves catalog group IDs to display names without copying names into
  /// product identities. Callers must hide an unresolved group rather than
  /// falling back to the opaque document ID.
  Future<Map<String, String>> fetchActiveGroupNames({required String brandId}) {
    final cleanBrandId = _required(brandId, 'Brand ID');
    return _activeGroupNamesCache.putIfAbsent(
      _cacheKey(cleanBrandId),
      () async {
        final snapshot = await _groups
            .where(ProductCatalogFields.brandId, isEqualTo: cleanBrandId)
            .where(ProductCatalogFields.active, isEqualTo: true)
            .get();
        final names = <String, String>{};
        for (final doc in snapshot.docs) {
          final group = ProductGroupModel.fromMap(doc.id, doc.data());
          final name = group.name.trim();
          if (name.isEmpty) continue;
          names[doc.id] = name;
          if (group.id.isNotEmpty) names[group.id] = name;
        }
        return Map.unmodifiable(names);
      },
    );
  }

  Future<List<ProductCatalogModel>> _activeProductsForBrand(String brandId) {
    return _activeCatalogCache.putIfAbsent(_cacheKey(brandId), () async {
      final snapshot = await _products
          .where(ProductCatalogFields.brandId, isEqualTo: brandId)
          .where(ProductCatalogFields.active, isEqualTo: true)
          .orderBy(ProductCatalogFields.normalizedName)
          .get();
      return List.unmodifiable(
        snapshot.docs
            .map((doc) => ProductCatalogModel.fromMap(doc.id, doc.data()))
            .toList(growable: false),
      );
    });
  }

  Stream<List<ProductAuditEvent>> watchProductAudit({
    required String productId,
  }) {
    return _watchAudit(entityType: 'product', entityId: productId);
  }

  Stream<List<ProductAuditEvent>> watchGroupAudit({required String groupId}) {
    return _watchAudit(entityType: 'product_group', entityId: groupId);
  }

  Stream<List<ProductAuditEvent>> _watchAudit({
    required String entityType,
    required String entityId,
  }) {
    _requireValue(entityId, 'Entity ID');
    return _auditEvents
        .where('entity_type', isEqualTo: entityType)
        .where('entity_id', isEqualTo: entityId.trim())
        .orderBy('created_at', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => ProductAuditEvent.fromMap(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  Stream<ProductAccountingProfile?> watchAccountingProfile({
    required String productId,
  }) {
    _requireValue(productId, 'Product ID');
    return _firestore
        .collection(ProductCatalogCollections.accountingProfiles)
        .doc(productId.trim())
        .snapshots()
        .map((snapshot) {
          final data = snapshot.data();
          return data == null ? null : ProductAccountingProfile.fromMap(data);
        });
  }

  Future<String> createGroup({
    required CatalogActor actor,
    required String brandId,
    required String name,
    String? legacyCode,
  }) async {
    _requireCatalogManager(actor);
    final cleanBrandId = _required(brandId, 'Brand ID');
    final cleanName = _required(name, 'Group name');
    if (UncategorizedProductGroupContract.isReservedIdentity(
      name: cleanName,
      legacyCode: legacyCode,
    )) {
      throw ArgumentError(
        'The uncategorized system-group identity is reserved.',
      );
    }
    final normalizedName = normalizeCatalogText(cleanName);
    final cleanLegacyCode = _optional(legacyCode);
    final groupId = productGroupDocumentId(
      brandId: cleanBrandId,
      groupName: cleanName,
    );
    final brandRef = _firestore.collection('brands').doc(cleanBrandId);
    final groupRef = _groups.doc(groupId);
    final auditRef = _auditEvents.doc();

    await _firestore.runTransaction((transaction) async {
      final brand = await transaction.get(brandRef);
      final existing = await transaction.get(groupRef);
      if (!brand.exists) throw StateError('The selected brand does not exist.');
      if (existing.exists) {
        throw StateError('A normalized duplicate group already exists.');
      }

      final groupData = <String, dynamic>{
        ProductCatalogFields.id: groupId,
        ProductCatalogFields.brandId: cleanBrandId,
        ProductCatalogFields.name: cleanName,
        ProductCatalogFields.normalizedName: normalizedName,
        if (cleanLegacyCode != null)
          ProductCatalogFields.legacyCode: cleanLegacyCode,
        ProductCatalogFields.isSystemGroup: false,
        ProductCatalogFields.active: true,
        ProductCatalogFields.lastAuditEventId: auditRef.id,
        ProductCatalogFields.createdBy: actor.uid,
        ProductCatalogFields.createdByName: actor.name,
        ProductCatalogFields.createdAt: FieldValue.serverTimestamp(),
        ProductCatalogFields.updatedBy: actor.uid,
        ProductCatalogFields.updatedByName: actor.name,
        ProductCatalogFields.updatedAt: FieldValue.serverTimestamp(),
      };
      transaction.set(groupRef, groupData);
      transaction.set(
        auditRef,
        _auditData(
          id: auditRef.id,
          entityType: 'product_group',
          entityId: groupId,
          brandId: cleanBrandId,
          action: 'created',
          actor: actor,
          after: _groupAuditSnapshot(groupData),
        ),
      );
    });
    return groupId;
  }

  /// Ensures exactly one reserved Uncategorized group for [brandId].
  ///
  /// Repeated and concurrent calls are idempotent. A document occupying the
  /// deterministic ID with another identity is never overwritten.
  Future<String> ensureUncategorizedGroup({
    required CatalogActor actor,
    required String brandId,
  }) async {
    _requireCatalogManager(actor);
    final cleanBrandId = _required(brandId, 'Brand ID');
    final groupId = UncategorizedProductGroupContract.documentIdForBrand(
      cleanBrandId,
    );
    final brandRef = _firestore.collection('brands').doc(cleanBrandId);
    final groupRef = _groups.doc(groupId);
    final auditRef = _auditEvents.doc();

    await _firestore.runTransaction((transaction) async {
      final brand = await transaction.get(brandRef);
      final existing = await transaction.get(groupRef);
      if (!brand.exists) throw StateError('The selected brand does not exist.');
      final existingData = existing.data();
      if (existingData != null) {
        if (!UncategorizedProductGroupContract.matchesExistingDocument(
          documentId: existing.id,
          brandId: cleanBrandId,
          data: existingData,
        )) {
          throw StateError(
            'The reserved uncategorized group ID is occupied by a conflicting document.',
          );
        }
        return;
      }

      final groupData = <String, dynamic>{
        ProductCatalogFields.id: groupId,
        ProductCatalogFields.brandId: cleanBrandId,
        ProductCatalogFields.name:
            UncategorizedProductGroupContract.displayName,
        ProductCatalogFields.normalizedName: normalizeCatalogText(
          UncategorizedProductGroupContract.displayName,
        ),
        ProductCatalogFields.active: true,
        ProductCatalogFields.isSystemGroup: true,
        ProductCatalogFields.systemKey:
            UncategorizedProductGroupContract.systemKey,
        ProductCatalogFields.lastAuditEventId: auditRef.id,
        ProductCatalogFields.createdBy: actor.uid,
        ProductCatalogFields.createdByName: actor.name,
        ProductCatalogFields.createdAt: FieldValue.serverTimestamp(),
        ProductCatalogFields.updatedBy: actor.uid,
        ProductCatalogFields.updatedByName: actor.name,
        ProductCatalogFields.updatedAt: FieldValue.serverTimestamp(),
      };
      transaction.set(groupRef, groupData);
      transaction.set(
        auditRef,
        _auditData(
          id: auditRef.id,
          entityType: 'product_group',
          entityId: groupId,
          brandId: cleanBrandId,
          action: 'system_group_created',
          actor: actor,
          after: _groupAuditSnapshot(groupData),
        ),
      );
    });
    return groupId;
  }

  Future<String> createProduct({
    required CatalogActor actor,
    required String brandId,
    required String groupId,
    required String name,
    String? legacyCode,
    required List<CatalogUnit> units,
    required String primaryUnitId,
    Map<String, dynamic>? sourceMetadata,
  }) async {
    _requireCatalogManager(actor);
    final cleanBrandId = _required(brandId, 'Brand ID');
    final cleanGroupId = _required(groupId, 'Group ID');
    final cleanName = _required(name, 'Product name');
    final cleanPrimaryUnitId = _required(primaryUnitId, 'Primary unit ID');
    final cleanSourceMetadata = Map<String, dynamic>.from(
      sourceMetadata ?? const {},
    );
    _validateUnits(units, cleanPrimaryUnitId);
    _rejectProtectedPriceData(
      cleanSourceMetadata,
      brandId: cleanBrandId,
      creationGroupId: cleanGroupId,
    );

    final normalizedName = normalizeCatalogText(cleanName);
    final normalizedCode = normalizeLegacyCode(legacyCode);
    final nameKeyId = productUniqueKeyId(
      brandId: cleanBrandId,
      keyType: 'name',
      normalizedValue: normalizedName,
    );
    final codeKeyId = normalizedCode.isEmpty
        ? null
        : productUniqueKeyId(
            brandId: cleanBrandId,
            keyType: 'legacy_code',
            normalizedValue: normalizedCode,
          );
    final productRef = _products.doc();
    final brandRef = _firestore.collection('brands').doc(cleanBrandId);
    final groupRef = _groups.doc(cleanGroupId);
    final nameKeyRef = _uniqueKeys.doc(nameKeyId);
    final codeKeyRef = codeKeyId == null ? null : _uniqueKeys.doc(codeKeyId);
    final auditRef = _auditEvents.doc();

    await _firestore.runTransaction((transaction) async {
      final brand = await transaction.get(brandRef);
      final group = await transaction.get(groupRef);
      final nameKey = await transaction.get(nameKeyRef);
      final codeKey = codeKeyRef == null
          ? null
          : await transaction.get(codeKeyRef);
      if (!brand.exists) throw StateError('The selected brand does not exist.');
      _validateGroup(group.data(), cleanBrandId);
      _ensureUniqueAvailable(nameKey.data(), productRef.id);
      _ensureUniqueAvailable(codeKey?.data(), productRef.id);

      final productData = _newProductData(
        productId: productRef.id,
        brandId: cleanBrandId,
        groupId: cleanGroupId,
        name: cleanName,
        normalizedName: normalizedName,
        legacyCode: _optional(legacyCode),
        units: units,
        primaryUnitId: cleanPrimaryUnitId,
        nameKeyId: nameKeyId,
        codeKeyId: codeKeyId,
        sourceMetadata: cleanSourceMetadata,
        actor: actor,
        lastAuditEventId: auditRef.id,
      );
      transaction.set(productRef, productData);
      transaction.set(
        nameKeyRef,
        _uniqueKeyData(
          id: nameKeyId,
          brandId: cleanBrandId,
          keyType: 'name',
          normalizedValue: normalizedName,
          productId: productRef.id,
          actor: actor,
          isNew: !nameKey.exists,
        ),
        SetOptions(merge: true),
      );
      if (codeKeyId != null && codeKeyRef != null && codeKey != null) {
        transaction.set(
          codeKeyRef,
          _uniqueKeyData(
            id: codeKeyId,
            brandId: cleanBrandId,
            keyType: 'legacy_code',
            normalizedValue: normalizedCode,
            productId: productRef.id,
            actor: actor,
            isNew: !codeKey.exists,
          ),
          SetOptions(merge: true),
        );
      }
      transaction.set(
        auditRef,
        _auditData(
          id: auditRef.id,
          entityType: 'product',
          entityId: productRef.id,
          brandId: cleanBrandId,
          action: 'created',
          actor: actor,
          after: _productAuditSnapshot(productData),
        ),
      );
    });
    _invalidateBrandCache(cleanBrandId);
    return productRef.id;
  }

  Future<void> updateProduct({
    required CatalogActor actor,
    required String productId,
    required String groupId,
    required String name,
    String? legacyCode,
    required List<CatalogUnit> units,
    required String primaryUnitId,
    Map<String, dynamic>? sourceMetadata,
  }) async {
    _requireCatalogManager(actor);
    final cleanProductId = _required(productId, 'Product ID');
    final cleanGroupId = _required(groupId, 'Group ID');
    final cleanName = _required(name, 'Product name');
    final cleanPrimaryUnitId = _required(primaryUnitId, 'Primary unit ID');
    _validateUnits(units, cleanPrimaryUnitId);
    if (sourceMetadata != null) {
      _rejectProtectedPriceData(sourceMetadata);
    }
    final productRef = _products.doc(cleanProductId);
    final auditRef = _auditEvents.doc();

    String? affectedBrandId;
    await _firestore.runTransaction((transaction) async {
      final product = await transaction.get(productRef);
      final current = product.data();
      if (current == null) throw StateError('Product was not found.');
      if (current[ProductCatalogFields.active] == false) {
        throw StateError(
          'Archived products must be reactivated before editing.',
        );
      }
      final brandId = _required(
        current[ProductCatalogFields.brandId]?.toString() ?? '',
        'Product brand ID',
      );
      affectedBrandId = brandId;
      final currentSourceMetadata = Map<String, dynamic>.from(
        current[ProductCatalogFields.sourceMetadata] as Map? ?? const {},
      );
      if (sourceMetadata != null) {
        _rejectProtectedPriceData(sourceMetadata, brandId: brandId);
        if (!_sameFlatMap(sourceMetadata, currentSourceMetadata)) {
          throw StateError('Product source provenance cannot be rewritten.');
        }
      }
      final normalizedName = normalizeCatalogText(cleanName);
      final normalizedCode = normalizeLegacyCode(legacyCode);
      final nameKeyId = productUniqueKeyId(
        brandId: brandId,
        keyType: 'name',
        normalizedValue: normalizedName,
      );
      final codeKeyId = normalizedCode.isEmpty
          ? null
          : productUniqueKeyId(
              brandId: brandId,
              keyType: 'legacy_code',
              normalizedValue: normalizedCode,
            );
      final groupRef = _groups.doc(cleanGroupId);
      final nameKeyRef = _uniqueKeys.doc(nameKeyId);
      final codeKeyRef = codeKeyId == null ? null : _uniqueKeys.doc(codeKeyId);
      final group = await transaction.get(groupRef);
      final nameKey = await transaction.get(nameKeyRef);
      final codeKey = codeKeyRef == null
          ? null
          : await transaction.get(codeKeyRef);
      _validateGroup(group.data(), brandId);
      _ensureUniqueAvailable(nameKey.data(), cleanProductId);
      _ensureUniqueAvailable(codeKey?.data(), cleanProductId);

      final nextVersion =
          (current[ProductCatalogFields.version] as num?)?.toInt() ?? 1;
      final update = <String, dynamic>{
        ProductCatalogFields.groupId: cleanGroupId,
        ProductCatalogFields.name: cleanName,
        ProductCatalogFields.normalizedName: normalizedName,
        ProductCatalogFields.legacyCode:
            _optional(legacyCode) ?? FieldValue.delete(),
        ProductCatalogFields.units: units.map((unit) => unit.toMap()).toList(),
        ProductCatalogFields.primaryUnitId: cleanPrimaryUnitId,
        ProductCatalogFields.nameUniqueKeyId: nameKeyId,
        ProductCatalogFields.legacyCodeUniqueKeyId:
            codeKeyId ?? FieldValue.delete(),
        ProductCatalogFields.sourceMetadata: Map<String, dynamic>.from(
          currentSourceMetadata,
        ),
        ProductCatalogFields.version: nextVersion + 1,
        ProductCatalogFields.lastAuditEventId: auditRef.id,
        ProductCatalogFields.updatedBy: actor.uid,
        ProductCatalogFields.updatedByName: actor.name,
        ProductCatalogFields.updatedAt: FieldValue.serverTimestamp(),
      };
      transaction.update(productRef, update);
      transaction.set(
        nameKeyRef,
        _uniqueKeyData(
          id: nameKeyId,
          brandId: brandId,
          keyType: 'name',
          normalizedValue: normalizedName,
          productId: cleanProductId,
          actor: actor,
          isNew: !nameKey.exists,
        ),
        SetOptions(merge: true),
      );
      if (codeKeyId != null && codeKeyRef != null && codeKey != null) {
        transaction.set(
          codeKeyRef,
          _uniqueKeyData(
            id: codeKeyId,
            brandId: brandId,
            keyType: 'legacy_code',
            normalizedValue: normalizedCode,
            productId: cleanProductId,
            actor: actor,
            isNew: !codeKey.exists,
          ),
          SetOptions(merge: true),
        );
      }
      final after = <String, dynamic>{...current, ...update};
      transaction.set(
        auditRef,
        _auditData(
          id: auditRef.id,
          entityType: 'product',
          entityId: cleanProductId,
          brandId: brandId,
          action:
              current[ProductCatalogFields.groupId]?.toString() == cleanGroupId
              ? 'updated'
              : 'recategorized',
          actor: actor,
          before: _productAuditSnapshot(current),
          after: _productAuditSnapshot(after),
        ),
      );
    });
    if (affectedBrandId != null) _invalidateBrandCache(affectedBrandId!);
  }

  Future<void> archiveProduct({
    required CatalogActor actor,
    required String productId,
    required String reason,
  }) async {
    _requireCatalogManager(actor);
    final cleanReason = _required(reason, 'Archive reason');
    final productRef = _products.doc(_required(productId, 'Product ID'));
    final auditRef = _auditEvents.doc();
    String? affectedBrandId;
    await _firestore.runTransaction((transaction) async {
      final product = await transaction.get(productRef);
      final current = product.data();
      if (current == null) throw StateError('Product was not found.');
      affectedBrandId = current[ProductCatalogFields.brandId]?.toString();
      if (current[ProductCatalogFields.active] == false) {
        throw StateError('Product is already archived.');
      }
      final nextVersion =
          ((current[ProductCatalogFields.version] as num?)?.toInt() ?? 1) + 1;
      final after = <String, dynamic>{
        ...current,
        ProductCatalogFields.active: false,
        ProductCatalogFields.version: nextVersion,
        ProductCatalogFields.lastAuditEventId: auditRef.id,
      };
      transaction.update(productRef, {
        ProductCatalogFields.active: false,
        ProductCatalogFields.version: nextVersion,
        ProductCatalogFields.lastAuditEventId: auditRef.id,
        ProductCatalogFields.archivedBy: actor.uid,
        ProductCatalogFields.archivedByName: actor.name,
        ProductCatalogFields.archivedAt: FieldValue.serverTimestamp(),
        ProductCatalogFields.updatedBy: actor.uid,
        ProductCatalogFields.updatedByName: actor.name,
        ProductCatalogFields.updatedAt: FieldValue.serverTimestamp(),
      });
      transaction.set(
        auditRef,
        _auditData(
          id: auditRef.id,
          entityType: 'product',
          entityId: product.id,
          brandId: current[ProductCatalogFields.brandId]?.toString() ?? '',
          action: 'archived',
          actor: actor,
          before: _productAuditSnapshot(current),
          after: _productAuditSnapshot(after),
          reason: cleanReason,
        ),
      );
    });
    if (affectedBrandId != null) _invalidateBrandCache(affectedBrandId!);
  }

  Future<void> reactivateProduct({
    required CatalogActor actor,
    required String productId,
    required String reason,
  }) async {
    _requireCatalogManager(actor);
    final cleanReason = _required(reason, 'Reactivation reason');
    final productRef = _products.doc(_required(productId, 'Product ID'));
    final auditRef = _auditEvents.doc();
    String? affectedBrandId;
    await _firestore.runTransaction((transaction) async {
      final product = await transaction.get(productRef);
      final current = product.data();
      if (current == null) throw StateError('Product was not found.');
      affectedBrandId = current[ProductCatalogFields.brandId]?.toString();
      if (current[ProductCatalogFields.active] != false) {
        throw StateError('Product is already active.');
      }
      final nameKeyRef = _uniqueKeys.doc(
        _required(
          current[ProductCatalogFields.nameUniqueKeyId]?.toString() ?? '',
          'Product name unique key',
        ),
      );
      final codeKeyId = _optional(
        current[ProductCatalogFields.legacyCodeUniqueKeyId]?.toString(),
      );
      final codeKeyRef = codeKeyId == null ? null : _uniqueKeys.doc(codeKeyId);
      final nameKey = await transaction.get(nameKeyRef);
      final codeKey = codeKeyRef == null
          ? null
          : await transaction.get(codeKeyRef);
      _ensureUniqueAvailable(nameKey.data(), product.id);
      _ensureUniqueAvailable(codeKey?.data(), product.id);

      final nextVersion =
          ((current[ProductCatalogFields.version] as num?)?.toInt() ?? 1) + 1;
      final after = <String, dynamic>{
        ...current,
        ProductCatalogFields.active: true,
        ProductCatalogFields.version: nextVersion,
        ProductCatalogFields.lastAuditEventId: auditRef.id,
      };
      transaction.update(productRef, {
        ProductCatalogFields.active: true,
        ProductCatalogFields.version: nextVersion,
        ProductCatalogFields.lastAuditEventId: auditRef.id,
        ProductCatalogFields.archivedBy: FieldValue.delete(),
        ProductCatalogFields.archivedByName: FieldValue.delete(),
        ProductCatalogFields.archivedAt: FieldValue.delete(),
        ProductCatalogFields.updatedBy: actor.uid,
        ProductCatalogFields.updatedByName: actor.name,
        ProductCatalogFields.updatedAt: FieldValue.serverTimestamp(),
      });
      transaction.set(
        auditRef,
        _auditData(
          id: auditRef.id,
          entityType: 'product',
          entityId: product.id,
          brandId: current[ProductCatalogFields.brandId]?.toString() ?? '',
          action: 'reactivated',
          actor: actor,
          before: _productAuditSnapshot(current),
          after: _productAuditSnapshot(after),
          reason: cleanReason,
        ),
      );
    });
    if (affectedBrandId != null) _invalidateBrandCache(affectedBrandId!);
  }

  Future<void> upsertAccountingProfile({
    required CatalogActor actor,
    required String productId,
    String? accountingReference,
    required String syncState,
    String? notes,
  }) async {
    _requireCatalogManager(actor);
    final cleanProductId = _required(productId, 'Product ID');
    final cleanSyncState = _required(syncState, 'Synchronization state');
    const allowedStates = {'not_synced', 'pending', 'synced', 'sync_error'};
    if (!allowedStates.contains(cleanSyncState)) {
      throw ArgumentError('Unsupported synchronization state.');
    }
    final productRef = _products.doc(cleanProductId);
    final profileRef = _firestore
        .collection(ProductCatalogCollections.accountingProfiles)
        .doc(cleanProductId);
    final auditRef = _auditEvents.doc();
    await _firestore.runTransaction((transaction) async {
      final product = await transaction.get(productRef);
      final profile = await transaction.get(profileRef);
      final productData = product.data();
      if (productData == null) throw StateError('Product was not found.');
      final brandId =
          productData[ProductCatalogFields.brandId]?.toString() ?? '';
      final profileData = <String, dynamic>{
        'id': cleanProductId,
        'product_id': cleanProductId,
        'brand_id': brandId,
        'accounting_reference':
            _optional(accountingReference) ?? FieldValue.delete(),
        'sync_state': cleanSyncState,
        'last_audit_event_id': auditRef.id,
        'notes': _optional(notes) ?? FieldValue.delete(),
        if (!profile.exists) 'created_by': actor.uid,
        if (!profile.exists) 'created_at': FieldValue.serverTimestamp(),
        'updated_by': actor.uid,
        'updated_at': FieldValue.serverTimestamp(),
      };
      transaction.set(profileRef, profileData, SetOptions(merge: true));
      transaction.set(
        auditRef,
        _auditData(
          id: auditRef.id,
          entityType: 'product_accounting_profile',
          entityId: cleanProductId,
          brandId: brandId,
          action: profile.exists ? 'updated' : 'created',
          actor: actor,
          before: profile.data() ?? const {},
          after: {
            'id': cleanProductId,
            'product_id': cleanProductId,
            'brand_id': brandId,
            'accounting_reference': _optional(accountingReference),
            'sync_state': cleanSyncState,
            'notes': _optional(notes),
            'last_audit_event_id': auditRef.id,
          },
        ),
      );
    });
  }

  Map<String, dynamic> _newProductData({
    required String productId,
    required String brandId,
    required String groupId,
    required String name,
    required String normalizedName,
    required String? legacyCode,
    required List<CatalogUnit> units,
    required String primaryUnitId,
    required String nameKeyId,
    required String? codeKeyId,
    required Map<String, dynamic> sourceMetadata,
    required CatalogActor actor,
    required String lastAuditEventId,
  }) {
    return {
      ProductCatalogFields.id: productId,
      ProductCatalogFields.brandId: brandId,
      ProductCatalogFields.groupId: groupId,
      ProductCatalogFields.name: name,
      ProductCatalogFields.normalizedName: normalizedName,
      if (legacyCode != null) ProductCatalogFields.legacyCode: legacyCode,
      ProductCatalogFields.units: units.map((unit) => unit.toMap()).toList(),
      ProductCatalogFields.primaryUnitId: primaryUnitId,
      ProductCatalogFields.active: true,
      ProductCatalogFields.version: 1,
      ProductCatalogFields.nameUniqueKeyId: nameKeyId,
      if (codeKeyId != null)
        ProductCatalogFields.legacyCodeUniqueKeyId: codeKeyId,
      ProductCatalogFields.sourceMetadata: Map<String, dynamic>.from(
        sourceMetadata,
      ),
      ProductCatalogFields.lastAuditEventId: lastAuditEventId,
      ProductCatalogFields.createdBy: actor.uid,
      ProductCatalogFields.createdByName: actor.name,
      ProductCatalogFields.createdAt: FieldValue.serverTimestamp(),
      ProductCatalogFields.updatedBy: actor.uid,
      ProductCatalogFields.updatedByName: actor.name,
      ProductCatalogFields.updatedAt: FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> _uniqueKeyData({
    required String id,
    required String brandId,
    required String keyType,
    required String normalizedValue,
    required String productId,
    required CatalogActor actor,
    required bool isNew,
  }) {
    return {
      'id': id,
      'brand_id': brandId,
      'key_type': keyType,
      'normalized_value': normalizedValue,
      'product_id': productId,
      'active': true,
      if (isNew) 'created_by': actor.uid,
      if (isNew) 'created_at': FieldValue.serverTimestamp(),
      'updated_by': actor.uid,
      'updated_at': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> _auditData({
    required String id,
    required String entityType,
    required String entityId,
    required String brandId,
    required String action,
    required CatalogActor actor,
    Map<String, dynamic> before = const {},
    Map<String, dynamic> after = const {},
    String? reason,
  }) {
    return {
      'id': id,
      'entity_type': entityType,
      'entity_id': entityId,
      'brand_id': brandId,
      'action': action,
      if (before.isNotEmpty) 'before': before,
      if (after.isNotEmpty) 'after': after,
      if (reason != null) 'reason': reason,
      'actor_uid': actor.uid,
      'actor_name': actor.name,
      'actor_role': actor.role,
      'created_at': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> _productAuditSnapshot(Map<String, dynamic> data) {
    return {
      for (final field in const [
        ProductCatalogFields.id,
        ProductCatalogFields.brandId,
        ProductCatalogFields.groupId,
        ProductCatalogFields.name,
        ProductCatalogFields.normalizedName,
        ProductCatalogFields.legacyCode,
        ProductCatalogFields.units,
        ProductCatalogFields.primaryUnitId,
        ProductCatalogFields.active,
        ProductCatalogFields.version,
        ProductCatalogFields.nameUniqueKeyId,
        ProductCatalogFields.legacyCodeUniqueKeyId,
        ProductCatalogFields.lastAuditEventId,
      ])
        if (data[field] != null && data[field] is! FieldValue)
          field: data[field],
    };
  }

  Map<String, dynamic> _groupAuditSnapshot(Map<String, dynamic> data) {
    return {
      for (final field in const [
        ProductCatalogFields.id,
        ProductCatalogFields.brandId,
        ProductCatalogFields.name,
        ProductCatalogFields.normalizedName,
        ProductCatalogFields.legacyCode,
        ProductCatalogFields.active,
        ProductCatalogFields.lastAuditEventId,
        ProductCatalogFields.isSystemGroup,
        ProductCatalogFields.systemKey,
      ])
        if (data[field] != null && data[field] is! FieldValue)
          field: data[field],
    };
  }

  void _validateGroup(Map<String, dynamic>? data, String brandId) {
    if (data == null) {
      throw StateError('The selected product group was not found.');
    }
    if (data[ProductCatalogFields.brandId] != brandId) {
      throw StateError('The product group belongs to a different brand.');
    }
    if (data[ProductCatalogFields.active] == false) {
      throw StateError('The selected product group is archived.');
    }
  }

  void _ensureUniqueAvailable(Map<String, dynamic>? data, String productId) {
    if (data == null) return;
    if (data['product_id']?.toString() != productId) {
      throw StateError('A normalized duplicate product already exists.');
    }
  }

  void _validateUnits(List<CatalogUnit> units, String primaryUnitId) {
    if (units.isEmpty) throw ArgumentError('At least one unit is required.');
    if (units.length > maxCatalogUnits) {
      throw ArgumentError(
        'A product can have at most $maxCatalogUnits independent units.',
      );
    }
    final ids = <String>{};
    for (final unit in units) {
      final id = unit.id.trim();
      if (id.isEmpty ||
          unit.displayValue.trim().isEmpty ||
          unit.rawValue.trim().isEmpty) {
        throw ArgumentError(
          'Every unit requires an ID, display value, and raw value.',
        );
      }
      if (!ids.add(id)) throw ArgumentError('Unit IDs must be unique.');
    }
    if (!ids.contains(primaryUnitId)) {
      throw ArgumentError(
        'The primary unit ID must reference a supplied unit.',
      );
    }
  }

  void _rejectProtectedPriceData(
    Map<String, dynamic> sourceMetadata, {
    String? brandId,
    String? creationGroupId,
  }) {
    const allowedSourceFields = <String>{
      'source_profile',
      'source_file_sha256',
      'source_sheet',
      'source_row',
      'raw_material_value',
      'raw_group_value',
      'raw_primary_unit',
      'raw_unit_2',
      'raw_unit_3',
      'import_id',
      ProductSourceMetadataFields.originalGroupMissing,
      ProductSourceMetadataFields.fallbackSystemGroupAssigned,
      ProductSourceMetadataFields.fallbackSystemGroupKey,
      ProductSourceMetadataFields.fallbackSystemGroupId,
      ProductSourceMetadataFields.sourceFingerprint,
    };
    final unsupportedFields = sourceMetadata.keys.toSet().difference(
      allowedSourceFields,
    );
    if (unsupportedFields.isNotEmpty) {
      throw ArgumentError('Unsupported product source metadata field.');
    }
    for (final field in const [
      ProductSourceMetadataFields.originalGroupMissing,
      ProductSourceMetadataFields.fallbackSystemGroupAssigned,
    ]) {
      if (sourceMetadata.containsKey(field) && sourceMetadata[field] is! bool) {
        throw ArgumentError('$field must be a boolean.');
      }
    }
    for (final field in const [
      ProductSourceMetadataFields.fallbackSystemGroupKey,
      ProductSourceMetadataFields.fallbackSystemGroupId,
      ProductSourceMetadataFields.sourceFingerprint,
    ]) {
      if (sourceMetadata.containsKey(field) &&
          (sourceMetadata[field] is! String ||
              (sourceMetadata[field] as String).trim().isEmpty)) {
        throw ArgumentError('$field must be a non-empty string.');
      }
    }
    final originalGroupMissing =
        sourceMetadata[ProductSourceMetadataFields.originalGroupMissing] ==
        true;
    final fallbackAssigned =
        sourceMetadata[ProductSourceMetadataFields
            .fallbackSystemGroupAssigned] ==
        true;
    if (originalGroupMissing != fallbackAssigned) {
      throw ArgumentError(
        'Missing-group provenance and fallback assignment must agree.',
      );
    }
    if (fallbackAssigned) {
      if (sourceMetadata[ProductSourceMetadataFields.originalGroupMissing] !=
              true ||
          sourceMetadata[ProductSourceMetadataFields.fallbackSystemGroupKey] !=
              UncategorizedProductGroupContract.systemKey) {
        throw ArgumentError(
          'Uncategorized fallback metadata is internally inconsistent.',
        );
      }
      if (brandId != null &&
          sourceMetadata[ProductSourceMetadataFields.fallbackSystemGroupId] !=
              UncategorizedProductGroupContract.documentIdForBrand(brandId)) {
        throw ArgumentError(
          'Uncategorized fallback group does not match the product brand.',
        );
      }
      if (creationGroupId != null &&
          sourceMetadata[ProductSourceMetadataFields.fallbackSystemGroupId] !=
              creationGroupId) {
        throw ArgumentError(
          'A new missing-group product must use its Uncategorized group.',
        );
      }
    } else if (sourceMetadata.containsKey(
          ProductSourceMetadataFields.fallbackSystemGroupKey,
        ) ||
        sourceMetadata.containsKey(
          ProductSourceMetadataFields.fallbackSystemGroupId,
        )) {
      throw ArgumentError(
        'Fallback group identity requires fallback assignment to be true.',
      );
    }

    bool containsPrice(dynamic value) {
      if (value is Map) {
        for (final entry in value.entries) {
          final key = entry.key.toString().toLowerCase();
          if (key.contains('price') ||
              key.contains('cost') ||
              key.contains('\u0633\u0639\u0631')) {
            return true;
          }
          if (containsPrice(entry.value)) return true;
        }
      } else if (value is Iterable) {
        return value.any(containsPrice);
      }
      return false;
    }

    if (containsPrice(sourceMetadata)) {
      throw ArgumentError(
        'Protected price data cannot be stored in product documents.',
      );
    }
  }

  bool _sameFlatMap(Map<String, dynamic> left, Map<String, dynamic> right) {
    return left.length == right.length &&
        left.entries.every((entry) => right[entry.key] == entry.value);
  }

  void _requireCatalogManager(CatalogActor actor) {
    _requireValue(actor.uid, 'Actor UID');
    _requireValue(actor.name, 'Actor name');
    if (!actor.canManageCatalog) {
      throw StateError(
        'Only the General Manager or accountant can manage the product catalog.',
      );
    }
  }

  String _required(String value, String label) {
    _requireValue(value, label);
    return value.trim();
  }

  void _requireValue(String value, String label) {
    if (value.trim().isEmpty) throw ArgumentError('$label is required.');
  }

  String? _optional(String? value) {
    final clean = value?.trim();
    return clean == null || clean.isEmpty ? null : clean;
  }
}
