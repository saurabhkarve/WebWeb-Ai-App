package ai.webweb.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/**
 * The "Ongoing call" foreground service, like WhatsApp's: from Android 11 an app loses the microphone
 * (and camera) as soon as it leaves the screen unless a foreground service of that type is running, so
 * without it pressing Home mid-call would silently mute the user. It also keeps the process alive and
 * shows the call in the status bar with "Return to call" and "Hang up". Started and stopped from Dart
 * (CallManager, through MainActivity's "webweb/call" channel) for every call, incoming or outgoing.
 */
class CallService : Service() {
    companion object {
        private const val CHANNEL = "ongoing_calls"
        private const val ID = 4711
        private const val ACTION_HANG_UP = "ai.webweb.app.HANG_UP"

        /** Set by MainActivity: tells Dart the user tapped "Hang up" in the notification. */
        var onHangUp: (() -> Unit)? = null

        fun start(context: Context, name: String, video: Boolean, connected: Boolean, status: String, hangUp: String) {
            val i = Intent(context, CallService::class.java)
                .putExtra("name", name)
                .putExtra("status", status)
                .putExtra("hangUp", hangUp)
                .putExtra("video", video)
                .putExtra("connected", connected)
            try {
                ContextCompat.startForegroundService(context, i)
            } catch (_: Exception) {
                // Android 12+ refuses a start from the background; the call goes on, only without the service
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, CallService::class.java))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_HANG_UP) {
            onHangUp?.invoke()
            stopSelf()
            return START_NOT_STICKY
        }
        val name = intent?.getStringExtra("name") ?: "WEBWEB AI"
        val video = intent?.getBooleanExtra("video", false) ?: false
        val connected = intent?.getBooleanExtra("connected", false) ?: false
        val kind = if (video) "video" else "voice"
        val status = intent?.getStringExtra("status")?.takeIf { it.isNotEmpty() }
            ?: if (connected) "Ongoing $kind call · Tap to return" else "Calling…"
        val hangUpLabel = intent?.getStringExtra("hangUp")?.takeIf { it.isNotEmpty() } ?: "Hang up"

        val nm = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && nm.getNotificationChannel(CHANNEL) == null) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "Ongoing calls", NotificationManager.IMPORTANCE_LOW).apply {
                    setShowBadge(false)
                    setSound(null, null)
                }
            )
        }
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val hangUp = PendingIntent.getService(
            this, 1,
            Intent(this, CallService::class.java).setAction(ACTION_HANG_UP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val n: Notification = NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_call)
            .setContentTitle(name)
            .setContentText(status)
            .setUsesChronometer(connected)
            .setWhen(System.currentTimeMillis())
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setColor(0xFF22C55E.toInt())
            .setContentIntent(open)
            .addAction(0, hangUpLabel, hangUp)
            .build()

        var type = 0
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            type = ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            if (video) type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
        }
        try {
            ServiceCompat.startForeground(this, ID, n, type)
        } catch (_: Exception) {
            // e.g. the camera permission was refused: keep the microphone at least
            try {
                ServiceCompat.startForeground(
                    this, ID, n,
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE else 0
                )
            } catch (_: Exception) {
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    /** Swiped away from recents mid-call: the call cannot go on without the app, so end it cleanly. */
    override fun onTaskRemoved(rootIntent: Intent?) {
        onHangUp?.invoke()
        stopSelf()
    }
}
