package app.nussnuss.nussnuss

import android.database.ContentObserver
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var sink: EventChannel.EventSink? = null

    // A java.util.function.Consumer (API 24+), kept untyped so older phones never load the class.
    private var blurListener: Any? = null
    private var contrastObserver: ContentObserver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
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
