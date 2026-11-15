package org.rozario.christiantube.mobile

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Fullscreen Activity shown over the Android lock screen when the user wakes
 * the device, displaying the Scripture Word Feed regardless of charging state.
 */
class ScreensaverActivity : FlutterActivity() {
    companion object {
        const val CHANNEL_NAME = "org.rozario.christiantube.mobile/screensaver"
    }

    private var unlockReceiver: BroadcastReceiver? = null

    override fun getDartEntrypointFunctionName(): String = "screensaverMain"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
        }

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == Intent.ACTION_USER_PRESENT) {
                    finish()
                }
            }
        }
        unlockReceiver = receiver
        val filter = IntentFilter(Intent.ACTION_USER_PRESENT)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(receiver, filter)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                if (call.method == "dismiss") {
                    finish()
                    result.success(true)
                } else {
                    result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        unlockReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {}
        }
        unlockReceiver = null
        super.onDestroy()
    }
}
