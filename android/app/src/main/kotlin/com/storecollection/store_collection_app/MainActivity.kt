package com.storecollection.store_collection_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val channel = NotificationChannel(
            HIGH_IMPORTANCE_CHANNEL_ID,
            "إشعارات المعاملات المهمة",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "إشعارات الاعتماد والتعديل والأرشفة"
            enableVibration(true)
            setShowBadge(true)
        }

        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_UPDATE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstallPackages" -> {
                        result.success(UpdateInstaller.canInstall(this))
                    }

                    "openInstallSettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName"),
                            )
                            startActivity(intent)
                        }
                        result.success(null)
                    }

                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("invalid_path", "لم يتم تحديد ملف التحديث.", null)
                            return@setMethodCallHandler
                        }

                        val apk = java.io.File(path)
                        if (!apk.isFile) {
                            result.error("file_missing", "ملف التحديث غير موجود.", null)
                            return@setMethodCallHandler
                        }

                        try {
                            UpdateInstaller.install(this, apk)
                            result.success(null)
                        } catch (error: Exception) {
                            result.error(
                                "install_failed",
                                error.message ?: "تعذر فتح مُثبّت التحديث.",
                                null,
                            )
                        }
                    }

                    "startUpdateDownload" -> {
                        val request = UpdateRequest(
                            url = call.argument<String>("url").orEmpty(),
                            sha256 = call.argument<String>("sha256").orEmpty(),
                            version = call.argument<String>("version").orEmpty(),
                            buildNumber = call.argument<Int>("buildNumber") ?: 0,
                        )
                        if (!request.isValid) {
                            result.error("invalid_update", "بيانات التحديث غير صالحة.", null)
                            return@setMethodCallHandler
                        }
                        try {
                            AppUpdateDownloadService.start(this, request)
                            result.success(UpdateDownloadStore.readState(this).toMap())
                        } catch (error: Exception) {
                            result.error(
                                "download_start_failed",
                                error.message ?: "تعذر بدء تنزيل التحديث.",
                                null,
                            )
                        }
                    }

                    "getUpdateDownloadState" -> result.success(
                        UpdateDownloadStore.readState(this).toMap(),
                    )

                    "installDownloadedUpdate" -> {
                        val apk = UpdateDownloadStore.readyFile(this)
                        if (apk == null) {
                            result.error(
                                "file_missing",
                                "ملف التحديث المكتمل غير موجود.",
                                null,
                            )
                            return@setMethodCallHandler
                        }
                        if (!UpdateInstaller.canInstall(this)) {
                            result.error(
                                "permission_required",
                                "يتطلب أندرويد السماح بتثبيت التطبيقات من هذا المصدر.",
                                null,
                            )
                            return@setMethodCallHandler
                        }
                        try {
                            UpdateInstaller.install(this, apk)
                            result.success(null)
                        } catch (error: Exception) {
                            result.error(
                                "install_failed",
                                error.message ?: "تعذر فتح مُثبّت التحديث.",
                                null,
                            )
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    companion object {
        const val HIGH_IMPORTANCE_CHANNEL_ID = "high_importance_channel"
        const val APP_UPDATE_CHANNEL =
            "com.storecollection.store_collection_app/app_updates"
    }
}
