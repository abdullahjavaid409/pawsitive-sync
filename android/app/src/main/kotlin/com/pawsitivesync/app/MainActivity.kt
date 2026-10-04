package com.pawsitivesync.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var clockChannel: MethodChannel? = null

    /**
     * The user changed the clock or the time zone while the app is alive:
     * Dart re-plans reminders (`pawsitive_sync/clock`). When the app is not
     * running, the next launch/resume and the periodic WorkManager job
     * re-plan instead; scheduled alarms survive either way.
     */
    private val clockReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            clockChannel?.invokeMethod("changed", intent.action ?: "android_time_changed")
        }
    }
    private var clockRegistered = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        clockChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pawsitive_sync/clock")
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_TIME_CHANGED)
            addAction(Intent.ACTION_TIMEZONE_CHANGED)
        }
        // System broadcasts only; exported so the OS can always deliver them.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(clockReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            registerReceiver(clockReceiver, filter)
        }
        clockRegistered = true
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        if (clockRegistered) {
            unregisterReceiver(clockReceiver)
            clockRegistered = false
        }
        clockChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
