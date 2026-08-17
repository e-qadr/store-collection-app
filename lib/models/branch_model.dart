class BranchModel {
  final String id;
  final String name;
  final String companyName;
  final String brandId;
  final String branchCode;
  final String? branchManagerId;

  BranchModel({
    required this.id,
    required this.name,
    required this.companyName,
    this.brandId = '',
    required this.branchCode,
    this.branchManagerId,
  });

  factory BranchModel.fromJson(Map<String, dynamic> json) {
    return BranchModel(
      id: json['id'],
      name: json['name'],
      companyName: json['company_name'] ?? 'بدون شركة',
      brandId: json['brand_id'] ?? '',
      branchCode: json['branch_code'] ?? '',
      branchManagerId: json['branch_manager_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'company_name': companyName,
      'brand_id': brandId,
      'branch_code': branchCode,
      'branch_manager_id': branchManagerId,
    };
  }
}
