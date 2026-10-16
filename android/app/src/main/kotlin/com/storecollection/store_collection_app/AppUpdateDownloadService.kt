package com.storecollection.store_collection_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import java.io.BufferedInputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * A foreground Android service for application updates.
 *
 * Keeping the transfer on the native side makes it independent of the Flutter
 * activity: swiping the app away no longer cancels it. The partial APK is kept
 * in files/updates and HTTP Range requests resume it after a lost connection.
 */
class AppUpdateDownloadService : Service() {
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    @Volatile private var isDownloading = false

    override fun onCreate() {
        super.onCreate()
        createChannel(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val request = when (intent?.action) {
            ACTION_START -> UpdateDownloadStore.saveRequest(
                this,
                UpdateRequest(
                    url = intent.getStringExtra(EXTRA_URL).orEmpty(),
                    sha256 = intent.getStringExtra(EXTRA_SHA256).orEmpty(),
                    version = intent.getStringExtra(EXTRA_VERSION).orEmpty(),
                    buildNumber = intent.getIntExtra(EXTRA_BUILD_NUMBER, 0),
                ),
            )
            else -> UpdateDownloadStore.readRequest(this)
        }

        if (request == null || !request.isValid) {
            stopSelf(startId)
            return START_NOT_STICKY
        }

        // Android requires a foreground notification immediately after a
        // foreground service has been started.
        startForeground(NOTIFICATION_ID, notificationFor(UpdateDownloadStore.readState(this)))
        if (!isDownloading) {
            isDownloading = true
            executor.execute { download(request, startId) }
        }
        return START_STICKY
    }

    private fun download(request: UpdateRequest, startId: Int) {
        var retryDelayMillis = INITIAL_RETRY_DELAY_MILLIS
        try {
            val finalFile = updateFile(request, ".apk")
            val partialFile = updateFile(request, ".apk.part")

            if (finalFile.isFile && UpdateFileVerifier.hasSha256(finalFile, request.sha256)) {
                UpdateDownloadStore.ready(this, finalFile)
                updateNotification(UpdateDownloadStore.readState(this))
                return
            }
            if (finalFile.exists()) finalFile.delete()

            while (true) {
                try {
                    downloadOnce(request, partialFile)
                    UpdateDownloadStore.verifying(this)
                    updateNotification(UpdateDownloadStore.readState(this))
                    if (!UpdateFileVerifier.hasSha256(partialFile, request.sha256)) {
                        partialFile.delete()
                        throw IllegalStateException("فشل التحقق من سلامة ملف التحديث. سيعاد تنزيله تلقائياً.")
                    }
                    if (!partialFile.renameTo(finalFile)) {
                        throw IllegalStateException("تعذر تجهيز ملف التحديث للتثبيت.")
                    }
                    UpdateDownloadStore.ready(this, finalFile)
                    updateNotification(UpdateDownloadStore.readState(this))
                    return
                } catch (error: Exception) {
                    val state = UpdateDownloadStore.retrying(
                        this,
                        error.message ?: "انقطع الاتصال أثناء تنزيل التحديث.",
                    )
                    updateNotification(state)
                    try {
                        Thread.sleep(retryDelayMillis)
                    } catch (_: InterruptedException) {
                        Thread.currentThread().interrupt()
                        return
                    }
                    retryDelayMillis = (retryDelayMillis * 2).coerceAtMost(MAX_RETRY_DELAY_MILLIS)
                }
            }
        } finally {
            isDownloading = false
            // Leave completed/retrying work visible in the notification. If the
            // process is stopped unexpectedly, START_STICKY restores the request
            // and continues from the .part file.
            val state = UpdateDownloadStore.readState(this)
            if (state.status == UpdateDownloadStatus.READY) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    stopForeground(STOP_FOREGROUND_DETACH)
                } else {
                    @Suppress("DEPRECATION")
                    stopForeground(false)
                }
                stopSelf(startId)
            }
        }
    }

    private fun downloadOnce(request: UpdateRequest, partialFile: File) {
        partialFile.parentFile?.mkdirs()
        var alreadyDownloaded = partialFile.takeIf { it.isFile }?.length() ?: 0L
        val connection = (URL(request.url).openConnection() as HttpURLConnection).apply {
            instanceFollowRedirects = true
            connectTimeout = CONNECT_TIMEOUT_MILLIS
            readTimeout = READ_TIMEOUT_MILLIS
            setRequestProperty("Accept-Encoding", "identity")
            if (alreadyDownloaded > 0) setRequestProperty("Range", "bytes=$alreadyDownloaded-")
        }

        try {
            val responseCode = connection.responseCode
            val append = when (responseCode) {
                HttpURLConnection.HTTP_PARTIAL -> true
                HttpURLConnection.HTTP_OK -> {
                    // Server did not honour Range. Avoid appending duplicate
                    // bytes and simply restart this individual attempt.
                    alreadyDownloaded = 0L
                    if (partialFile.exists()) partialFile.delete()
                    false
                }
                else -> throw IllegalStateException("تعذر تنزيل التحديث (رمز $responseCode).")
            }
            val totalBytes = contentLength(connection, alreadyDownloaded)
            UpdateDownloadStore.downloading(this, alreadyDownloaded, totalBytes)
            updateNotification(UpdateDownloadStore.readState(this))

            BufferedInputStream(connection.inputStream, BUFFER_SIZE).use { input ->
                FileOutputStream(partialFile, append).use { output ->
                    val buffer = ByteArray(BUFFER_SIZE)
                    var bytesRead: Int
                    var received = alreadyDownloaded
                    var lastNotificationAt = 0L
                    while (input.read(buffer).also { bytesRead = it } >= 0) {
                        output.write(buffer, 0, bytesRead)
                        received += bytesRead
                        val now = System.currentTimeMillis()
                        if (now - lastNotificationAt >= NOTIFICATION_UPDATE_INTERVAL_MILLIS) {
                            lastNotificationAt = now
                            val state = UpdateDownloadStore.downloading(this, received, totalBytes)
                            updateNotification(state)
                        }
                    }
                    output.fd.sync()
                    val state = UpdateDownloadStore.downloading(this, received, totalBytes)
                    updateNotification(state)
                }
            }
        } finally {
            connection.disconnect()
        }
    }

    private fun contentLength(connection: HttpURLConnection, alreadyDownloaded: Long): Long {
        val contentRange = connection.getHeaderField("Content-Range")
        val totalFromRange = contentRange
            ?.substringAfterLast('/', missingDelimiterValue = "")
            ?.toLongOrNull()
        if (totalFromRange != null && totalFromRange > 0) return totalFromRange
        val bodyLength = connection.contentLengthLong
        return if (bodyLength > 0) bodyLength + alreadyDownloaded else 0L
    }

    private fun updateFile(request: UpdateRequest, suffix: String): File {
        val safeVersion = request.version.replace(Regex("[^A-Za-z0-9._-]"), "_")
        return File(filesDir, "updates/store-collection-app-v$safeVersion+${request.buildNumber}$suffix")
    }

    private fun updateNotification(state: UpdateDownloadState) {
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, notificationFor(state))
    }

    private fun notificationFor(state: UpdateDownloadState) = NotificationCompat.Builder(this, CHANNEL_ID)
        .setSmallIcon(android.R.drawable.stat_sys_download)
        .setContentTitle("تحديث إدارة الأصالة")
        .setContentText(state.notificationText())
        .setOnlyAlertOnce(true)
        .setOngoing(state.status != UpdateDownloadStatus.READY)
        .setCategory(NotificationCompat.CATEGORY_PROGRESS)
        .setContentIntent(openAppPendingIntent(this))
        .apply {
            val total = state.totalBytes
            if (state.status == UpdateDownloadStatus.DOWNLOADING && total > 0) {
                setProgress(100, ((state.receivedBytes * 100) / total).toInt().coerceIn(0, 100), false)
            } else if (state.status == UpdateDownloadStatus.VERIFYING) {
                setProgress(0, 0, true)
            }
            if (state.status == UpdateDownloadStatus.READY) {
                setSmallIcon(android.R.drawable.stat_sys_download_done)
                setAutoCancel(true)
                addAction(
                    android.R.drawable.stat_sys_download_done,
                    "تثبيت الآن",
                    installPendingIntent(this@AppUpdateDownloadService),
                )
            }
        }
        .build()

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        const val ACTION_START = "com.storecollection.store_collection_app.START_UPDATE_DOWNLOAD"
        const val EXTRA_URL = "url"
        const val EXTRA_SHA256 = "sha256"
        const val EXTRA_VERSION = "version"
        const val EXTRA_BUILD_NUMBER = "buildNumber"
        const val CHANNEL_ID = "app_update_download"
        const val NOTIFICATION_ID = 3012
        private const val CONNECT_TIMEOUT_MILLIS = 20_000
        private const val READ_TIMEOUT_MILLIS = 45_000
        private const val INITIAL_RETRY_DELAY_MILLIS = 5_000L
        private const val MAX_RETRY_DELAY_MILLIS = 60_000L
        private const val NOTIFICATION_UPDATE_INTERVAL_MILLIS = 500L
        private const val BUFFER_SIZE = 128 * 1024

        internal fun start(context: Context, request: UpdateRequest) {
            val intent = Intent(context, AppUpdateDownloadService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_URL, request.url)
                putExtra(EXTRA_SHA256, request.sha256)
                putExtra(EXTRA_VERSION, request.version)
                putExtra(EXTRA_BUILD_NUMBER, request.buildNumber)
            }
            ContextCompat.startForegroundService(context, intent)
        }

        fun createChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val channel = NotificationChannel(
                CHANNEL_ID,
                "تنزيل تحديثات التطبيق",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "يبين تقدم تنزيل تحديثات إدارة الأصالة"
                setShowBadge(false)
            }
            context.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }

        private fun openAppPendingIntent(context: Context): PendingIntent {
            val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                ?: Intent(context, MainActivity::class.java)
            return PendingIntent.getActivity(
                context,
                30120,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun installPendingIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
            context,
            30121,
            Intent(context, AppUpdateInstallReceiver::class.java).setAction(AppUpdateInstallReceiver.ACTION_INSTALL),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}

class AppUpdateInstallReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != ACTION_INSTALL) return
        val file = UpdateDownloadStore.readyFile(context) ?: return
        UpdateInstaller.install(context, file)
    }

    companion object {
        const val ACTION_INSTALL = "com.storecollection.store_collection_app.INSTALL_DOWNLOADED_UPDATE"
    }
}

internal data class UpdateRequest(
    val url: String,
    val sha256: String,
    val version: String,
    val buildNumber: Int,
) {
    val isValid: Boolean
        get() = url.startsWith("https://") &&
            sha256.matches(Regex("^[a-fA-F0-9]{64}$")) &&
            version.isNotBlank() && buildNumber > 0
}

internal enum class UpdateDownloadStatus(val wireValue: String) {
    IDLE("idle"),
    DOWNLOADING("downloading"),
    RETRYING("retrying"),
    VERIFYING("verifying"),
    READY("ready"),
    ;

    companion object {
        fun fromWireValue(value: String?) = entries.firstOrNull { it.wireValue == value } ?: IDLE
    }
}

internal data class UpdateDownloadState(
    val status: UpdateDownloadStatus,
    val receivedBytes: Long = 0L,
    val totalBytes: Long = 0L,
    val error: String? = null,
    val version: String? = null,
    val buildNumber: Int = 0,
) {
    fun toMap(): Map<String, Any> = mapOf(
        "status" to status.wireValue,
        "receivedBytes" to receivedBytes,
        "totalBytes" to totalBytes,
        "error" to (error ?: ""),
        "version" to (version ?: ""),
        "buildNumber" to buildNumber,
    )

    fun notificationText(): String = when (status) {
        UpdateDownloadStatus.DOWNLOADING -> {
            if (totalBytes > 0) {
                "تم تنزيل ${formatBytes(receivedBytes)} من ${formatBytes(totalBytes)} — متبقي ${formatBytes((totalBytes - receivedBytes).coerceAtLeast(0))}"
            } else {
                "تم تنزيل ${formatBytes(receivedBytes)} من التحديث"
            }
        }
        UpdateDownloadStatus.RETRYING -> "انقطع الاتصال — سيُستأنف التنزيل تلقائياً"
        UpdateDownloadStatus.VERIFYING -> "جارٍ التحقق من سلامة التحديث"
        UpdateDownloadStatus.READY -> "اكتمل التنزيل. اضغط لتثبيت التحديث."
        UpdateDownloadStatus.IDLE -> "جاهز لتنزيل التحديث"
    }

    private fun formatBytes(bytes: Long): String {
        val megabytes = bytes / (1024.0 * 1024.0)
        return String.format(Locale.US, "%.1f م.ب", megabytes)
    }
}

internal object UpdateDownloadStore {
    private const val PREFS = "app_update_download"
    private const val URL = "url"
    private const val SHA256 = "sha256"
    private const val VERSION = "version"
    private const val BUILD_NUMBER = "buildNumber"
    private const val STATUS = "status"
    private const val RECEIVED_BYTES = "receivedBytes"
    private const val TOTAL_BYTES = "totalBytes"
    private const val ERROR = "error"
    private const val READY_FILE = "readyFile"

    fun saveRequest(context: Context, request: UpdateRequest): UpdateRequest? {
        if (!request.isValid) return null
        val existing = readRequest(context)
        val changedRelease = existing?.version != request.version ||
            existing.buildNumber != request.buildNumber || existing.sha256 != request.sha256
        val editor = prefs(context).edit()
            .putString(URL, request.url)
            .putString(SHA256, request.sha256.lowercase(Locale.US))
            .putString(VERSION, request.version)
            .putInt(BUILD_NUMBER, request.buildNumber)
        if (changedRelease) {
            editor.putString(STATUS, UpdateDownloadStatus.IDLE.wireValue)
                .putLong(RECEIVED_BYTES, 0L)
                .putLong(TOTAL_BYTES, 0L)
                .remove(ERROR)
                .remove(READY_FILE)
        }
        editor.apply()
        return request
    }

    fun readRequest(context: Context): UpdateRequest? {
        val prefs = prefs(context)
        val request = UpdateRequest(
            url = prefs.getString(URL, "").orEmpty(),
            sha256 = prefs.getString(SHA256, "").orEmpty(),
            version = prefs.getString(VERSION, "").orEmpty(),
            buildNumber = prefs.getInt(BUILD_NUMBER, 0),
        )
        return request.takeIf { it.isValid }
    }

    fun readState(context: Context): UpdateDownloadState {
        val prefs = prefs(context)
        return UpdateDownloadState(
            status = UpdateDownloadStatus.fromWireValue(prefs.getString(STATUS, null)),
            receivedBytes = prefs.getLong(RECEIVED_BYTES, 0L),
            totalBytes = prefs.getLong(TOTAL_BYTES, 0L),
            error = prefs.getString(ERROR, null),
            version = prefs.getString(VERSION, null),
            buildNumber = prefs.getInt(BUILD_NUMBER, 0),
        )
    }

    fun downloading(context: Context, received: Long, total: Long): UpdateDownloadState = writeState(
        context,
        UpdateDownloadStatus.DOWNLOADING,
        received,
        total,
        null,
    )

    fun retrying(context: Context, error: String): UpdateDownloadState = writeState(
        context,
        UpdateDownloadStatus.RETRYING,
        readState(context).receivedBytes,
        readState(context).totalBytes,
        error,
    )

    fun verifying(context: Context): UpdateDownloadState = writeState(
        context,
        UpdateDownloadStatus.VERIFYING,
        readState(context).receivedBytes,
        readState(context).totalBytes,
        null,
    )

    fun ready(context: Context, file: File): UpdateDownloadState {
        prefs(context).edit().putString(READY_FILE, file.absolutePath).apply()
        return writeState(
            context,
            UpdateDownloadStatus.READY,
            file.length(),
            file.length(),
            null,
        )
    }

    fun readyFile(context: Context): File? {
        val path = prefs(context).getString(READY_FILE, null) ?: return null
        return File(path).takeIf { it.isFile }
    }

    private fun writeState(
        context: Context,
        status: UpdateDownloadStatus,
        received: Long,
        total: Long,
        error: String?,
    ): UpdateDownloadState {
        prefs(context).edit()
            .putString(STATUS, status.wireValue)
            .putLong(RECEIVED_BYTES, received)
            .putLong(TOTAL_BYTES, total)
            .apply {
                if (error.isNullOrBlank()) remove(ERROR) else putString(ERROR, error)
            }
            .apply()
        return readState(context)
    }

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}

internal object UpdateFileVerifier {
    fun hasSha256(file: File, expected: String): Boolean {
        if (!file.isFile || expected.length != 64) return false
        val digest = MessageDigest.getInstance("SHA-256")
        FileInputStream(file).use { input ->
            val buffer = ByteArray(128 * 1024)
            var count: Int
            while (input.read(buffer).also { count = it } >= 0) {
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
            .equals(expected, ignoreCase = true)
    }
}

internal object UpdateInstaller {
    fun canInstall(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O || context.packageManager.canRequestPackageInstalls()

    fun install(context: Context, apk: File) {
        require(apk.isFile) { "ملف التحديث غير موجود." }
        val apkUri: Uri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.fileprovider",
            apk,
        )
        val installIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(apkUri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(installIntent)
    }
}
