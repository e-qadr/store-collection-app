# رفع فواتير المصروفات على Hostinger

هذا المجلد يحتوي سكربت PHP بسيط يستقبل ملفات الفواتير من التطبيق ويحفظها على الاستضافة.

## الخطوات

1. افتح `upload_invoice.php`.
2. غيّر قيمة `UPLOAD_TOKEN` إلى نص طويل وسري، مثل:

   ```php
   const UPLOAD_TOKEN = 'ضع_رمز_طويل_وسري_هنا';
   ```

3. ارفع الملف إلى الاستضافة، مثلاً:

   ```text
   public_html/api/upload_invoice.php
   ```

4. تأكد أن مجلد `api` قابل للكتابة، أو أن PHP يستطيع إنشاء مجلد:

   ```text
   public_html/api/uploads/
   ```

5. شغّل التطبيق أو ابنِه مع نفس الرابط والتوكن:

   ```bash
   flutter run \
     --dart-define=INVOICE_UPLOAD_URL=https://example.com/api/upload_invoice.php \
     --dart-define=INVOICE_UPLOAD_TOKEN=ضع_نفس_الرمز_السري_هنا
   ```

   وعند البناء:

   ```bash
   flutter build apk \
     --dart-define=INVOICE_UPLOAD_URL=https://example.com/api/upload_invoice.php \
     --dart-define=INVOICE_UPLOAD_TOKEN=ضع_نفس_الرمز_السري_هنا
   ```

## ملاحظات

- الملفات المسموحة حالياً: `pdf`, `jpg`, `jpeg`, `png`.
- الحد الأقصى الافتراضي: `10 MB`.
- التطبيق سيحفظ رابط الملف الراجع من الاستضافة داخل Firestore.
- لا تضع التوكن الحقيقي داخل مستودع عام.
