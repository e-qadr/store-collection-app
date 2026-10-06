import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/models/purchase_invoice_model.dart';
import 'package:store_collection_app/models/purchase_invoice_price_model.dart';

class PurchaseInvoiceService {
  final FirebaseFirestore _firestore;

  PurchaseInvoiceService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _invoices =>
      _firestore.collection(PurchaseInvoiceCollections.invoices);

  Stream<List<PurchaseInvoiceRead>> watchDashboard({
    required UserRole role,
    String? branchId,
  }) {
    Query<Map<String, dynamic>> query;
    PurchaseInvoiceStatus? actionStatus;
    if (role == UserRole.manager) {
      final branch = branchId?.trim() ?? '';
      if (branch.isEmpty) return Stream.value(const []);
      query = _invoices.where('receiving_branch_id', isEqualTo: branch);
    } else if (role == UserRole.collector) {
      actionStatus = PurchaseInvoiceStatus.pendingPriceEntry;
      query = (branchId?.trim().isNotEmpty ?? false)
          ? _invoices.where('receiving_branch_id', isEqualTo: branchId!.trim())
          : _invoices.where('status', isEqualTo: actionStatus.value);
    } else if (role == UserRole.accountant) {
      actionStatus = PurchaseInvoiceStatus.pendingAccountingEntry;
      query = (branchId?.trim().isNotEmpty ?? false)
          ? _invoices.where('receiving_branch_id', isEqualTo: branchId!.trim())
          : _invoices.where('status', isEqualTo: actionStatus.value);
    } else {
      return Stream.value(const []);
    }
    return query
        .orderBy('last_updated', descending: true)
        .limit(100)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => PurchaseInvoiceRead(id: doc.id, data: doc.data()))
              .where(
                (invoice) =>
                    // A pending controlled amendment freezes pricing and
                    // accounting actions.  Keep it out of those task queues
                    // until every recorded participant decides the edit.
                    !invoice.hasPendingAmendment &&
                    (actionStatus == null || invoice.status == actionStatus),
              )
              .toList(growable: false),
        );
  }

  Stream<PurchaseInvoiceRead?> watchInvoice(String invoiceId) {
    return _invoices.doc(invoiceId).snapshots().map((snapshot) {
      final data = snapshot.data();
      return data == null
          ? null
          : PurchaseInvoiceRead(id: snapshot.id, data: data);
    });
  }

  /// Resolves the public number for a protected-price source. Price memory
  /// stores document IDs for referential integrity, but UI text must show the
  /// readable purchase number instead of exposing an internal ID.
  Future<String?> fetchPurchaseNumber(String invoiceId) async {
    final cleanId = invoiceId.trim();
    if (cleanId.isEmpty) return null;
    final snapshot = await _invoices.doc(cleanId).get();
    final number = snapshot.data()?['purchase_number']?.toString().trim();
    return number == null || number.isEmpty ? null : number;
  }

  /// The history page intentionally uses one bounded, live header query. It
  /// does not fetch items or protected prices until a user opens one invoice.
  Stream<List<PurchaseInvoiceRead>> watchHistory({
    required UserRole role,
    String? branchId,
  }) {
    Query<Map<String, dynamic>> query = _invoices;
    final cleanBranch = branchId?.trim() ?? '';
    if (role == UserRole.manager) {
      if (cleanBranch.isEmpty) return Stream.value(const []);
      query = query.where('receiving_branch_id', isEqualTo: cleanBranch);
    } else if (role != UserRole.collector &&
        role != UserRole.accountant &&
        role != UserRole.admin) {
      return Stream.value(const []);
    } else if (cleanBranch.isNotEmpty) {
      // The selector intentionally scopes the management dashboards to one
      // receiving branch; history must retain the same scope as the dashboard.
      query = query.where('receiving_branch_id', isEqualTo: cleanBranch);
    }
    return query
        .orderBy('last_updated', descending: true)
        .limit(100)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => PurchaseInvoiceRead(id: doc.id, data: doc.data()))
              .toList(growable: false),
        );
  }

  Future<PurchaseInvoiceRead> loadInvoiceWithItems(String invoiceId) async {
    final invoiceSnapshot = await _invoices.doc(invoiceId).get();
    final data = invoiceSnapshot.data();
    if (data == null) throw StateError('فاتورة المشتريات غير موجودة.');
    final itemSnapshot = await _invoices
        .doc(invoiceId)
        .collection(PurchaseInvoiceCollections.items)
        .orderBy('line_number')
        .get();
    return PurchaseInvoiceRead(
      id: invoiceId,
      data: data,
      itemDocuments: itemSnapshot.docs.map((doc) => doc.data()).toList(),
    );
  }

  Stream<List<Map<String, dynamic>>> watchEvents(
    String invoiceId,
    String receivingBranchId,
  ) {
    return _firestore
        .collection(PurchaseInvoiceCollections.events)
        .where('invoice_id', isEqualTo: invoiceId)
        .where('receiving_branch_id', isEqualTo: receivingBranchId)
        .orderBy('created_at', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => {'id': doc.id, ...doc.data()})
              .toList(growable: false),
        );
  }

  Stream<PurchaseInvoiceAmendment?> watchAmendment(String amendmentId) {
    if (amendmentId.trim().isEmpty) return Stream.value(null);
    return _firestore
        .collection(PurchaseInvoiceCollections.amendments)
        .doc(amendmentId.trim())
        .snapshots()
        .map((snapshot) {
          final data = snapshot.data();
          return data == null
              ? null
              : PurchaseInvoiceAmendment.fromMap(snapshot.id, data);
        });
  }

  Stream<List<PurchaseInvoiceAmendmentItem>> watchAmendmentItems(
    String amendmentId,
  ) {
    if (amendmentId.trim().isEmpty) return Stream.value(const []);
    return _firestore
        .collection(PurchaseInvoiceCollections.amendments)
        .doc(amendmentId.trim())
        .collection(PurchaseInvoiceCollections.amendmentItems)
        .orderBy('line_number')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(
                (document) => PurchaseInvoiceAmendmentItem.fromMap(
                  document.id,
                  document.data(),
                ),
              )
              .toList(growable: false),
        );
  }

  Stream<PurchaseInvoiceAmendmentPrice?> watchProtectedAmendmentPrices(
    String amendmentId,
  ) {
    if (amendmentId.trim().isEmpty) return Stream.value(null);
    return _firestore
        .collection(PurchaseInvoiceCollections.amendmentPrices)
        .doc(amendmentId.trim())
        .snapshots()
        .map((snapshot) {
          final data = snapshot.data();
          return data == null
              ? null
              : PurchaseInvoiceAmendmentPrice.fromMap(data);
        });
  }

  Stream<PurchaseInvoicePriceSnapshot?> watchProtectedPrices(String invoiceId) {
    return _firestore
        .collection(PurchaseInvoiceCollections.prices)
        .doc(invoiceId)
        .snapshots()
        .map((snapshot) {
          final data = snapshot.data();
          return data == null
              ? null
              : PurchaseInvoicePriceSnapshot.fromMap(data);
        });
  }

  Stream<List<ProductReviewTask>> watchReviewQueue({String? status}) {
    Query<Map<String, dynamic>> query = _firestore.collection(
      PurchaseInvoiceCollections.reviewTasks,
    );
    final cleanStatus = status?.trim() ?? '';
    if (cleanStatus.isNotEmpty) {
      query = query.where('status', isEqualTo: cleanStatus);
    }
    return query
        .orderBy('updated_at', descending: true)
        .limit(100)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => ProductReviewTask.fromMap(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  Future<List<ProductReviewTask>> loadInvoiceReviewTasks(
    String invoiceId,
  ) async {
    final snapshot = await _firestore
        .collection(PurchaseInvoiceCollections.reviewTasks)
        .where('invoice_id', isEqualTo: invoiceId)
        .get();
    return snapshot.docs
        .map((doc) => ProductReviewTask.fromMap(doc.id, doc.data()))
        .toList(growable: false);
  }
}
