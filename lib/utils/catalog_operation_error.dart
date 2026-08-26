import 'package:cloud_firestore/cloud_firestore.dart';

/// Maps only safe, actionable catalog persistence failures. Server messages
/// are deliberately not shown because they can expose backend implementation
/// details.
String? catalogOperationErrorText(Object error) {
  if (error is! FirebaseException) return null;

  return switch (error.code) {
    'resource-exhausted' =>
      'خدمة قاعدة البيانات مشغولة أو تجاوزت الحد المتاح مؤقتاً. لم يتم حفظ المادة؛ انتظر ثم حاول مرة واحدة.',
    'permission-denied' => 'لا تملك صلاحية إدارة المواد.',
    'unavailable' =>
      'خدمة قاعدة البيانات غير متاحة مؤقتاً. تحقق من الاتصال ثم حاول مرة واحدة.',
    'aborted' => 'تعارض في إصدار المادة. حدّث القائمة ثم حاول مرة أخرى.',
    'invalid-argument' => 'بيانات المادة غير مكتملة أو غير صالحة.',
    _ => null,
  };
}
