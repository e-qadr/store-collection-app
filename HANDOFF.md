# ملف تسليم المشروع — إدارة الأصالة

> مرجع كامل لنقل العمل إلى Cloud Code أو إلى مطور جديد. اقرأه قبل أي تعديل أو
> نشر أو تغيير Firebase أو Hostinger.
>
> آخر تحديث: **2026-10-18**
> الفرع المعتمد: main
> آخر مراجعة منشورة: d2d2fe72dca22d7948fa5cc47279071ad6fe1197
> المستودع: https://github.com/e-qadr/store-collection-app.git

---

## 1. تعريف المشروع

**إدارة الأصالة** تطبيق أعمال عربي RTL مبني بـ Flutter، يعمل على Android والويب.
يدير الفروع والعلامات والكتالوج والتحصيل وفواتير المشتريات والمناقلات بين
الفروع والمصروفات النقدية والمستهلكات وطلبات الفروع، مع صلاحيات وإشعارات وسجل
تدقيق.

المشروع ليس نظام مخزون: المناقلات والمشتريات توثيق واعتماد وترحيل محاسبي؛ لا
يوجد رصيد كميات تشغيلي يجب احتسابه.

### مبادئ عمل لا تكسر

1. مديرو الفروع لا يرون السعر أو الإجماليات أو مراجع الأسعار المحمية.
2. بعد تدخل طرف آخر في سند أو فاتورة، لا يطبق تعديل البيانات قبل موافقة
   المشاركين الفعليين في ذلك السند فقط.
3. أوامر الفواتير الحديثة تمر عبر خادم Node الذري؛ إخفاء زر Flutter ليس حماية.
4. لا تضع أسرارًا أو مفاتيح أو service-account أو keystore أو توكنات في Git أو
   سجل أو اختبار أو هذا الملف.
5. الأدوار غير المعروفة تفشل بشكل آمن في Flutter والخادم وقواعد Firestore.

---

## 2. الحالة المنشورة الآن

| بند | القيمة |
| --- | --- |
| موقع الويب | https://app-alasalh.web.app |
| رقم مراجعة نشر الويب | https://app-alasalh.web.app/deployment.json |
| API Hostinger | https://collection-api.alasalh.com |
| Manifest تحديث Android | https://updates-alasalh.web.app/android.json |
| إصدار Android الحالي | **1.0.17+25** |
| نوع التحديث الحالي | **اختياري**، mandatory: false |
| APK الحالي | https://github.com/e-qadr/store-collection-app/releases/download/v1.0.17%2B25/store-collection-app-v1.0.17%2B25.apk |
| SHA-256 الحالي | ce737f676c72e189d3261c157f9365e42a3e9701b453fc0efa124ed9244e368e |
| وسم بناء Android | android-v1.0.17+25 |

آخر تغيير منشور يعرض للمشاركين في **مناقلة الفروع** طلب التعديل قبل القرار:
المواد قبل التعديل وبعده، سبب الطلب، مقدم الطلب، الملاحظات، وعدد وأسماء
الموافقين.

### حالة مساحة العمل المحلية

هذا الملف يتغير محليًا الآن حتى يقرر شخص مخول إدخاله في commit. لا تحذف ولا
تضمن تلقائيًا العناصر التالية، فهي محلية وخارج الإصدار:

- output/
- tmp/
- tools/
- ملاحظات مراجعة قاعدة البيانات.docx

---

## 3. البنية التقنية

    Flutter (Android + Web)
      ├─ Firebase Authentication: الهوية والجلسة
      ├─ Cloud Firestore: البيانات العامة والقراءات
      ├─ Firebase Messaging: الإشعارات
      ├─ Firebase Hosting: الويب وManifest التحديث
      └─ Hostinger Node API: الأوامر الحساسة الذرية وإدارة الحسابات وFCM

    GitHub Actions
      ├─ push إلى main → بناء ونشر الويب
      └─ Android tag/workflow → APK موقّع + GitHub Release + android.json

- Flutter المستخدم في CI: 3.44.2، وDart SDK: ^3.9.2.
- Firebase project: store-collection-app.
- Android package: com.storecollection.store_collection_app.
- خادم Hostinger: Node 20.x، Express 5، Firebase Admin 13، Firestore 7.

### خريطة الملفات

| المسار | الغرض |
| --- | --- |
| lib/main.dart | إقلاع Flutter وFirebase والجلسة وبوابة التحديث. |
| lib/models/ | نماذج المستخدمين والفواتير والكتالوج والسندات. |
| lib/services/ | Firestore وNode API والطباعة والإشعارات والتحديث. |
| lib/screens/ | شاشات كل نظام. |
| lib/utils/ | السياسات والتحويلات وتصفية الصلاحيات. |
| lib/widgets/ | واجهات مشتركة، اختيار الفرع، الطباعة، التحديث. |
| hostinger-push-server/ | خادم Node المنشور. |
| server/hostinger/ | PHP مستقل لرفع مرفقات المصروفات. |
| firestore.rules | حماية Firestore للعميل. |
| firestore.indexes.json | الفهارس المركبة. |
| firestore_rules_tests/ | اختبارات Emulator للقواعد. |
| test/ | اختبارات Flutter. |
| .github/workflows/ | النشر الآلي للويب وAndroid. |

---

## 4. التشغيل المحلي والاختبارات

### المتطلبات

- Flutter قريب من 3.44.2 وAndroid SDK/JDK عند بناء Android.
- Node 20.x.
- Firebase CLI لاختبارات المحاكي أو عند وجود تفويض نشر صريح فقط.

### أوامر آمنة

    # من جذر المشروع
    flutter pub get
    flutter analyze
    flutter test

    # خادم Node
    Push-Location hostinger-push-server
    npm ci
    npm run check
    npm test
    Pop-Location

    # قواعد Firestore على Emulator المحلي فقط
    Push-Location firestore_rules_tests
    npm ci
    npm test
    Pop-Location

### التشغيل

    flutter run --dart-define=AUTH_API_BASE_URL=https://collection-api.alasalh.com
    flutter run -d chrome --dart-define=AUTH_API_BASE_URL=https://collection-api.alasalh.com

لا تحفظ قيمًا سرية في الأوامر أو launch settings المتتبعة.

---

## 5. الأدوار والأمان

القيم المخزنة معرفة في lib/models/enums.dart:

| الدور | التسمية العملية | المسؤوليات |
| --- | --- | --- |
| admin | مسؤول النظام | المستخدمون والفروع والعلامات والتعيينات. |
| collector | المدير العام | إنشاء المشتريات واعتماد أسعارها والمراقبة. |
| manager | مدير الفرع | الاستلام والعمليات الخاصة بفرعه. |
| accountant | المحاسب | الكتالوج والمراجعات والترحيل المحاسبي. |

### قواعد الأمن الأساسية

- الخادم يعيد التحقق من Firebase ID token والدور والفرع وحالة الحساب وتغيير كلمة
  المرور الإلزامي، ولا يثق في payload العميل.
- Firebase Admin يتجاوز قواعد Firestore؛ لهذا تحقق الخادم شرط أساسي.
- لا تضع حقول سعر أو تكلفة أو إجمالي أو عملة محمية في header أو item أو event أو
  notification أو log أو PDF لمدير الفرع.
- لا تغير role المخزن لتغيير النص الظاهر في الواجهة.

---

## 6. الأنظمة ومسارات الأعمال

### 6.1 الحسابات والجلسات والإشعارات

- Firebase Auth مسؤول عن الهوية.
- الويب يستخدم Persistence.LOCAL، فتُحفظ الجلسة في المتصفح والجهاز نفسيهما حتى
  تسجيل الخروج أو مسح بيانات الموقع؛ لا توجد cookie مخصصة لكلمة المرور.
- إدارة المستخدمين واستعادة وتغيير كلمة المرور تمر عبر Node.
- FCM يصدر من Hostinger للمستخدمين المعنيين فقط.

الملفات المهمة: lib/screens/auth/، lib/services/auth_service.dart،
lib/services/auth_api_service.dart، lib/services/device_notification_service.dart،
hostinger-push-server/password-management.js.

### 6.2 الكتالوج

- المواد والمجموعات مرتبطة بالعلامة التجارية.
- الوحدات وتحويلاتها ديناميكية؛ لا تفترض حدًا لعدد الوحدات.
- البحث في المواد والمجموعات فوري، وإنشاء مجموعة يجب أن ينعكس في القائمة نفسها.
- السعر الحالي والتاريخ محفوظان في مجموعات محمية منفصلة.

    brands/{brandId}
    branches/{branchId}
    users/{uid}
    product_groups/{groupId}
    products/{productId}
    product_unique_keys/{keyId}
    products/{productId}/audit_events/{eventId}
    product_accounting_profiles/{productId}
    product_price_latest/{priceKey}       # محمي
    product_price_history/{eventId}       # محمي

### 6.3 نظام التحصيل والسندات

المجموعة الأساسية: transactions/{transactionId}.

قاعدة التعديل المتفق عليها:

1. إن كان المدير العام أنشأ السند ولم يوافق عليه أي طرف آخر، يعدله مباشرة.
2. بعد موافقة مدير الفرع، يلزم المنشئ ومدير الفرع في أي تعديل.
3. بعد موافقة المحاسب، يلزم المنشئ ومدير الفرع والمحاسب.
4. طالب التعديل يسجل موافقته ضمنيًا؛ لا تتغير البيانات إلا بعد اكتمال الجميع.
5. الرفض يسجل السبب ويعيد السند إلى مساره السابق ويرسل إشعارًا للمعنيين.

منطق حماية تعديل التحصيل موجود في firestore.rules بدوال collectionAmendment.

### 6.4 فواتير المشتريات

    المدير العام ينشئ فاتورة شراء
    → مدير الفرع المستلم يؤكد الاستلام والكميات
    → المدير العام يؤكد السعر المحمي
    → المحاسب يرحل محاسبيًا

- الفرع النشط عند فتح الإنشاء هو الافتراضي ويمكن تغييره.
- المدير العام والمحاسب يريان الأسعار والإجمالي؛ مدير الفرع لا يراهما.
- فرق كمية الاستلام يتحول إلى تعديل ولا يغير الفاتورة تلقائيًا.
- تعديل الشراء يدعم العملة والأسعار والمواد: إضافة وإزالة واستبدال وكمية، ويعرض
  before/after قبل القرار.
- الموافقون يستنتجون من المتدخلين الفعليين في الفاتورة، لا من كل أصحاب الدور.
- مادة غير موجودة تدخل مراجعة محاسب ولا تمنع الإنشاء.

    purchase_invoices/{invoiceId}
    purchase_invoices/{invoiceId}/items/{itemId}
    purchase_invoice_events/{eventId}
    purchase_invoice_prices/{invoiceId}                  # محمي
    purchase_invoice_amendments/{amendmentId}
    purchase_invoice_amendments/{amendmentId}/items/{id}
    purchase_invoice_amendment_prices/{amendmentId}      # محمي
    product_review_tasks/{taskId}

### 6.5 فواتير المناقلات بين الفروع

المادة تختار من كتالوج **الفرع المرسل**، لا المستلم. الفواتير الحديثة V3 لا
تدخل الأسعار في واجهة مدير الفرع.

    مدير الفرع المرسل ينشئ المناقلة
    → pendingReceiverReview
    → مدير الفرع المستلم يؤكد الاستلام والكميات
    → pendingDualAccounting
    → المحاسب يرحل جانب الفرع المرسل والجانب المستلم كلًا على حدة
    → postedToAccounting بعد اكتمال الجانبين

- المدير العام مراقب للسجلات، ويعمل كمستلم حيث يكون الفرع الرئيسي هو الطرف
  المستلم.
- السجل الإداري يبدأ باختيار فرع، ثم وارد أو صادر، مع فلاتر الحالة والفترة
  وحالة الترحيل وتحميل صفحات تتجاوز أول 50 فاتورة.
- بطاقات الملخص قابلة للضغط وتفتح الوجهة التي تدل عليها.
- الفاتورة القديمة يمكن تجهيزها للترحيل المزدوج: يحدد المحاسب الجانب المترحل
  سابقًا ثم يرحل الجانب الآخر. لا تغير البيانات التاريخية المالية.
- V2 قديم ما زال يحتوي خطوة سعر محمية؛ لا تحذف توافقه بلا فحص إنتاج وخطة انتقال.

#### تعديل المناقلة V3

1. قبل الاستلام: منشئ المناقلة فقط يعدل مباشرة.
2. بعد الاستلام: المشاركون المسجلون فقط يطلبون ويعتمدون التعديل.
3. المحاسب الذي يرحل أي جانب يضاف إلى المشاركين.
4. الرفض يسجل السبب ويعيد الحالة السابقة بلا تطبيق للمقترح.
5. عند إجماع المشاركين تطبق المواد والكميات والملاحظات، وتعود المناقلة إلى
   الاستلام وتصفّر بيانات الاستلام والترحيل للمسار الجديد.
6. شاشة التفاصيل تعرض المواد الحالية والمقترحة قبل الموافقة أو الرفض.

    inter_branch_invoices/{invoiceId}
    inter_branch_invoices/{invoiceId}/items/{itemId}
    inter_branch_invoice_events/{eventId}
    inter_branch_invoice_prices/{invoiceId}              # V2 فقط، محمي
    inter_branch_invoice_price_history/{eventId}         # محمي
    inter_branch_invoice_counters/{branchId}

ملفاتها: hostinger-push-server/inter-branch-invoice-domain.js،
hostinger-push-server/inter-branch-invoice-commands.js،
lib/services/inter_branch_invoice_api_service.dart،
lib/services/inter_branch_invoice_service.dart،
lib/screens/inter_branch_invoices/، lib/utils/inter_branch_invoice_policies.dart،
lib/utils/inter_branch_invoice_transitions.dart.

### 6.6 المستهلكات والمصروفات وطلبات الفروع

- consumable_requests: المستهلكات ومسار المراجعة.
- cash_expense_requests: مصروفات نقدية ومرفقات اختيارية ومسار اعتماد.
- branch_requests: طلبات الفرع والتنفيذ والرفض والإكمال.
- لا تخلط منطق هذه الأنظمة مع الشراء أو المناقلات؛ لكل منها نموذج وقواعد مستقلة.

---

## 7. خادم Hostinger

المسار: hostinger-push-server/
التشغيل: npm start
الصحة: GET https://collection-api.alasalh.com/health

### المسؤوليات

- التحقق من token والهوية والأدوار وحالة المستخدم.
- إدارة كلمات المرور والمستخدمين وتعيين مدير الفرع.
- أوامر الشراء والمناقلات الذرية، revision وidempotency، الأحداث والإشعارات.
- كتابة السعر المحمي فقط حيث تسمح الصلاحيات.
- إرسال FCM.

### المسارات الرئيسة

    POST /v1/inter-branch-invoices
    POST /v1/inter-branch-invoices/:id/confirm-receipt
    POST /v1/inter-branch-invoices/:id/confirm-prices                 # V2/legacy
    POST /v1/inter-branch-invoices/:id/initialize-legacy-dual-accounting
    POST /v1/inter-branch-invoices/:id/post-accounting
    POST /v1/inter-branch-invoices/:id/request-amendment
    POST /v1/inter-branch-invoices/:id/decide-amendment
    POST /v1/inter-branch-invoices/:id/request-cancellation
    POST /v1/inter-branch-invoices/:id/decide-cancellation

    POST /v1/purchase-invoices
    POST /v1/purchase-invoices/:id/confirm-receipt
    POST /v1/purchase-invoices/:id/confirm-prices
    POST /v1/purchase-invoices/:id/post-accounting
    POST /v1/purchase-invoices/:id/amendments
    POST /v1/purchase-invoices/:id/amendments/:amendmentId/decision
    GET  /v1/purchase-invoices/amendments/pending
    GET  /v1/purchase-invoices/:id

    POST /v1/auth/forgot-password
    POST /v1/auth/change-password
    POST /v1/admin/users
    PATCH /v1/admin/users/:uid
    POST /v1/admin/users/:uid/reset-password
    POST /v1/admin/branches/:branchId/manager

### بيئة Hostinger

خذ الأسماء فقط من hostinger-push-server/.env.example، ولا تكشف القيم:

    FIREBASE_SERVICE_ACCOUNT_BASE64
    # أو FIREBASE_PROJECT_ID + FIREBASE_CLIENT_EMAIL + FIREBASE_PRIVATE_KEY
    FIREBASE_WEB_API_KEY
    ALLOWED_ORIGINS=https://app.alasalh.com,https://app-alasalh.web.app
    POLL_INTERVAL_MS=5000
    ANDROID_NOTIFICATION_CHANNEL_ID=high_importance_channel
    FIREBASE_EMAIL_LOCALE=ar
    PASSWORD_RESET_CONTINUE_URL=...

Hostinger موصول بـ main. بعد تعديل الخادم تحقق من Deployments وسجل التشغيل
وhealth؛ لا يكفي وجود push إلى GitHub لإعلان النجاح.

### PHP الخاص بمرفقات المصروفات

server/hostinger/upload_invoice.php خدمة مستقلة. تستخدم INVOICE_UPLOAD_TOKEN أو
upload_invoice.config.php غير المتتبع. لا تستبدلها أثناء نشر Node ولا تكشف توكنها.

---

## 8. Firebase: قواعد وفهارس

- القواعد: firestore.rules.
- الفهارس: firestore.indexes.json.
- اختبار القواعد: firestore_rules_tests/ على Emulator فقط ومشروعه
  demo-store-collection-catalog، وليس الإنتاج.
- لا تنشر القواعد أو الفهارس بلا طلب صريح وفحص.

تسلسل النشر المصرح:

    firebase deploy --only firestore:indexes --project store-collection-app
    # انتظر كل الفهارس المطلوبة حتى تصبح Enabled في Firebase Console
    firebase deploy --only firestore:rules --project store-collection-app

القواعد تحمي الكتالوج والأسعار والتحصيل والمشتريات والمناقلات والمستهلكات وطلبات
الفروع والمصروفات. لا تخفف القواعد فقط لتجاوز فشل اختبار؛ أصلح التصميم وأضف
اختبار وصول غير مصرح به.

---

## 9. الويب، الجلسات والطباعة

### النشر

.github/workflows/deploy-web.yml ينطلق عند push إلى main في ملفات التطبيق
المعنية. يبني الويب مع:

    AUTH_API_BASE_URL=https://collection-api.alasalh.com
    WEB_RELEASE_ID=<Git SHA>

ثم يكتب build/web/deployment.json وينشر Firebase Hosting بواسطة OIDC قصير العمر.
توجد no-cache headers لملفات bootstrap والإصدار كي لا يبقى المتصفح على نسخة قديمة.

### النطاق

النطاق المقترح: app.alasalh.com، وDNS:

    CNAME  app  app-alasalh.web.app

أضفه إلى Firebase Authentication Authorized domains وإلى ALLOWED_ORIGINS.

### الطباعة

lib/widgets/pdf_print_format_picker.dart يعرض قالبين قبل الطباعة: **A4** أو
**إيصال حراري 80mm**. على الويب يفتح مربع طباعة المتصفح؛ لا يمكن للتطبيق فرض
طابعة أو تجاوز تأكيده.

---

## 10. التحديث الداخلي لـ Android

### النشر

.github/workflows/publish-android-update.yml:

1. يستعيد مفتاح التوقيع من GitHub Secrets.
2. يبني APK موقعًا.
3. يتحقق من SHA-256.
4. ينشئ GitHub Release ويرفع APK.
5. ينشر app-releases/android.json إلى Firebase Hosting target updates.

الوسوم:

    android-v<version>+<build>             # اختياري
    android-mandatory-v<version>+<build>   # إلزامي

مثال:

    # عدل pubspec.yaml أولًا إلى رقم أعلى وفريد
    git tag -a "android-v1.0.18+26" -m "Optional Android update 1.0.18+26"
    git push origin "android-v1.0.18+26"

لا تعد استخدام build number أو tag منشورًا.

### سلوك التطبيق

- lib/services/app_update_service.dart يقرأ Manifest.
- lib/widgets/app_update_gate.dart يمنع الاستخدام فقط عند mandatory: true.
- بطاقة الإعدادات: lib/widgets/app_update_settings_card.dart.
- خدمة Android: android/app/src/main/kotlin/com/storecollection/store_collection_app/AppUpdateDownloadService.kt.
- التنزيل foreground service، إشعار تقدم، ملف part تحت files/updates، استئناف
  HTTP Range، محاولات شبكة، والتحقق من SHA-256.
- Android لا يسمح بتثبيت APK بصمت؛ يؤكد المستخدم التثبيت النهائي. الخروج العادي
  لا يوقف التنزيل، لكن Force stop يوقفه حسب النظام.

الأسرار اللازمة في GitHub Secrets، دون عرض قيمها:

    ANDROID_KEYSTORE_BASE64
    ANDROID_STORE_PASSWORD
    ANDROID_KEY_ALIAS
    ANDROID_KEY_PASSWORD

---

## 11. بوابات التحقق قبل الدمج أو النشر

### Flutter فقط

    flutter analyze --no-pub
    flutter test
    git diff --check

### المناقلات أو المشتريات

    flutter test test/inter_branch_invoice_phase2_widget_test.dart
    Push-Location hostinger-push-server
    npm test
    npm run check
    Pop-Location

اختبر يدويًا: كل دور معني، انعكاس البيانات بعد refresh، رفض وموافقة التعديل،
عدم ظهور السعر لمدير الفرع، الإشعارات، وترحيل جانبي المناقلة V3.

### تحديث Android

بعد نجاح workflow تحقق من GitHub Release ومن android.json: الإصدار والبناء
والرابط وSHA وmandatory. لا تعلن نجاح النشر قبل ذلك.

---

## 12. ربط Cloud Code والخدمات من جديد

هذا القسم هو دليل الربط العملي. لا يحتاج Cloud Code إلى إنشاء مشروع جديد؛ يجب
ربطه بالموارد **القائمة** حتى يستمر التطبيق والمستخدمون والفواتير والتحديثات
بالعمل كما هي.

### 12.1 صلاحيات يجب أن يمنحها مالك الحساب

أضف الحساب أو هوية Cloud Code/المطور إلى الخدمات التالية، بأقل صلاحية تكفي
للعمل:

1. **GitHub**: وصول write إلى المستودع
   e-qadr/store-collection-app، والوصول إلى Actions وإلى Secrets عند الحاجة
   لإدارة الإصدارات.
2. **Firebase وGoogle Cloud**: الوصول إلى المشروع الحالي
   store-collection-app، وليس مشروع Firebase جديدًا. يلزم عادة Firebase
   Authentication Admin، Cloud Firestore Admin، Firebase Hosting Admin
   وصلاحية مشاهدة/تشغيل إعدادات Workload Identity عند صيانة CI.
3. **Hostinger hPanel**: الوصول إلى موقع Node باسم
   collection-api.alasalh.com، وإلى Environment variables وDeployments وRuntime
   logs وإعداد اتصال GitHub.
4. **DNS للنطاق alasalh.com**: فقط إذا تغير نطاق الويب أو الـ API.

لا تشارك كلمة مرور الحساب أو ملف service account أو keystore داخل المحادثة.
استخدم دعوة مستخدم أو ربط حساب Cloud Code رسمي أو GitHub Secrets.

### 12.2 استنساخ المستودع والتحقق من الهوية

    git clone https://github.com/e-qadr/store-collection-app.git
    cd store-collection-app
    git switch main
    git pull --ff-only origin main
    git status --short --branch
    flutter pub get
    flutter analyze --no-pub

تأكد أن آخر commit يطابق رقم مراجعة نشر الويب في:

    https://app-alasalh.web.app/deployment.json

إذا كان هناك فرق، لا تفترض السبب. افحص GitHub Actions وFirebase Hosting أولًا.

### 12.3 ربط Firebase الصحيح

اسم المشروع الإنتاجي هو:

    store-collection-app

لا تشغّل flutterfire configure على مشروع جديد ولا تستبدل إعدادات التطبيق إلا إذا
كان المطلوب صراحة هو نقل Firebase. الإعدادات العامة الموجودة بالفعل:

- إعدادات الويب العامة في lib/firebase_web_options.dart.
- إعداد Android العام في android/app/google-services.json.
- أهداف Hosting في .firebaserc:
  - target web → app-alasalh
  - target updates → updates-alasalh
- القواعد والفهارس في firestore.rules وfirestore.indexes.json.

بعد منح وصول Google/Firebase، تحقق فقط:

    firebase login
    firebase projects:list
    firebase use store-collection-app
    firebase hosting:sites:list --project store-collection-app

في Firebase Console تحقق من:

1. Authentication: Email/Password مفعّل، والنطاقات المصرح بها تشمل
   app-alasalh.web.app وapp.alasalh.com إن كان النطاق المخصص مفعّلًا.
2. Firestore: قاعدة الإنتاج هي التي تحوي المستخدمين والفواتير الحالية؛ لا تنشئ
   قاعدة أو مجموعة بديلة.
3. Cloud Messaging: إعدادات Android والويب مستمرة في المشروع نفسه.
4. Hosting: يوجد الموقعان app-alasalh وupdates-alasalh.
5. Google Cloud: واجهات IAM Credentials وSecurity Token Service مفعلة لكي تعمل
   GitHub Actions عبر OIDC.

**لا تنشر قواعد أو فهارس لمجرد نجاح الربط.** نفذ اختبارات المحاكي أولًا، ثم انشر
فقط عند وجود تفويض صريح كما في القسم 8.

### 12.4 إبقاء نشر الويب التلقائي متصلًا

الملف .github/workflows/deploy-web.yml هو نقطة الربط. وهو يستخدم:

    Workload Identity Provider:
    projects/385756153909/locations/global/workloadIdentityPools/github-actions/providers/github

    Service account:
    github-firebase-deployer@store-collection-app.iam.gserviceaccount.com

لذلك عند نقل ملكية GitHub أو تعديل Organization:

1. لا تحذف provider أو service account الحاليين قبل التأكد من workflow.
2. تحقق أن الـ provider يقبل المستودع الجديد أو فرع main الصحيح.
3. ابق service account صالحًا بصلاحية نشر Firebase Hosting.
4. نفذ workflow يدويًا أو push تجريبيًا محدودًا، ثم راقب نجاح Deploy web.
5. افحص deployment.json؛ هذه هي طريقة تأكيد أن الويب المنشور هو commit المقصود.

الويب ينشر تلقائيًا عند push إلى main في الملفات المحددة داخل workflow. أي تغيير
في خادم Hostinger قد يحتاج نشر Hostinger منفصلًا، حتى لو نشر الويب بنجاح.

### 12.5 إعادة ربط Hostinger API

في hPanel راجع تطبيق Node الحالي، ولا تنشئ تطبيقًا ثانيًا على نطاق مختلف:

    التطبيق: collection-api.alasalh.com
    المستودع: e-qadr/store-collection-app
    الفرع: main
    Root directory: hostinger-push-server
    Start command: npm start
    Node: 20.x

انقل أو أعد إدخال متغيرات البيئة الموجودة في التطبيق الحالي باستخدام أسماء
hostinger-push-server/.env.example، وأهمها:

    FIREBASE_SERVICE_ACCOUNT_BASE64
    FIREBASE_WEB_API_KEY
    ALLOWED_ORIGINS=https://app.alasalh.com,https://app-alasalh.web.app
    POLL_INTERVAL_MS=5000
    ANDROID_NOTIFICATION_CHANNEL_ID=high_importance_channel
    FIREBASE_EMAIL_LOCALE=ar

المفضل هو FIREBASE_SERVICE_ACCOUNT_BASE64 بدل تقسيم private key إلى أسطر. يجب
أن يكون service account تابعًا لمشروع Firebase الحالي وله صلاحيات Firebase Admin
المطلوبة. بعد حفظ المتغيرات ونشر Hostinger تحقق من:

    https://collection-api.alasalh.com/health

ثم سجّل دخولًا بحساب اختبار وافتح عملية بسيطة. لا تجرّب أوامر إنتاجية تغير
فاتورة حقيقة لمجرد فحص الاتصال.

إذا نقلت النطاق، حدّث هذه المواضع معًا:

1. AUTH_API_BASE_URL في workflowين.
2. ALLOWED_ORIGINS في Hostinger.
3. Authorized domains في Firebase Authentication.
4. أي build محلي يستخدم dart-define.

### 12.6 ربط GitHub Actions وتحديث Android

نشر تحديث Android لا يحتاج كشف keystore إلى Cloud Code إذا بقيت GitHub Secrets
الأصلية موجودة. تحقق من وجود الأسماء فقط:

    ANDROID_KEYSTORE_BASE64
    ANDROID_STORE_PASSWORD
    ANDROID_KEY_ALIAS
    ANDROID_KEY_PASSWORD

هذه الأسرار يجب أن تبقى نفسها لأن تحديث التطبيق المثبت يتطلب APK موقّعًا
بالشهادة نفسها. إذا فُقد المفتاح أو استبدل بمفتاح جديد فلن يستطيع Android تثبيت
التحديث فوق النسخة الموجودة؛ سيحتاج المستخدمون إزالة التطبيق وتثبيت تطبيق جديد.

خطوات إصدار Android صحيحة:

1. غيّر version في pubspec.yaml إلى رقم أكبر مع build number جديد وفريد.
2. ادفع commit إلى main بعد التحقق؛ ينتج عنه نشر الويب تلقائيًا.
3. أنشئ وسمًا اختياريًا أو إلزاميًا:

       git tag -a "android-v1.0.18+26" -m "Optional Android update 1.0.18+26"
       git push origin "android-v1.0.18+26"

   أو:

       git tag -a "android-mandatory-v1.0.18+26" -m "Mandatory Android update 1.0.18+26"
       git push origin "android-mandatory-v1.0.18+26"

4. انتظر Publish Android update في GitHub Actions.
5. تحقق من GitHub Release ومن:

       https://updates-alasalh.web.app/android.json

   يجب أن يطابق version وbuildNumber وmandatory وapkUrl وsha256.

مكان نشر APK هو GitHub Release. مكان إعلان التحديث هو Firebase Hosting target
updates. لا ترفع APK إلى Git ولا إلى موقع الويب الرئيسي.

### 12.7 نقل النطاقات وDNS

الواجهة الحالية في app-alasalh.web.app. عند تفعيل app.alasalh.com:

    CNAME  app  app-alasalh.web.app

ثم أضف النطاق إلى Firebase Hosting وFirebase Authentication وALLOWED_ORIGINS.
لا تغير DNS للـ API أو الويب في الوقت نفسه دون فترة تحقق؛ قد توقف الواجهة أو CORS.

### 12.8 اختبار قبول سريع بعد الربط

نفذ هذه الفحوص دون تغيير بيانات إنتاج:

1. افتح الويب وسجّل دخول مستخدم اختبار؛ أغلق الصفحة وافتحها للتحقق من الجلسة.
2. افتح deployment.json وتأكد من SHA أحدث main.
3. افتح health لخادم Hostinger وتأكد من جاهزية الإعداد، دون طباعة أسرار.
4. افتح سجل المناقلات وفاتورة شراء وسند تحصيل بصلاحيات الاختبار المناسبة.
5. تأكد أن مدير الفرع لا يرى الأسعار وأن المحاسب أو المدير العام يراها حيث يلزم.
6. راقب إشعارًا على حساب اختبار عند إنشاء حدث غير مدمر.
7. افحص android.json ولا تنشئ إصدار Android إلا بعد مراجعة رقم البناء.

---

## 13. تعليمات أول جلسة في Cloud Code

    git status --short --branch
    git log --oneline --decorate -12
    rg -n "^version:" pubspec.yaml
    flutter analyze --no-pub

ثم:

1. اقرأ هذا الملف وREADME.md وhostinger-push-server/README.md.
2. حافظ على أي تعديلات أو ملفات محلية لا تخص الطلب الحالي.
3. افهم المسار المتأثر وأضف اختبارًا يعيد المشكلة قبل تطبيق حل كبير.
4. عدل أقل نطاق ممكن وشغل الاختبارات المختصة.
5. لا تبن أو تنشر أو تدفع GitHub أو Firebase أو Hostinger إلا بطلب صريح.
6. افصل بين نشر الويب ونشر الخادم وقواعد Firestore وإصدار Android؛ لكل واحد
   تحقق مستقل.
7. لا تستخدم git reset --hard أو force push أو npm audit fix --force.

### مراجع سريعة

    إقلاع التطبيق:                 lib/main.dart
    المصادقة:                      lib/screens/auth/ و lib/services/auth_service.dart
    التحديث:                       lib/services/app_update_service.dart
    التحصيل:                       lib/services/database_service.dart و lib/screens/transactions/
    المشتريات:                     lib/screens/purchase_invoices/ و lib/services/purchase_invoice_*.dart
    المناقلات:                     lib/screens/inter_branch_invoices/ و lib/services/inter_branch_invoice_*.dart
    خادم المناقلات:                hostinger-push-server/inter-branch-invoice-*.js
    الكتالوج:                      lib/screens/products/ و lib/services/product_catalog_service.dart
    قواعد Firestore:               firestore.rules
    اختبارات الأمان:               firestore_rules_tests/test/
    نشر الويب:                     .github/workflows/deploy-web.yml
    نشر Android:                   .github/workflows/publish-android-update.yml

هذا المستند يصف الحالة المعروفة فقط؛ لا يمثل تفويضًا لتعديل بيانات الإنتاج أو
نشر قواعد أو كشف بيانات اعتماد.
