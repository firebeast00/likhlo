package com.example.likhlo

import android.content.Context
import android.content.Intent
import android.media.AudioManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterFragmentActivity() {
    private val CHANNEL = "com.likhlo/quick_tile"
    private val AUDIO_CHANNEL = "com.likhlo/audio_feedback"
    private var quickAction: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        quickAction = intent.getStringExtra("quick_action")

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getQuickAction") {
                result.success(quickAction)
                quickAction = null
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "isDeviceSilent") {
                val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                result.success(audioManager.ringerMode != AudioManager.RINGER_MODE_NORMAL)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        val action = intent.getStringExtra("quick_action")
        if (action != null) {
            flutterEngine?.dartExecutor?.binaryMessenger?.let {
                MethodChannel(it, CHANNEL).invokeMethod("triggerAction", action)
            }
        }
    }
}
