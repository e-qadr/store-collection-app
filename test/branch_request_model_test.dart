import 'package:flutter_test/flutter_test.dart';
import 'package:store_collection_app/models/branch_request_model.dart';

void main() {
  test(
    'branch request labels map stable stored values to Arabic UI labels',
    () {
      expect(BranchRequestCategory.maintenance.label, 'صيانة');
      expect(BranchRequestPriority.urgent.label, 'عاجل');
      expect(BranchRequestStatus.inProgress.label, 'قيد التنفيذ');
      expect(
        branchRequestStatusFromString('completed'),
        BranchRequestStatus.completed,
      );
    },
  );

  test('branch request workflow only permits the General Manager sequence', () {
    expect(
      BranchRequestWorkflow.canTransition(
        BranchRequestStatus.newRequest,
        BranchRequestStatus.inProgress,
      ),
      isTrue,
    );
    expect(
      BranchRequestWorkflow.canTransition(
        BranchRequestStatus.inProgress,
        BranchRequestStatus.completed,
      ),
      isTrue,
    );
    expect(
      BranchRequestWorkflow.canTransition(
        BranchRequestStatus.newRequest,
        BranchRequestStatus.completed,
      ),
      isFalse,
    );
    expect(
      BranchRequestWorkflow.canTransition(
        BranchRequestStatus.completed,
        BranchRequestStatus.newRequest,
      ),
      isFalse,
    );
  });
}
