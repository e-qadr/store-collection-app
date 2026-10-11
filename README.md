# إدارة الأصالة

تطبيق Flutter واحد لأندرويد والويب. نسخة الويب منشورة على:

`https://app-alasalh.web.app`

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## النشر التلقائي للويب

كل دفع إلى الفرع `main` يغيّر ملفات التطبيق أو إعدادات الويب يبني نسخة الويب
وينشرها تلقائياً إلى Firebase Hosting عبر GitHub Actions. يستخدم مسار النشر
مصادقة OIDC قصيرة العمر ولا يحتفظ بمفتاح حساب خدمة أو رمز Firebase داخل المستودع.

## النطاق الرسمي

النطاق المقترح هو `app.alasalh.com` لأنه يوضح أنه واجهة التطبيق ويترك النطاقات
الأخرى للخدمات وواجهة الـ API. تمت إضافته إلى Firebase Authentication كنطاق
مسموح. لإتمام تفعيله في DNS لدى Hostinger، أضف السجل التالي ثم انتظر التحقق:

| النوع | الاسم | القيمة |
| --- | --- | --- |
| `CNAME` | `app` | `app-alasalh.web.app` |

ولكي يعمل خادم Node API من المتصفح، أضف في إعدادات بيئة الاستضافة:

```env
ALLOWED_ORIGINS=https://app.alasalh.com,https://app-alasalh.web.app
```

## الجلسات والطباعة

على الويب يحفظ Firebase Auth الجلسة محلياً في المتصفح نفسه، لذلك لا يحتاج
المستخدم لتسجيل الدخول عند فتح التطبيق من الجهاز والمتصفح نفسيهما، إلى أن يسجل
خروجاً أو يمسح بيانات الموقع. لا يخزن التطبيق كلمات المرور في ملفات تعريف
ارتباط مخصّصة.

تعمل الطباعة في الويب عبر مربع طباعة المتصفح الأصلي من شاشات الفواتير والتقارير.

## أندرويد

مصدر التطبيق مشترك، لذا أي تعديل في الوظائف يصل إلى بناء الويب تلقائياً. أما
التطبيق المثبّت على هواتف أندرويد فلا يستطيع التحديث الذاتي بصمت وفق قيود
أندرويد؛ يلزم نشر APK موقّع أو إصدار عبر Google Play أو Firebase App
Distribution ليصل التحديث للمستخدمين.
