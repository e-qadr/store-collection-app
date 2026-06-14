# نشر خادم الإشعارات على Hostinger

هذا الخادم يرسل إشعارات Firebase Cloud Messaging المجانية إلى مستخدمي التطبيق
حتى عندما يكون التطبيق مغلقًا. لا يحتاج إلى خطة Firebase Blaze.

## هل خطة Hostinger مناسبة؟

في hPanel افتح `Websites` ثم `Add website`. إذا ظهر خيار `Node.js Web App`
فيمكن استخدام هذه الخدمة مباشرة. وفق وثائق Hostinger يتوفر ذلك في خطط Node.js
Web App وخطط Business أو أعلى. يمكن أيضًا تشغيلها على Hostinger VPS.

## إنشاء بيانات Firebase السرية

1. افتح Firebase Console ثم إعدادات المشروع.
2. افتح `Service accounts`.
3. اختر `Generate new private key`.
4. افتح ملف JSON الناتج، واستخدم القيم التالية كمتغيرات بيئة في Hostinger:
   - `project_id` ← `FIREBASE_PROJECT_ID`
   - `client_email` ← `FIREBASE_CLIENT_EMAIL`
   - `private_key` ← `FIREBASE_PRIVATE_KEY`
5. لا ترفع ملف JSON إلى Git أو ملفات الموقع العامة.

## إعداد Hostinger Node.js Web App

1. ارفع محتويات مجلد `hostinger-push-server` أو اربطه بمستودع Git خاص.
2. عيّن أمر التشغيل إلى:

```text
npm start
```

3. أضف متغيرات البيئة الموجودة في `.env.example`.
4. انشر التطبيق، ثم افتح:

```text
https://YOUR-DOMAIN/health
```

يجب أن تظهر نتيجة تحتوي على `"status":"ok"`.

## الاختبار

1. ثبّت آخر نسخة من تطبيق Flutter، وسجّل الدخول واسمح بالإشعارات.
2. تأكد أن مستند المستخدم يحتوي `notification_tokens`.
3. أغلق التطبيق بالكامل.
4. أنشئ سندًا جديدًا من حساب محصل.
5. يجب أن يصل الإشعار إلى مدير الفرع المحدد فقط.
