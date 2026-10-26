package app.nussnuss.nussnuss

import android.content.Intent
import android.database.ContentObserver
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var sink: EventChannel.EventSink? = null

    // App shortcuts (long-press the icon): nussnuss://add and nussnuss://activity.
    private var shortcuts: MethodChannel? = null

    /** A shortcut that arrived before Flutter asked for it (a cold start). */
    private var pendingShortcut: String? = null

    /** Flutter has asked once, so later shortcuts are sent straight to it. */
    private var shortcutsReady = false

    override fun onCreate(savedInstanceState: Bundle?) {
        pendingShortcut = shortcutOf(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        // Kept as the activity's intent first, so the deep-link check below sees this one.
        setIntent(intent)
        val action = shortcutOf(intent)
        if (action != null) {
            if (shortcutsReady && shortcuts != null) {
                shortcuts?.invokeMethod("open", action)
            } else {
                pendingShortcut = action
            }
        }
        super.onNewIntent(intent)
    }

    /** Shortcut links are ours: Flutter's own deep linking only gets the invite links. */
    override fun shouldHandleDeeplinking(): Boolean {
        if (intent?.data?.scheme == "nussnuss") return false
        return super.shouldHandleDeeplinking()
    }

    private fun shortcutOf(intent: Intent?): String? {
        val data = intent?.data ?: return null
        if (data.scheme != "nussnuss") return null
        return when (data.host) {
            "add" -> "add"
            "activity" -> "activity"
            else -> null
        }
    }

    // A java.util.function.Consumer (API 24+), kept untyped so older phones never load the class.
    private var blurListener: Any? = null
    private var contrastObserver: ContentObserver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        // The home-screen widget: the app sends the overall balance after each overview. The
        // trip calls are for the iPhone's Lock Screen; Android has nothing to do for them.
        MethodChannel(messenger, "nussnuss/widget").setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    NussNussWidget.save(
                        applicationContext,
                        call.argument<String>("title") ?: "",
                        call.argument<String>("amount") ?: "",
                        call.argument<String>("sub") ?: "",
                    )
                    result.success(null)
                }
                "startTrip", "updateTrip", "endTrip" -> result.success(null)
                else -> result.notImplemented()
            }
        }
        val shortcuts = MethodChannel(messenger, "nussnuss/shortcuts")
        shortcuts.setMethodCallHandler { call, result ->
            if (call.method == "initial") {
                shortcutsReady = true
                result.success(pendingShortcut)
                pendingShortcut = null
            } else {
                result.notImplemented()
            }
        }
        this.shortcuts = shortcuts
        MethodChannel(messenger, "nussnuss/accessibility").setMethodCallHandler { call, result ->
            if (call.method == "reduceTransparency") {
                result.success(reduceTransparency())
            } else {
                result.notImplemented()
            }
        }
        EventChannel(messenger, "nussnuss/accessibility/changes").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    sink = events
                    watch()
                    events.success(reduceTransparency())
                }

                override fun onCancel(arguments: Any?) {
                    unwatch()
                    sink = null
                }
            },
        )
    }

    override fun onDestroy() {
        unwatch()
        super.onDestroy()
    }

    /**
     * Android's nearest thing to Reduce Transparency: the system has turned window blur off (for
     * battery saver, or "Allow window-level blurs" off in the developer options), or high-contrast
     * text is on. The app's glass turns solid then.
     */
    private fun reduceTransparency(): Boolean {
        val noBlur = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            !windowManager.isCrossWindowBlurEnabled
        val highContrast =
            Settings.Secure.getInt(contentResolver, HIGH_TEXT_CONTRAST, 0) == 1
        return noBlur || highContrast
    }

    private fun send() {
        runOnUiThread { sink?.success(reduceTransparency()) }
    }

    private fun watch() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && blurListener == null) {
            val listener = java.util.function.Consumer<Boolean> { send() }
            windowManager.addCrossWindowBlurEnabledListener(mainExecutor, listener)
            blurListener = listener
        }
        if (contrastObserver == null) {
            val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
                override fun onChange(selfChange: Boolean) = send()
            }
            contentResolver.registerContentObserver(
                Settings.Secure.getUriFor(HIGH_TEXT_CONTRAST),
                false,
                observer,
            )
            contrastObserver = observer
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun unwatch() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (blurListener as? java.util.function.Consumer<Boolean>)?.let {
                windowManager.removeCrossWindowBlurEnabledListener(it)
            }
        }
        blurListener = null
        contrastObserver?.let { contentResolver.unregisterContentObserver(it) }
        contrastObserver = null
    }

    companion object {
        private const val HIGH_TEXT_CONTRAST = "high_text_contrast_enabled"
    }
}
