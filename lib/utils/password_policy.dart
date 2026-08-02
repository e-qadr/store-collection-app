enum PasswordStrength { weak, fair, strong }

class PasswordPolicy {
  const PasswordPolicy._();

  static const int minimumLength = 12;

  static List<String> validationMessages(String password) {
    final messages = <String>[];
    if (password.length < minimumLength) {
      messages.add('يجب أن تتكون كلمة المرور من 12 حرفاً على الأقل');
    }
    if (!RegExp(r'[a-z]').hasMatch(password)) {
      messages.add('أضف حرفاً إنجليزياً صغيراً واحداً على الأقل');
    }
    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      messages.add('أضف حرفاً إنجليزياً كبيراً واحداً على الأقل');
    }
    if (!RegExp(r'\d').hasMatch(password)) {
      messages.add('أضف رقماً واحداً على الأقل');
    }
    if (!RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
      messages.add('أضف رمزاً خاصاً واحداً على الأقل');
    }
    if (password.length > 128) {
      messages.add('يجب ألا تتجاوز كلمة المرور 128 حرفاً');
    }
    return messages;
  }

  static bool isValid(String password) => validationMessages(password).isEmpty;

  static PasswordStrength strength(String password) {
    if (password.isEmpty || password.length < 8) return PasswordStrength.weak;
    var score = 0;
    if (password.length >= minimumLength) score++;
    if (password.length >= 16) score++;
    if (RegExp(r'[a-z]').hasMatch(password) &&
        RegExp(r'[A-Z]').hasMatch(password)) {
      score++;
    }
    if (RegExp(r'\d').hasMatch(password)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) score++;
    if (score >= 5) return PasswordStrength.strong;
    if (score >= 3) return PasswordStrength.fair;
    return PasswordStrength.weak;
  }
}
