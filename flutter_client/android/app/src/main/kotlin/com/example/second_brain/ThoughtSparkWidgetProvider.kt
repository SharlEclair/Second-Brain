package com.example.second_brain

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import org.json.JSONArray

class ThoughtSparkWidgetProvider : HomeWidgetProvider() {

    companion object {
        const val ACTION_REFRESH_SPARK = "com.example.second_brain.ACTION_REFRESH_SPARK"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_REFRESH_SPARK) {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val sparksJson = prefs.getString("flutter.thought_sparks", "[]")
            
            try {
                val sparksArray = JSONArray(sparksJson)
                if (sparksArray.length() > 0) {
                    val currentIndex = prefs.getInt("flutter.thought_spark_index", 0)
                    val nextIndex = (currentIndex + 1) % sparksArray.length()
                    
                    // Save the next index back to SharedPreferences
                    prefs.edit().putInt("flutter.thought_spark_index", nextIndex).apply()
                    
                    // Trigger an update for the widget
                    val appWidgetManager = AppWidgetManager.getInstance(context)
                    val appWidgetIds = appWidgetManager.getAppWidgetIds(
                        android.content.ComponentName(context, ThoughtSparkWidgetProvider::class.java)
                    )
                    onUpdate(context, appWidgetManager, appWidgetIds)
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        } else {
            super.onReceive(context, intent)
        }
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        // Find current thought text
        val sparksJson = widgetData.getString("flutter.thought_sparks", "[]")
        var currentSpark = "Select 'Sync Vault' in Cortex to load insights from your ingested knowledge."
        
        try {
            val sparksArray = JSONArray(sparksJson)
            if (sparksArray.length() > 0) {
                val currentIndex = widgetData.getInt("flutter.thought_spark_index", 0)
                // Boundary check
                val safeIndex = if (currentIndex >= 0 && currentIndex < sparksArray.length()) currentIndex else 0
                currentSpark = sparksArray.getString(safeIndex)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }

        // Customizations
        val theme = widgetData.getString("widget_theme", "System") ?: "System"
        
        // Safely extract widget opacity float (which may be saved as a Double/String)
        var opacity = 0.9f
        try {
            if (widgetData.contains("widget_opacity")) {
                opacity = try {
                    widgetData.getFloat("widget_opacity", 0.9f)
                } catch (e: Exception) {
                    widgetData.getString("widget_opacity", "0.9")?.toFloatOrNull() ?: 0.9f
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }

        // Determine if Dark theme should be rendered
        var isDark = true
        if (theme == "Clean Lab Light") {
            isDark = false
        } else if (theme == "System") {
            val nightModeFlags = context.resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK
            isDark = nightModeFlags == android.content.res.Configuration.UI_MODE_NIGHT_YES
        }

        // Programmatic background color painting
        val baseColor = if (isDark) 0x0A0A0C else 0xFAFAFA
        val alpha = (opacity * 255).toInt().coerceIn(0, 255)
        val backgroundColor = (alpha shl 24) or (baseColor and 0x00FFFFFF)

        // Show/hide shortcut buttons toggles
        val showVoice = widgetData.getBoolean("widget_show_voice", true)
        val showClipboard = widgetData.getBoolean("widget_show_clipboard", true)
        val showScratchpad = widgetData.getBoolean("widget_show_scratchpad", true)

        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.thought_spark_widget)
            views.setTextViewText(R.id.thought_text, currentSpark)

            // Apply programmatic colors
            views.setInt(R.id.widget_container, "setBackgroundColor", backgroundColor)
            
            val textColor = if (isDark) 0xFFFFFFFF.toInt() else 0xFF0F172A.toInt()
            views.setTextColor(R.id.thought_text, textColor)

            // Apply buttons visibility
            views.setViewVisibility(R.id.btn_voice, if (showVoice) View.VISIBLE else View.GONE)
            views.setViewVisibility(R.id.btn_clipboard, if (showClipboard) View.VISIBLE else View.GONE)
            views.setViewVisibility(R.id.btn_scratchpad, if (showScratchpad) View.VISIBLE else View.GONE)

            // 1. Refresh click target (Broadcast to local receiver)
            val refreshIntent = Intent(context, ThoughtSparkWidgetProvider::class.java).apply {
                action = ACTION_REFRESH_SPARK
            }
            val refreshPendingIntent = PendingIntent.getBroadcast(
                context, 
                appWidgetId, 
                refreshIntent, 
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.btn_refresh, refreshPendingIntent)

            // 2. Voice Memo click intent
            val voiceIntent = HomeWidgetLaunchIntent.getActivity(
                context, 
                MainActivity::class.java, 
                Uri.parse("secondbrain://action/voice")
            )
            views.setOnClickPendingIntent(R.id.btn_voice, voiceIntent)

            // 3. Clipboard Ingest click intent
            val clipboardIntent = HomeWidgetLaunchIntent.getActivity(
                context, 
                MainActivity::class.java, 
                Uri.parse("secondbrain://action/clipboard")
            )
            views.setOnClickPendingIntent(R.id.btn_clipboard, clipboardIntent)

            // 4. Scratchpad click intent
            val scratchpadIntent = HomeWidgetLaunchIntent.getActivity(
                context, 
                MainActivity::class.java, 
                Uri.parse("secondbrain://action/scratchpad")
            )
            views.setOnClickPendingIntent(R.id.btn_scratchpad, scratchpadIntent)

            // 5. Container click opens full app normally
            val appIntent = HomeWidgetLaunchIntent.getActivity(
                context, 
                MainActivity::class.java
            )
            views.setOnClickPendingIntent(R.id.widget_container, appIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
