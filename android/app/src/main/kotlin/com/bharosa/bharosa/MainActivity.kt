package com.bharosa.bharosa

import android.view.WindowManager
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.bharosa.app/screen_protector"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "enableSecure" -> {
                    runOnUiThread {
                        window.setFlags(
                            WindowManager.LayoutParams.FLAG_SECURE,
                            WindowManager.LayoutParams.FLAG_SECURE
                        )
                    }
                    result.success(true)
                }
                "disableSecure" -> {
                    runOnUiThread {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(true)
                }
                "getDeviceId" -> {
                    try {
                        @android.annotation.SuppressLint("HardwareIds")
                        val androidId = android.provider.Settings.Secure.getString(
                            contentResolver,
                            android.provider.Settings.Secure.ANDROID_ID
                        )
                        result.success(androidId ?: "")
                    } catch (e: Exception) {
                        result.error("DEVICE_ID_ERROR", e.localizedMessage, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
