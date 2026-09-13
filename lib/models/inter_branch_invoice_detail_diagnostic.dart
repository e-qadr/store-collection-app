import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/models/inter_branch_invoice_model.dart';

/// Temporary, in-memory-only context shown after a public transfer-header
/// permission failure. This deliberately models an allow-listed set of public
/// identifiers; it has no field for tokens, credentials, prices, or errors
/// from the server beyond a stable error code.
class InterBranchInvoiceDetailDiagnostic {
  static const buildCommit = String.fromEnvironment(
    'TRANSFER_DETAIL_DIAGNOSTIC_BUILD_ID',
    defaultValue: 'e775a1c-diagnostic',
  );
  static const applicationId = 'com.storecollection.store_collection_app';
  static const applicationVersion = '1.0.0+4';

  final String firebaseUid;
  final String role;
  final String branchId;
  final String branchName;
  final String firebaseProjectId;
  final String invoiceId;
  final String? invoiceNumber;
  final String collectionPath;
  final String errorCode;
  final String participantClassification;
  final String? sendingBranchId;
  final String? receivingBranchId;
  final List<String> branchIds;

  const InterBranchInvoiceDetailDiagnostic({
    required this.firebaseUid,
    required this.role,
    required this.branchId,
    required this.branchName,
    required this.firebaseProjectId,
    required this.invoiceId,
    required this.invoiceNumber,
    required this.collectionPath,
    required this.errorCode,
    required this.participantClassification,
    required this.sendingBranchId,
    required this.receivingBranchId,
    required this.branchIds,
  });

  factory InterBranchInvoiceDetailDiagnostic.forPermissionFailure({
    required String? firebaseUid,
    required UserRole role,
    required String? branchId,
    required String branchName,
    required String firebaseProjectId,
    required String invoiceId,
    required String errorCode,
    InterBranchInvoiceRead? cachedInvoice,
  }) {
    final effectiveBranchId = branchId?.trim() ?? '';
    final cachedNumber = cachedInvoice?.invoiceNumber.trim() ?? '';
    return InterBranchInvoiceDetailDiagnostic(
      firebaseUid: firebaseUid?.trim().isNotEmpty == true
          ? firebaseUid!.trim()
          : 'غير متاح',
      role: role.name,
      branchId: effectiveBranchId.isEmpty ? 'غير متاح' : effectiveBranchId,
      branchName: branchName.trim().isEmpty ? 'غير متاح' : branchName.trim(),
      firebaseProjectId: firebaseProjectId.trim().isEmpty
          ? 'غير متاح'
          : firebaseProjectId.trim(),
      invoiceId: invoiceId,
      invoiceNumber: cachedNumber.isEmpty || cachedNumber == '-'
          ? null
          : cachedNumber,
      collectionPath: 'inter_branch_invoices/$invoiceId',
      errorCode: errorCode.trim().isEmpty ? 'unknown' : errorCode.trim(),
      participantClassification: _participantClassification(
        branchId: effectiveBranchId,
        invoice: cachedInvoice,
      ),
      sendingBranchId: _nonEmpty(cachedInvoice?.sendingBranchId),
      receivingBranchId: _nonEmpty(cachedInvoice?.receivingBranchId),
      branchIds: cachedInvoice?.branchIds ?? const <String>[],
    );
  }

  static String _participantClassification({
    required String branchId,
    required InterBranchInvoiceRead? invoice,
  }) {
    if (branchId.isEmpty || invoice == null) return 'UNKNOWN';
    if (invoice.sendingBranchId == branchId) return 'SOURCE_PARTICIPANT';
    if (invoice.receivingBranchId == branchId) return 'RECEIVING_PARTICIPANT';
    return 'UNRELATED';
  }

  static String? _nonEmpty(String? value) {
    final cleaned = value?.trim() ?? '';
    return cleaned.isEmpty ? null : cleaned;
  }

  /// The panel consumes this allow-listed map. Keeping presentation data here
  /// makes accidental addition of a token or protected field conspicuous in
  /// review and straightforward to test.
  Map<String, Object?> toSafeDisplayMap() => {
    'معرّف المستخدم': firebaseUid,
    'الدور': role,
    'معرّف الفرع الفعّال': branchId,
    'اسم الفرع': branchName,
    'مشروع Firebase': firebaseProjectId,
    'معرّف المستند': invoiceId,
    if (invoiceNumber != null) 'رقم الفاتورة': invoiceNumber,
    'المسار المقروء': collectionPath,
    'رمز الخطأ': errorCode,
    'إصدار التشخيص': buildCommit,
    'معرّف التطبيق': applicationId,
    'إصدار التطبيق': applicationVersion,
    'تصنيف المشاركة': participantClassification,
    if (sendingBranchId != null) 'فرع الإرسال': sendingBranchId,
    if (receivingBranchId != null) 'فرع الاستلام': receivingBranchId,
    if (branchIds.isNotEmpty) 'معرّفات الفروع': branchIds.join(', '),
  };
}
