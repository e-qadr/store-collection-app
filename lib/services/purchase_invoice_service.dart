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
    if (role == UserRole.manager) {
      final branch = branchId?.trim() ?? '';
      if (branch.isEmpty) return Stream.value(const []);
      query = _invoices.where('receiving_branch_id', isEqualTo: branch);
    } else if (role == UserRole.collector) {
      query = _invoices.where(
        'status',
        isEqualTo: PurchaseInvoiceStatus.pendingPriceEntry.value,
      );
    } else if (role == UserRole.accountant) {
      query = _invoices.where(
        'status',
        isEqualTo: PurchaseInvoiceStatus.pendingAccountingEntry.value,
      );
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
