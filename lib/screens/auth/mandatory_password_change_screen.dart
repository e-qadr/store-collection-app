import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:store_collection_app/services/auth_api_service.dart';
import 'package:store_collection_app/services/auth_service.dart';
import 'package:store_collection_app/theme/app_theme.dart';
import 'package:store_collection_app/utils/password_policy.dart';
import 'package:store_collection_app/widgets/password_strength_indicator.dart';

class MandatoryPasswordChangeScreen extends StatefulWidget {
  final bool credentialExpired;
  final bool claimRequired;
  final bool emailSetupPending;
  final AuthService? authService;

  const MandatoryPasswordChangeScreen({
    super.key,
    this.credentialExpired = false,
    this.claimRequired = false,
    this.emailSetupPending = false,
    this.authService,
  });

  @override
  State<MandatoryPasswordChangeScreen> createState() =>
      _MandatoryPasswordChangeScreenState();
}

class _MandatoryPasswordChangeScreenState
    extends State<MandatoryPasswordChangeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  late final AuthService _authService;
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;
  bool _submitting = false;
  bool _claiming = false;
  String? _claimError;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? AuthService();
    if (widget.claimRequired && !widget.credentialExpired) {
      _claimTemporaryCredential();
    } else if (widget.emailSetupPending && !widget.credentialExpired) {
      _completeEmailSetup();
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting ||
        _claiming ||
        _claimError != null ||
        !_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _submitting = true);
    try {
      await _authService.changePassword(_passwordController.text);
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حفظ كلمة المرور. سجل الدخول باستخدامها للمتابعة.'),
          backgroundColor: AppTheme.successColor,
        ),
      );
    } on AuthApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر تغيير كلمة المرور. حاول مرة أخرى.'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _claimTemporaryCredential() async {
    if (_claiming) return;
    setState(() {
      _claiming = true;
      _claimError = null;
    });
    try {
      await _authService.claimTemporaryCredential();
    } on AuthApiException catch (error) {
      if (mounted) setState(() => _claimError = error.message);
    } catch (_) {
      if (mounted) {
        setState(() {
          _claimError = 'تعذر تأمين جلسة الإعداد. تحقق من الشبكة وحاول مجدداً.';
        });
      }
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  Future<void> _completeEmailSetup() async {
    if (_claiming) return;
    setState(() {
      _claiming = true;
      _claimError = null;
    });
    try {
      await _authService.completeEmailSetup();
    } on AuthApiException catch (error) {
      if (mounted) setState(() => _claimError = error.message);
    } catch (_) {
      if (mounted) {
        setState(() {
          _claimError =
              'تعذر تأكيد إعداد كلمة المرور. حاول تسجيل الدخول مجدداً.';
        });
      }
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(
          title: const Text('إعداد كلمة المرور'),
          automaticallyImplyLeading: false,
          actions: [
            TextButton(
              onPressed: _submitting ? null : _authService.logout,
              child: const Text(
                'تسجيل الخروج',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: widget.credentialExpired
                        ? _expiredContent()
                        : widget.emailSetupPending
                        ? _emailSetupContent()
                        : _passwordForm(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _expiredContent() {
    return Column(
      children: [
        const Icon(
          Icons.timer_off_outlined,
          size: 58,
          color: AppTheme.warningColor,
        ),
        const SizedBox(height: 16),
        const Text(
          'انتهت صلاحية بيانات الدخول المؤقتة',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        const Text(
          'اطلب من مسؤول النظام إعادة تعيين كلمة المرور. لن تتمكن من الوصول إلى بقية التطبيق بهذه البيانات.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 22),
        OutlinedButton.icon(
          onPressed: _authService.logout,
          icon: const Icon(Icons.logout_rounded),
          label: const Text('العودة إلى تسجيل الدخول'),
        ),
      ],
    );
  }

  Widget _passwordForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.password_rounded,
            size: 58,
            color: AppTheme.managerColor,
          ),
          const SizedBox(height: 16),
          const Text(
            'أنشئ كلمة مرور شخصية',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'يجب إكمال هذه الخطوة قبل الوصول إلى التطبيق.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 24),
          if (_claiming) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            const Text(
              'جاري تأمين بيانات الدخول المؤقتة للاستخدام مرة واحدة...',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
          ],
          if (_claimError != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.errorColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Text(
                    _claimError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.errorColor),
                  ),
                  TextButton.icon(
                    onPressed: _claimTemporaryCredential,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          TextFormField(
            enabled: !_claiming && _claimError == null,
            controller: _passwordController,
            obscureText: _obscurePassword,
            textDirection: TextDirection.ltr,
            enableSuggestions: false,
            autocorrect: false,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'كلمة المرور الجديدة',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
            validator: (value) {
              final messages = PasswordPolicy.validationMessages(value ?? '');
              return messages.isEmpty ? null : messages.first;
            },
          ),
          const SizedBox(height: 12),
          PasswordStrengthIndicator(password: _passwordController.text),
          const SizedBox(height: 18),
          TextFormField(
            enabled: !_claiming && _claimError == null,
            controller: _confirmationController,
            obscureText: _obscureConfirmation,
            textDirection: TextDirection.ltr,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'تأكيد كلمة المرور',
              prefixIcon: const Icon(Icons.lock_reset_outlined),
              suffixIcon: IconButton(
                onPressed: () => setState(
                  () => _obscureConfirmation = !_obscureConfirmation,
                ),
                icon: Icon(
                  _obscureConfirmation
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
            validator: (value) => value == _passwordController.text
                ? null
                : 'كلمتا المرور غير متطابقتين',
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _submitting || _claiming || _claimError != null
                ? null
                : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle_outline),
            label: Text(_submitting ? 'جاري الحفظ...' : 'حفظ والمتابعة'),
          ),
        ],
      ),
    );
  }

  Widget _emailSetupContent() {
    return Column(
      children: [
        Icon(
          _claimError == null
              ? Icons.mark_email_read_outlined
              : Icons.error_outline_rounded,
          size: 58,
          color: _claimError == null
              ? AppTheme.successColor
              : AppTheme.errorColor,
        ),
        const SizedBox(height: 16),
        Text(
          _claimError == null
              ? 'جاري تأكيد إعداد كلمة المرور...'
              : _claimError!,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 14),
        if (_claiming) const LinearProgressIndicator(),
        if (_claimError != null)
          TextButton.icon(
            onPressed: _completeEmailSetup,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('إعادة المحاولة'),
          ),
      ],
    );
  }
}
