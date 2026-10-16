package com.storecollection.store_collection_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

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
                        val canInstall = Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                            packageManager.canRequestPackageInstalls()
                        result.success(canInstall)
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

                        val apk = File(path)
                        if (!apk.isFile) {
                            result.error("file_missing", "ملف التحديث غير موجود.", null)
                            return@setMethodCallHandler
                        }

                        try {
                            val apkUri = FileProvider.getUriForFile(
                                this,
                                "$packageName.fileprovider",
                                apk,
                            )
                            val installIntent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(
                                    apkUri,
                                    "application/vnd.android.package-archive",
                                )
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(installIntent)
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
