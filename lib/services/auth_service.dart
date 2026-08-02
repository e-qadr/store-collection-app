import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:store_collection_app/services/auth_api_service.dart';
// تأكد من مسار الاستيراد الصحيح لنموذج المستخدم
import 'package:store_collection_app/models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthApiService _authApiService;

  AuthService({AuthApiService? authApiService})
    : _authApiService = authApiService ?? AuthApiService();

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
          await _auth.signOut();
          return null;
        }
      }
    } on FirebaseAuthException {
      return null;
    } catch (e) {
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

  Future<void> sendForgotPasswordEmail(String email) =>
      _authApiService.sendForgotPasswordEmail(email.trim().toLowerCase());

  Future<void> reauthenticate(String currentPassword) async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null) {
      throw const AuthApiException(
        'unauthenticated',
        'انتهت جلسة الدخول. سجل الدخول مجدداً.',
      );
    }
    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: email, password: currentPassword),
    );
  }

  Future<void> changePassword(String newPassword) =>
      _authApiService.changePassword(newPassword);

  Future<void> claimTemporaryCredential() async {
    final customToken = await _authApiService.claimTemporaryCredential();
    await _auth.signInWithCustomToken(customToken);
  }

  Future<void> completeEmailSetup() => _authApiService.completeEmailSetup();
}
