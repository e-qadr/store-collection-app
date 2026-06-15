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

### الطريقة الموصى بها: متغير Base64 واحد

لتجنب مشاكل الأسطر الجديدة في المفتاح الخاص، حوّل ملف JSON الكامل إلى Base64
في PowerShell:

```powershell
[Convert]::ToBase64String(
  [IO.File]::ReadAllBytes("C:\path\to\service-account.json")
) | Set-Clipboard
```

ثم أضف في Hostinger متغيرًا واحدًا باسم:

```text
FIREBASE_SERVICE_ACCOUNT_BASE64
```

والصق القيمة من الحافظة. عند استخدام هذه الطريقة احذف:
`FIREBASE_PROJECT_ID` و`FIREBASE_CLIENT_EMAIL` و`FIREBASE_PRIVATE_KEY`.

## إعداد Hostinger Node.js Web App

1. ارفع محتويات مجلد `hostinger-push-server` أو اربطه بمستودع Git خاص.
2. عيّن أمر التشغيل إلى:

```text
npm start
```

3. أضف متغيرات البيئة الموجودة في `.env.example`.
   لا تضف متغير `PORT` في Hostinger، لأنه يعيّنه تلقائيًا.
4. انشر التطبيق، ثم افتح:

```text
https://YOUR-DOMAIN/health
```

يجب أن تظهر نتيجة تحتوي على `"status":"ok"`.
إذا ظهرت `"configuration_error"` فستحتوي النتيجة على سبب إعداد Firebase الخاطئ.
قيمة `"workerRunning":false` تعني أن العامل في وضع الانتظار وليست خطأ.

## الاختبار

1. ثبّت آخر نسخة من تطبيق Flutter، وسجّل الدخول واسمح بالإشعارات.
2. تأكد أن مستند المستخدم يحتوي `notification_tokens`.
3. أغلق التطبيق بالكامل.
4. أنشئ سندًا جديدًا من حساب محصل.
5. يجب أن يصل الإشعار إلى مدير الفرع المحدد فقط.

إذا ظهرت حالة `no_tokens` داخل مستند الإشعار، يجب على المستخدم المستلم فتح
آخر نسخة من التطبيق مرة واحدة، وتسجيل الدخول، والسماح بإشعارات النظام.

في Android، إيقاف التطبيق قسريًا من إعدادات النظام يمنع وصول FCM حتى يتم فتح
التطبيق مرة أخرى. إزالته من شاشة التطبيقات الأخيرة لا تمنع وصول الإشعارات.
