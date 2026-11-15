package dev.tidylog.tidy_log_sample

import android.content.Context
import android.os.BatteryManager
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.security.GeneralSecurityException

/**
 * Native half of `lib/platform/native_bridge.dart`. Each method shows one
 * way a platform call can end: success, an error reply, an exception in the
 * handler, or "not implemented". `emitNativeLogs` writes logcat lines so the
 * native side of the console can be compared too.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getBatteryLevel" -> {
                    val battery = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
                    val level = battery.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
                    Log.i(TAG, "Battery level read: $level%")
                    result.success(level)
                }
                "failWithPlatformError" -> {
                    Log.w(TAG, "Card reader not connected, replying UNAVAILABLE")
                    result.error("UNAVAILABLE", "Card reader is not connected.", mapOf("retryable" to true))
                }
                // The embedding catches this, logs it with Log.e and replies
                // with an error envelope that carries the Java stack trace.
                "throwInHandler" -> throw IllegalStateException("Keystore entry missing", IOException("decryption failed"))
                "emitNativeLogs" -> {
                    emitNativeLogs()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun emitNativeLogs() {
        Log.v(TAG, "Verbose: method channel ready")
        Log.d(TAG, "Session cache warmed (12 entries)")
        Log.i(TAG, "Device is not rooted")
        Log.w(TAG, "Certificate pinning is disabled in debug builds")
        Log.e(
            TAG,
            "Secure storage could not be opened. Falling back to plain preferences.",
            SecurityException("Could not decrypt key", GeneralSecurityException("decryption failed")),
        )
        repeat(30) { Log.d("SensorPoller", "Polling accelerometer") }
        for (i in 1..6) Log.d("SyncWorker", "Synced account $i of 6")
    }

    private companion object {
        const val CHANNEL = "tidy_log_sample/native"
        const val TAG = "SampleNative"
    }
}
