package com.example.second_brain

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import es.antonborri.home_widget.HomeWidgetLaunchIntent

class CortexAgendaWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        // Theme & opacity settings
        val theme = widgetData.getString("widget_theme", "System") ?: "System"
        
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

        var isDark = true
        if (theme == "Clean Lab Light") {
            isDark = false
        } else if (theme == "System") {
            val nightModeFlags = context.resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK
            isDark = nightModeFlags == android.content.res.Configuration.UI_MODE_NIGHT_YES
        }

        val baseColor = if (isDark) 0x0A0A0C else 0xFAFAFA
        val alpha = (opacity * 255).toInt().coerceIn(0, 255)
        val backgroundColor = (alpha shl 24) or (baseColor and 0x00FFFFFF)

        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_agenda_layout)
            
            // Set Remote Views Service
            val intent = Intent(context, CortexAgendaWidgetService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
            }
            views.setRemoteAdapter(R.id.agenda_list, intent)
            views.setEmptyView(R.id.agenda_list, R.id.agenda_empty_view)

            // Apply background color
            views.setInt(R.id.agenda_widget_container, "setBackgroundColor", backgroundColor)
            
            // Launch app intent when clicking the header
            val appIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java
            )
            views.setOnClickPendingIntent(R.id.agenda_header, appIntent)

            // Dynamic item click template
            val clickIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java
            )
            views.setPendingIntentTemplate(R.id.agenda_list, clickIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
            appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.agenda_list)
        }
    }
}
