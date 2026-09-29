import 'package:flutter_test/flutter_test.dart';
import 'package:store_collection_app/models/branch_request_model.dart';

void main() {
  test(
    'branch request labels map stable stored values to Arabic UI labels',
    () {
      expect(BranchRequestCategory.maintenance.label, 'صيانة');
      expect(BranchRequestPriority.urgent.label, 'عاجل');
      expect(BranchRequestStatus.inProgress.label, 'قيد التنفيذ');
      expect(BranchRequestStatus.rejected.label, 'مرفوض');
      expect(
        BranchRequestDirection.administrationToBranch.label,
        'مهمة من الإدارة للفرع',
      );
      expect(
        BranchRequestDirection.administrationToAdministration.label,
        'مهمة إدارية داخلية',
      );
      expect(
        branchRequestStatusFromString('completed'),
        BranchRequestStatus.completed,
      );
    },
  );

  test('branch request workflow only permits the active task sequence', () {
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
