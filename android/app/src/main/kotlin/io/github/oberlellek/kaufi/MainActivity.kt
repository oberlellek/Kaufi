package io.github.oberlellek.kaufi

import android.content.Intent
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hands plans from other apps to Flutter: "Teilen -> Kaufi" (text or a file)
 * and opening a .json file with Kaufi. Flutter asks for the launch intent once
 * via "takePendingImport"; later intents are pushed via "importText".
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var launchIntentHandled = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kaufi/import").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "takePendingImport" -> {
                        val text = if (launchIntentHandled) null else readImport(intent)
                        launchIntentHandled = true
                        result.success(text)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        readImport(intent)?.let { channel?.invokeMethod("importText", it) }
    }

    private fun readImport(intent: Intent?): String? {
        if (intent == null) return null
        return try {
            when (intent.action) {
                Intent.ACTION_SEND ->
                    intent.getStringExtra(Intent.EXTRA_TEXT) ?: streamUri(intent)?.let(::readUri)
                Intent.ACTION_VIEW -> intent.data?.let(::readUri)
                else -> null
            }
        } catch (e: Exception) {
            null
        }
    }

    @Suppress("DEPRECATION")
    private fun streamUri(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }

    private fun readUri(uri: Uri): String? =
        contentResolver.openInputStream(uri)?.use { input ->
            // A meal plan is a few kilobytes; refuse anything absurdly large.
            val bytes = input.readBytes()
            if (bytes.size > MAX_IMPORT_BYTES) null else bytes.toString(Charsets.UTF_8)
        }

    companion object {
        private const val MAX_IMPORT_BYTES = 2 * 1024 * 1024
    }
}
