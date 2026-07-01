import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
// تأكد من مسار الاستيراد الصحيح لنموذج المستخدم
import 'package:store_collection_app/models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // دالة تسجيل الدخول
  Future<UserModel?> loginUser({
    required String email,
    required String password,
  }) async {
    try {
      // 1. تسجيل الدخول عبر Firebase Auth
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      User? firebaseUser = userCredential.user;

      if (firebaseUser != null) {
        // 2. جلب بيانات الموظف من Firestore بناءً على الـ uid
        DocumentSnapshot doc = await _firestore
            .collection('users')
            .doc(firebaseUser.uid)
            .get();

        if (doc.exists) {
          // 3. تحويل البيانات القادمة إلى UserModel الذي برمجناه سابقاً
          return UserModel.fromJson(doc.data() as Map<String, dynamic>);
        } else {
          debugPrint("لا توجد بيانات لهذا المستخدم في قاعدة البيانات");
          return null;
        }
      }
    } on FirebaseAuthException catch (e) {
      // التعامل مع أخطاء تسجيل الدخول (مثل كلمة مرور خاطئة)
      if (e.code == 'user-not-found') {
        debugPrint('لم يتم العثور على حساب بهذا البريد الإلكتروني.');
      } else if (e.code == 'wrong-password') {
        debugPrint('كلمة المرور غير صحيحة.');
      } else {
        debugPrint('حدث خطأ: ${e.message}');
      }
      return null;
    } catch (e) {
      debugPrint('حدث خطأ غير متوقع: $e');
      return null;
    }
    return null;
  }

  // دالة تسجيل الخروج
  Future<void> logout() async {
    await _auth.signOut();
  }

  // الاستماع لحالة المستخدم (هل هو مسجل دخول أم لا)
  Stream<User?> get authStateChanges => _auth.authStateChanges();
}
