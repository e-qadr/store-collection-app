import 'package:flutter_test/flutter_test.dart';
import 'package:store_collection_app/utils/manager_assignment.dart';

void main() {
  test('only active manager records are eligible for branch assignment', () {
    expect(
      isActiveManagerForAssignment({'role': 'manager', 'isActive': true}),
      isTrue,
    );
    expect(isActiveManagerForAssignment({'role': 'manager'}), isTrue);
    expect(
      isActiveManagerForAssignment({'role': 'manager', 'isActive': false}),
      isFalse,
    );
    expect(
      isActiveManagerForAssignment({'role': 'collector', 'isActive': true}),
      isFalse,
    );
  });
}
