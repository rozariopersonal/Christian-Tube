package org.rozario.christiantube.mobile

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ScreensaverActivity.CHANNEL_NAME
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "canDrawOverlays" -> {
                    result.success(Settings.canDrawOverlays(this))
                }
                "requestOverlayPermission" -> {
                    val intent = Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.parse("package:$packageName")
                    )
                    startActivity(intent)
                    result.success(true)
                }
                "openDreamSettings" -> {
                    val dreamIntent = Intent(Settings.ACTION_DREAM_SETTINGS)
                    if (dreamIntent.resolveActivity(packageManager) != null) {
                        startActivity(dreamIntent)
                    } else {
                        startActivity(Intent(Settings.ACTION_DISPLAY_SETTINGS))
                    }
                    result.success(true)
                }
                "startLockScreenService" -> {
                    val intent = Intent(this, LockScreenScreensaverService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(true)
                }
                "stopLockScreenService" -> {
                    stopService(Intent(this, LockScreenScreensaverService::class.java))
                    result.success(true)
                }
                "isLockScreenServiceRunning" -> {
                    result.success(LockScreenScreensaverService.isRunning)
                }
                else -> result.notImplemented()
            }
        }
    }
}
