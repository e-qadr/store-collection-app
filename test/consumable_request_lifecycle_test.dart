import 'package:flutter_test/flutter_test.dart';
import 'package:store_collection_app/models/consumable_request_model.dart';

void main() {
  test('consumable rejection is an explicit terminal audit state', () {
    expect(
      ConsumableRequestStatus.rejectedByCollector.label,
      'مرفوض من المدير العام',
    );
    expect(
      ConsumableRequestStatus.rejectedByAccountant.label,
      'مرفوض من المحاسب',
    );
    expect(ConsumableRequestStatus.rejectedByCollector.isFinal, isTrue);
    expect(ConsumableRequestStatus.rejectedByAccountant.isFinal, isTrue);
    expect(ConsumableRequestStatus.pendingCollectorReview.isFinal, isFalse);
  });

  test('unknown legacy values do not become an approved consumable state', () {
    expect(
      consumableRequestStatusFromString('unexpected-state'),
      ConsumableRequestStatus.pendingCollectorReview,
    );
  });
}
