# نشر إشعارات Firebase

تستخدم الدالة `sendTransactionNotification` حدث إنشاء مستند داخل مجموعة
`notifications` في Firestore، ثم ترسل إشعار FCM إلى الأجهزة المسجلة للمستخدم
المستهدف. تعمل الإشعارات على Android حتى عندما يكون التطبيق مغلقًا.

## المتطلبات

1. افتح مشروع Firebase باسم `store-collection-app`.
2. فعّل خطة Blaze من صفحة الفوترة. خدمة FCM مجانية، وتملك Cloud Functions حصة
   مجانية شهرية، لكن Firebase يتطلب ربط حساب فوترة لنشر الدوال.
3. سجّل الدخول إلى Firebase CLI.

## أوامر النشر على هذا الجهاز

```powershell
$env:PATH="D:\store-collection-node-tools\node-v22.20.0-win-x64;$env:PATH"
$firebase="$env:LOCALAPPDATA\firebase-tools-cli\firebase.cmd"

& $firebase login
& $firebase use store-collection-app
& $firebase deploy --only functions
```

## اختبار Android

1. ثبّت آخر نسخة من التطبيق وسجّل الدخول.
2. اسمح بإشعارات النظام عند ظهور الطلب.
3. تأكد أن مستند المستخدم في Firestore يحتوي على `notification_tokens`.
4. أغلق التطبيق بالكامل.
5. أنشئ سندًا جديدًا من حساب محصل، وتأكد أن مدير الفرع الصحيح يستلم الإشعار.

## إعداد iPhone

يلزم إضافة تطبيق iOS في Firebase، وتنزيل `GoogleService-Info.plist` إلى
`ios/Runner`، ثم رفع مفتاح APNs من إعدادات Cloud Messaging في Firebase.
