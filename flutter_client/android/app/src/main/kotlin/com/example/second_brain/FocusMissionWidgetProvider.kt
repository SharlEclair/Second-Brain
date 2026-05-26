package com.example.second_brain

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import android.widget.Toast
import es.antonborri.home_widget.HomeWidgetProvider
import es.antonborri.home_widget.HomeWidgetLaunchIntent

class FocusMissionWidgetProvider : HomeWidgetProvider() {

    companion object {
        const val ACTION_COMPLETE_MISSION = "com.example.second_brain.ACTION_COMPLETE_MISSION"
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_COMPLETE_MISSION) {
            Log.d("FocusMissionWidget", "Received ACTION_COMPLETE_MISSION")
            
            // 1. Update visual state in preferences
            val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            prefs.edit()
                .putString("focus_time", "COMPLETED!")
                .putString("focus_title", "Focus Mission Accomplished")
                .apply()
                
            // 2. Trigger Widget Redraw
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val thisAppWidget = ComponentName(context.packageName, FocusMissionWidgetProvider::class.java.name)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(thisAppWidget)
            onUpdate(context, appWidgetManager, appWidgetIds, prefs)
            
            // 3. Show dynamic feedback toast
            Toast.makeText(context, "🎯 Focus Mission Completed!", Toast.LENGTH_SHORT).show()

            // 4. Fire API call to compile in background
            val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val baseUrl = flutterPrefs.getString("flutter.base_url", null)
            if (!baseUrl.isNullOrEmpty()) {
                val cleanUrl = baseUrl.trim().removeSuffix("/")
                Thread {
                    try {
                        val url = java.net.URL("$cleanUrl/api/compile")
                        val conn = url.openConnection() as java.net.HttpURLConnection
                        conn.requestMethod = "POST"
                        conn.setRequestProperty("Content-Type", "application/json")
                        conn.setRequestProperty("ngrok-skip-browser-warning", "true")
                        conn.connectTimeout = 15000
                        conn.readTimeout = 15000
                        conn.doOutput = true
                        conn.outputStream.use { os ->
                            os.write("{}".toByteArray())
                        }
                        val responseCode = conn.responseCode
                        Log.d("FocusMissionWidget", "Background Compile response: $responseCode")
                    } catch (e: Exception) {
                        Log.e("FocusMissionWidget", "Error during background compilation", e)
                    }
                }.start()
            }
        }
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        val title = widgetData.getString("focus_title", "Cortex Ingestion Online")
        val time = widgetData.getString("focus_time", "ACTIVE")
        
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
        
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.focus_mission_widget)
            views.setTextViewText(R.id.focus_title, title)
            views.setTextViewText(R.id.focus_time, time)

            // Apply programmatic colors
            views.setInt(R.id.focus_widget_container, "setBackgroundColor", backgroundColor)
            
            val textColor = if (isDark) 0xFFFFFFFF.toInt() else 0xFF0F172A.toInt()
            val subColor = if (isDark) 0x88FFFFFF.toInt() else 0x880F172A.toInt()
            views.setTextColor(R.id.focus_time, textColor)
            views.setTextColor(R.id.focus_title, subColor)

            // Click opens the app
            val appIntent = HomeWidgetLaunchIntent.getActivity(
                context, 
                MainActivity::class.java
            )
            views.setOnClickPendingIntent(R.id.focus_widget_container, appIntent)

            // Done checkmark click listener (broadcasts explicit intent to this class)
            val completeIntent = Intent(context, FocusMissionWidgetProvider::class.java).apply {
                action = ACTION_COMPLETE_MISSION
            }
            val completePendingIntent = PendingIntent.getBroadcast(
                context,
                appWidgetId,
                completeIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.btn_complete_mission, completePendingIntent)

            // Hide/Show Done button based on state
            if (time == "COMPLETED!") {
                views.setViewVisibility(R.id.btn_complete_mission, View.GONE)
            } else {
                views.setViewVisibility(R.id.btn_complete_mission, View.VISIBLE)
            }

            // Set Remote Views Service for Scrollable Agenda ListView
            val serviceIntent = Intent(context, AgendaRemoteViewsService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
            }
            views.setRemoteAdapter(R.id.agenda_list, serviceIntent)
            views.setEmptyView(R.id.agenda_list, R.id.agenda_empty_view)

            // Setup click template intent for list item clicks to launch main app
            val clickIntentTemplate = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java
            )
            views.setPendingIntentTemplate(R.id.agenda_list, clickIntentTemplate)

            appWidgetManager.updateAppWidget(appWidgetId, views)
            appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.agenda_list)
        }
    }
}
