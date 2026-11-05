package com.hati.hati

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // "Open GCash" and friends (DECISIONS D-62): launch the wallet by its
        // package name, exactly as its home-screen icon would. More reliable
        // than URL schemes, which wallets change and do not document.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hati/wallets")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "open" -> {
                        val pkg = call.argument<String>("package")
                        val intent = pkg?.let { packageManager.getLaunchIntentForPackage(it) }
                        if (intent == null) {
                            // Not installed, or hidden by a missing <queries> entry.
                            result.success(false)
                        } else {
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
