import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:store_collection_app/services/catalog_product_command_service.dart';
import 'package:store_collection_app/utils/catalog_actor_access.dart';

/// Maps only safe, actionable catalog persistence failures. Server messages
/// are deliberately not shown because they can expose backend implementation
/// details.
String? catalogOperationErrorText(Object error) {
  if (error is CatalogActorAccessException) return error.message;
  if (error is CatalogProductCommandException) return error.message;
  if (error is! FirebaseException) return null;

  return switch (error.code) {
    'resource-exhausted' =>
      'تعذر الحفظ مؤقتاً بسبب ضغط على قاعدة البيانات. لم يتم حفظ المادة أو أي تغيير؛ انتظر قليلاً ثم حاول مرة واحدة.',
    'permission-denied' =>
      'رفضت قاعدة البيانات العملية. تحقق من حالة الحساب، ثم حدّث التطبيق إذا استمرت المشكلة لأن إعدادات قاعدة البيانات قد تحتاج إلى تحديث.',
    'unavailable' =>
      'خدمة قاعدة البيانات غير متاحة مؤقتاً. تحقق من الاتصال ثم حاول مرة واحدة.',
    'aborted' => 'تعارض في إصدار المادة. حدّث القائمة ثم حاول مرة أخرى.',
    'deadline-exceeded' =>
      'استغرقت قاعدة البيانات وقتاً أطول من المتوقع. لم يتم حفظ التغيير؛ تحقق من الاتصال ثم حاول مرة واحدة.',
    'failed-precondition' =>
      'بيانات المادة الحالية لا تتوافق مع متطلبات قاعدة البيانات. حدّث القائمة ثم حاول مرة أخرى.',
    'invalid-argument' => 'بيانات المادة غير مكتملة أو غير صالحة.',
    _ => null,
  };
}
