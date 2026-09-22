// أدوار المستخدمين
enum UserRole {
  admin, // تمت إضافة دور مسؤول النظام
  collector,
  manager,
  accountant,
}

// حالة السند المالي
enum TransactionStatus {
  reservedForCollection,
  collectionDifferencePendingReview,
  reservedCancelled,
  pending,
  approvedByCollector,
  approvedByManager,
  approvedByAccountant,
  reviewRequestedByAccountant,
  reviewRequestedByManager,
  editRequestedByCollector,
  rejectedByManager,
}
