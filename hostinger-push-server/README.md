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

## واجهة إدارة الحسابات وكلمات المرور

الخادم نفسه يستضيف الآن المسارات الآمنة تحت `/v1`. كل عمليات إنشاء المستخدمين
وتغيير أدوارهم وحالتهم وإعادة تعيين كلمات مرورهم تتحقق من Firebase ID token ثم
من دور `admin` وحالة الحساب في Firestore. لا ترسل تطبيق Flutter أي بيانات Firebase
Admin سرية.

أضف `FIREBASE_WEB_API_KEY` من إعدادات تطبيق Firebase إلى متغيرات البيئة. يستخدمه
الخادم فقط لاستدعاء سير عمل البريد الرسمي لـ Firebase Authentication. لا تحتاج
هذه الطريقة إلى مزود بريد مدفوع مستقل. خصص قالب **Password reset** ولغة المرسل
من Firebase Console > Authentication > Templates. إذا أضفت
`PASSWORD_RESET_CONTINUE_URL` فيجب أن يكون نطاقه ضمن Authorized domains.
يُرسل الخادم ترويسة اللغة العربية افتراضياً ويمكن تغييرها عبر
`FIREBASE_EMAIL_LOCALE`.

لا يتطلب إرسال قالب Firebase الافتراضي مزود بريد خارجي. وفق حدود Firebase
الحالية، خطة Spark تسمح بـ 150 رسالة إعادة تعيين يومياً، وخطة Blaze بـ 10,000
رسالة يومياً؛ لذلك راقب الحصة إذا كان عدد الدعوات أو الاستعادات كبيراً.

ابنِ تطبيق Flutter مع رابط هذا الخادم (من دون الشرطة المائلة الأخيرة):

```bash
flutter build apk \
  --dart-define=AUTH_API_BASE_URL=https://YOUR-AUTH-SERVER.example.com
```

لنسخة الويب، أضف نطاق الواجهة إلى `ALLOWED_ORIGINS`. حدود المحاولات محفوظة في
ذاكرة عملية Node، لذلك عند تشغيل أكثر من نسخة من الخادم استخدم محدد معدل مشتركاً
مثل Redis أو حماية Hostinger/Cloudflare على المسارات `/v1/auth/*` و`/v1/admin/*`.

انشر قواعد Firestore الموجودة في جذر المشروع بعد مراجعتها مع أي قواعد منشورة
حالياً:

```bash
firebase deploy --only firestore:rules --project store-collection-app
```

القواعد تمنع العميل من تعديل حقول الدور والحالة وكلمة المرور، وتمنع الحساب الذي
يجب عليه تغيير كلمة مروره من الوصول إلى بيانات العمل. Firebase Admin يتجاوز هذه
القواعد بعد تحقق الخادم من هوية المسؤول.
