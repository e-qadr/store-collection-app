/// A brand's Main Branch is a transfer-only receiving destination.
///
/// It is deliberately not an operational branch for purchases, expenses,
/// consumption, dashboards, or user/manager assignment.
bool isTransferOnlyMainBranch(Map<String, dynamic> branch) =>
    branch['branch_type']?.toString().trim() == 'main';

bool isActiveOperationalBranch(Map<String, dynamic> branch) =>
    !isTransferOnlyMainBranch(branch) &&
    branch['active'] != false &&
    branch['isActive'] != false &&
    branch['is_active'] != false;

bool canAssignUserToBranch(Map<String, dynamic> branch) =>
    !isTransferOnlyMainBranch(branch);
