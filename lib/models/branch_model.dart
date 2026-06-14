class BranchModel {
  final String id;
  final String name;
  final String companyName;
  final String branchCode;
  final String branchManagerId;

  BranchModel({
    required this.id,
    required this.name,
    required this.companyName,
    required this.branchCode,
    required this.branchManagerId,
  });

  factory BranchModel.fromJson(Map<String, dynamic> json) {
    return BranchModel(
      id: json['id'],
      name: json['name'],
      companyName: json['company_name'] ?? 'بدون شركة',
      branchCode: json['branch_code'] ?? '',
      branchManagerId: json['branch_manager_id'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'company_name': companyName,
      'branch_code': branchCode,
      'branch_manager_id': branchManagerId,
    };
  }
}
