package com.storecollection.store_collection_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

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

    companion object {
        const val HIGH_IMPORTANCE_CHANNEL_ID = "high_importance_channel"
    }
}
