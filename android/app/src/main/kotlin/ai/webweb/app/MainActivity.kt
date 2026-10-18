package ai.webweb.app

import android.content.Context
import android.os.PowerManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * "webweb/call": the native side of a call (see call_manager.dart):
 * - service: the ongoing-call foreground service ([CallService]); "hangUp" comes back from its notification
 * - proximity: screen off while the phone is at the ear (voice calls on the earpiece), as the phone app does
 * - awake: keep the screen on (video calls)
 */
class MainActivity : FlutterActivity() {
    private var proximity: PowerManager.WakeLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "webweb/call")
        CallService.onHangUp = { runOnUiThread { channel.invokeMethod("hangUp", null) } }
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "service" -> {
                    if (call.argument<Boolean>("on") == true) {
                        CallService.start(
                            applicationContext,
                            call.argument<String>("name") ?: "WEBWEB AI",
                            call.argument<Boolean>("video") == true,
                            call.argument<Boolean>("connected") == true,
                            call.argument<String>("status") ?: "",
                            call.argument<String>("hangUp") ?: "",
                        )
                    } else {
                        CallService.stop(applicationContext)
                    }
                    result.success(null)
                }
                "proximity" -> {
                    setProximity(call.argument<Boolean>("on") == true)
                    result.success(null)
                }
                "awake" -> {
                    if (call.argument<Boolean>("on") == true) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun setProximity(on: Boolean) {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        if (on) {
            if (proximity?.isHeld == true) return
            if (!pm.isWakeLockLevelSupported(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK)) return
            proximity = pm.newWakeLock(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK, "webweb:call").apply {
                setReferenceCounted(false)
                acquire(4 * 60 * 60 * 1000L)
            }
        } else {
            proximity?.let { if (it.isHeld) it.release() }
            proximity = null
        }
    }

    override fun onDestroy() {
        setProximity(false)
        super.onDestroy()
    }
}
