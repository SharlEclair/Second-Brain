package com.example.second_brain

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.second_brain/actions"
    private var pendingAction: String? = null
    private var channelInstance: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        val uri = intent?.data
        if (uri != null && uri.scheme == "secondbrain") {
            // E.g. scheme "secondbrain" and host "action", path "/voice"
            val host = uri.host ?: ""
            val path = uri.path ?: ""
            val fullAction = if (path.isNotEmpty()) "$host$path" else host
            
            pendingAction = fullAction
            sendPendingAction()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channelInstance = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channelInstance?.setMethodCallHandler { call, result ->
            if (call.method == "getPendingAction") {
                result.success(pendingAction)
                pendingAction = null
            } else {
                result.notImplemented()
            }
        }
        
        // If we have a pending action, send it immediately
        sendPendingAction()
    }

    private fun sendPendingAction() {
        val action = pendingAction
        val channel = channelInstance
        if (action != null && channel != null) {
            channel.invokeMethod("triggerAction", action)
            pendingAction = null
        }
    }
}
