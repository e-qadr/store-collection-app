import 'package:flutter_test/flutter_test.dart';
import 'package:store_collection_app/models/branch_model.dart';

void main() {
  test('يحفظ نموذج الفرع اسم الشركة والرمز الفريد', () {
    final branch = BranchModel(
      id: 'branch-1',
      name: 'فرع الرياض',
      companyName: 'شركة المتجر',
      brandId: 'brand-1',
      branchCode: 'AM',
      branchManagerId: 'manager-1',
    );

    expect(branch.toJson(), {
      'id': 'branch-1',
      'name': 'فرع الرياض',
      'company_name': 'شركة المتجر',
      'brand_id': 'brand-1',
      'branch_code': 'AM',
      'branch_manager_id': 'manager-1',
    });
  });
}
