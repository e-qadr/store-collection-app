const archiveRequiredRoles = <String>{'collector', 'manager', 'accountant'};

Map<String, dynamic> archiveApprovalsOf(Map<String, dynamic> transactionData) {
  final rawApprovals = transactionData['archive_approvals'];
  if (rawApprovals is! Map) return <String, dynamic>{};
  return Map<String, dynamic>.from(rawApprovals);
}

bool hasArchiveApproval(Map<String, dynamic> transactionData, String? role) {
  if (role == null || !archiveRequiredRoles.contains(role)) return false;
  return archiveApprovalsOf(transactionData)[role] is Map;
}

int archiveApprovalCount(Map<String, dynamic> transactionData) {
  return archiveRequiredRoles
      .where((role) => hasArchiveApproval(transactionData, role))
      .length;
}

bool areArchiveApprovalsComplete(Map<String, dynamic> transactionData) {
  return archiveApprovalCount(transactionData) == archiveRequiredRoles.length;
}
