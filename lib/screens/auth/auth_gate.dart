import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:store_collection_app/models/user_model.dart';
import 'package:store_collection_app/models/enums.dart';

import 'package:store_collection_app/screens/auth/login_screen.dart';
import 'package:store_collection_app/screens/auth/mandatory_password_change_screen.dart';
import 'package:store_collection_app/screens/dashboards/admin_dashboard.dart';
import 'package:store_collection_app/screens/systems/system_selection_screen.dart';
import 'package:store_collection_app/utils/logout_confirmation.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData && snapshot.data != null) {
          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(snapshot.data!.uid)
                .snapshots(),
            builder: (context, roleSnapshot) {
              if (roleSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              if (roleSnapshot.hasData && roleSnapshot.data!.exists) {
                UserModel user = UserModel.fromJson(
                  roleSnapshot.data!.data() as Map<String, dynamic>,
                );

                if (!user.isActive) {
                  return const _UnavailableAccountScreen();
                }

                if (!user.hasKnownRole) {
                  return const _UnknownRoleScreen();
                }

                if (user.mustChangePassword) {
                  return MandatoryPasswordChangeScreen(
                    credentialExpired: user.temporaryCredentialExpired,
                    claimRequired: user.passwordState == 'temporary',
                    emailSetupPending: user.passwordState == 'email_setup_sent',
                  );
                }

                switch (user.role) {
                  case UserRole.admin:
                    return const AdminDashboard();
                  case UserRole.collector:
                    return const SystemSelectionScreen(
                      role: UserRole.collector,
                      branchName: 'اختيار النظام',
                    );
                  case UserRole.accountant:
                    return const SystemSelectionScreen(
                      role: UserRole.accountant,
                      branchName: 'اختيار النظام',
                    );
                  case UserRole.manager:
                    if (user.branchId == null || user.branchId!.isEmpty) {
                      return Scaffold(
                        appBar: AppBar(title: const Text('تنبيه')),
                        body: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                'حسابك كمدير غير مربوط بأي فرع حالياً. تواصل مع الإدارة.',
                              ),
                              const SizedBox(height: 20),
                              ElevatedButton(
                                onPressed: () => confirmAndSignOut(context),
                                child: const Text('تسجيل الخروج'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance
                          .collection('branches')
                          .doc(user.branchId)
                          .get(),
                      builder: (context, branchSnap) {
                        if (branchSnap.connectionState ==
                            ConnectionState.waiting) {
                          return const Scaffold(
                            body: Center(child: CircularProgressIndicator()),
                          );
                        }

                        String branchName = 'الفرع غير معروف';
                        if (branchSnap.hasData && branchSnap.data!.exists) {
                          branchName = branchSnap.data!.get('name');
                        }
                        return SystemSelectionScreen(
                          role: UserRole.manager,
                          branchId: user.branchId!,
                          branchName: branchName,
                        );
                      },
                    );
                }
              }

              return Scaffold(
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('لا توجد بيانات لهذا المستخدم أو تم حذفها.'),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: () => confirmAndSignOut(context),
                        child: const Text('تسجيل الخروج'),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        }

        return const LoginScreen();
      },
    );
  }
}

class _UnavailableAccountScreen extends StatelessWidget {
  const _UnavailableAccountScreen();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.block_rounded, size: 58, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'هذا الحساب موقوف حالياً',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'تواصل مع مسؤول النظام إذا كنت تعتقد أن هذا غير صحيح.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: () => confirmAndSignOut(context),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('تسجيل الخروج'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UnknownRoleScreen extends StatelessWidget {
  const _UnknownRoleScreen();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.security_rounded,
                  size: 58,
                  color: Colors.orange,
                ),
                const SizedBox(height: 16),
                const Text(
                  'تعذر التحقق من صلاحية هذا الحساب',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'دور المستخدم غير معروف. تواصل مع مسؤول النظام لتصحيح بيانات الحساب.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: () => confirmAndSignOut(context),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('تسجيل الخروج'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
