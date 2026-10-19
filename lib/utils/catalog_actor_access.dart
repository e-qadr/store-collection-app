import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:store_collection_app/models/product_catalog_model.dart';

/// A safe, user-facing reason for refusing a catalog write before it reaches
/// Firestore rules.  Keeping this aligned with `operationalUser()` prevents a
/// visible editor from offering an action the rules will always reject.
class CatalogActorAccessException implements Exception {
  final String message;

  const CatalogActorAccessException(this.message);

  @override
  String toString() => message;
}

CatalogActor catalogActorFromProfile({
  required String uid,
  required Map<String, dynamic>? profile,
}) {
  if (profile == null) {
    throw const CatalogActorAccessException(
      'تعذر التحقق من ملف المستخدم. سجّل الدخول مجدداً ثم حاول مرة أخرى.',
    );
  }

  final role = profile['role']?.toString() ?? '';
  if (profile['isActive'] == false) {
    throw const CatalogActorAccessException(
      'هذا الحساب غير نشط، لذلك لا يمكنه إدارة المواد.',
    );
  }
  if (profile['mustChangePassword'] == true) {
    throw const CatalogActorAccessException(
      'يجب تغيير كلمة المرور أولاً قبل إنشاء المواد أو تعديلها.',
    );
  }
  if (role != 'collector' && role != 'accountant') {
    throw const CatalogActorAccessException(
      'إدارة المواد متاحة للمدير العام والمحاسب فقط.',
    );
  }

  final storedName = profile['name']?.toString().trim() ?? '';
  return CatalogActor(
    uid: uid,
    name: storedName.isNotEmpty
        ? storedName
        : (role == 'collector' ? 'المدير العام' : 'المحاسب'),
    role: role,
    active: true,
  );
}

/// Loads the current profile from the server rather than a possibly stale
/// local cache. A catalog write is security-sensitive and would fail anyway
/// while offline, so failing here gives the user a useful reason first.
Future<CatalogActor> requireCurrentCatalogActor({
  FirebaseAuth? auth,
  FirebaseFirestore? firestore,
}) async {
  final currentUser = (auth ?? FirebaseAuth.instance).currentUser;
  if (currentUser == null) {
    throw const CatalogActorAccessException(
      'انتهت جلسة الدخول. سجّل الدخول مجدداً ثم حاول مرة أخرى.',
    );
  }

  final database = firestore ?? FirebaseFirestore.instance;
  final snapshot = await database
      .collection('users')
      .doc(currentUser.uid)
      .get(const GetOptions(source: Source.server));
  return catalogActorFromProfile(
    uid: currentUser.uid,
    profile: snapshot.data(),
  );
}
