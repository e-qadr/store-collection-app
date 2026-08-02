import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:store_collection_app/services/auth_api_service.dart';
import 'package:store_collection_app/services/auth_service.dart';
import 'package:store_collection_app/theme/app_theme.dart';
import 'package:store_collection_app/utils/password_policy.dart';
import 'package:store_collection_app/widgets/password_strength_indicator.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmationController = TextEditingController();
  final _authService = AuthService();
  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirmation = false;
  bool _submitting = false;
  bool _sendingVerification = false;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await _authService.reauthenticate(_currentController.text);
      await _authService.changePassword(_newController.text);
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تغيير كلمة المرور. سجل الدخول مرة أخرى.'),
          backgroundColor: AppTheme.successColor,
        ),
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      final message = switch (error.code) {
        'wrong-password' ||
        'invalid-credential' => 'كلمة المرور الحالية غير صحيحة',
        'too-many-requests' => 'محاولات كثيرة. انتظر قليلاً ثم حاول مرة أخرى.',
        'network-request-failed' => 'تعذر الاتصال بالشبكة.',
        _ => 'تعذر التحقق من كلمة المرور الحالية.',
      };
      _showError(message);
    } on AuthApiException catch (error) {
      if (mounted) _showError(error.message);
    } catch (_) {
      if (mounted) _showError('تعذر تغيير كلمة المرور. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.errorColor),
    );
  }

  Future<void> _sendEmailVerification() async {
    if (_sendingVerification) return;
    setState(() => _sendingVerification = true);
    try {
      await FirebaseAuth.instance.setLanguageCode('ar');
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إرسال رسالة التحقق. افحص بريدك الإلكتروني.'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      _showError(
        error.code == 'too-many-requests'
            ? 'تم إرسال محاولات كثيرة. انتظر قليلاً ثم حاول مجدداً.'
            : 'تعذر إرسال رسالة التحقق حالياً.',
      );
    } finally {
      if (mounted) setState(() => _sendingVerification = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    final email = firebaseUser?.email ?? '';
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(title: const Text('إعدادات الحساب')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.person_outline_rounded),
                        ),
                        title: const Text('البريد الإلكتروني'),
                        subtitle: Text(
                          email,
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ),
                    if (firebaseUser?.emailVerified == false) ...[
                      const SizedBox(height: 12),
                      Card(
                        color: AppTheme.warningColor.withValues(alpha: 0.08),
                        child: ListTile(
                          leading: const Icon(
                            Icons.mark_email_unread_outlined,
                            color: AppTheme.warningColor,
                          ),
                          title: const Text('البريد الإلكتروني غير موثق'),
                          subtitle: const Text(
                            'وثّق بريدك لتسهيل استعادة الحساب بأمان.',
                          ),
                          trailing: TextButton(
                            onPressed: _sendingVerification
                                ? null
                                : _sendEmailVerification,
                            child: Text(
                              _sendingVerification
                                  ? 'جاري الإرسال...'
                                  : 'إرسال',
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'تغيير كلمة المرور',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'سنطلب كلمة المرور الحالية لإعادة التحقق من هويتك.',
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 20),
                              _passwordField(
                                controller: _currentController,
                                label: 'كلمة المرور الحالية',
                                visible: _showCurrent,
                                onToggle: () => setState(
                                  () => _showCurrent = !_showCurrent,
                                ),
                                validator: (value) => (value ?? '').isEmpty
                                    ? 'أدخل كلمة المرور الحالية'
                                    : null,
                              ),
                              const SizedBox(height: 14),
                              _passwordField(
                                controller: _newController,
                                label: 'كلمة المرور الجديدة',
                                visible: _showNew,
                                onChanged: (_) => setState(() {}),
                                onToggle: () =>
                                    setState(() => _showNew = !_showNew),
                                validator: (value) {
                                  final messages =
                                      PasswordPolicy.validationMessages(
                                        value ?? '',
                                      );
                                  return messages.isEmpty
                                      ? null
                                      : messages.first;
                                },
                              ),
                              const SizedBox(height: 10),
                              PasswordStrengthIndicator(
                                password: _newController.text,
                              ),
                              const SizedBox(height: 16),
                              _passwordField(
                                controller: _confirmationController,
                                label: 'تأكيد كلمة المرور الجديدة',
                                visible: _showConfirmation,
                                onToggle: () => setState(
                                  () => _showConfirmation = !_showConfirmation,
                                ),
                                validator: (value) =>
                                    value == _newController.text
                                    ? null
                                    : 'كلمتا المرور غير متطابقتين',
                              ),
                              const SizedBox(height: 22),
                              ElevatedButton.icon(
                                onPressed: _submitting ? null : _changePassword,
                                icon: _submitting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.password_rounded),
                                label: Text(
                                  _submitting
                                      ? 'جاري تغيير كلمة المرور...'
                                      : 'تغيير كلمة المرور',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required bool visible,
    required VoidCallback onToggle,
    required String? Function(String?) validator,
    ValueChanged<String>? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: !visible,
      textDirection: TextDirection.ltr,
      enableSuggestions: false,
      autocorrect: false,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          onPressed: onToggle,
          icon: Icon(
            visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          ),
        ),
      ),
      validator: validator,
    );
  }
}
