// أدوار المستخدمين
enum UserRole {
  admin, // تمت إضافة دور مسؤول النظام
  collector,
  manager,
  accountant,
}

// حالة السند المالي
enum TransactionStatus {
  pending,
  approvedByCollector,
  approvedByManager,
  approvedByAccountant,
  reviewRequestedByAccountant,
  reviewRequestedByManager,
  editRequestedByCollector,
  rejectedByManager,
}
