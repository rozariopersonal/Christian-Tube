package org.rozario.christiantube.mobile

import android.service.dreams.DreamService
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterSurfaceView
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugins.GeneratedPluginRegistrant

/**
 * Android OS Screen Saver (DreamService) displaying the ChristianApp Scripture
 * Word Feed when the device is docked or charging.
 */
class WordFeedDreamService : DreamService() {
    private var flutterEngine: FlutterEngine? = null
    private var flutterView: FlutterView? = null

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        isInteractive = false
        isFullscreen = true
        isScreenBright = true

        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(applicationContext)
        loader.ensureInitializationComplete(applicationContext, null)

        val engine = FlutterEngine(this)
        GeneratedPluginRegistrant.registerWith(engine)
        val entrypoint = DartExecutor.DartEntrypoint(
            loader.findAppBundlePath(),
            "screensaverMain"
        )
        engine.dartExecutor.executeDartEntrypoint(entrypoint)

        val view = FlutterView(this, FlutterSurfaceView(this))
        view.attachToFlutterEngine(engine)
        setContentView(view)

        flutterEngine = engine
        flutterView = view
    }

    override fun onDreamingStarted() {
        super.onDreamingStarted()
        flutterEngine?.lifecycleChannel?.appIsResumed()
    }

    override fun onDreamingStopped() {
        super.onDreamingStopped()
        flutterEngine?.lifecycleChannel?.appIsPaused()
    }

    override fun onDetachedFromWindow() {
        flutterView?.detachFromFlutterEngine()
        flutterEngine?.destroy()
        flutterView = null
        flutterEngine = null
        super.onDetachedFromWindow()
    }
}
