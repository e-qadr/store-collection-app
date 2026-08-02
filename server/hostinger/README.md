# رفع فواتير المصروفات على Hostinger

هذا المجلد يحتوي سكربت PHP بسيط يستقبل ملفات الفواتير من التطبيق ويحفظها على الاستضافة.

## الخطوات

1. انسخ `upload_invoice.config.example.php` إلى `upload_invoice.config.php`.
2. ضع التوكن الطويل والسري في ملف الإعداد المحلي، مثل:

   ```php
   return ['upload_token' => 'ضع_رمزًا_طويلًا_وعشوائيًا_هنا'];
   ```

   ملف `upload_invoice.config.php` مستثنى من Git. ويمكن بدلًا منه ضبط متغير البيئة
   `INVOICE_UPLOAD_TOKEN` على الخادم.

3. ارفع `upload_invoice.php` وملف الإعداد المحلي إلى الاستضافة، مثل:

   ```text
   public_html/api/upload_invoice.php
   public_html/api/upload_invoice.config.php
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
- لا تضع التوكن الحقيقي داخل مستودع عام أو أرشيف عام.
- لا ترفع `upload_invoice.config.php` إلى Git.
