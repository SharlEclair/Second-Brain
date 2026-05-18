package com.example.second_brain

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import es.antonborri.home_widget.HomeWidgetLaunchIntent

class FocusMissionWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        val title = widgetData.getString("focus_title", "Cortex Ingestion Online")
        val time = widgetData.getString("focus_time", "ACTIVE")
        
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.focus_mission_widget)
            views.setTextViewText(R.id.focus_title, title)
            views.setTextViewText(R.id.focus_time, time)

            // Click opens the app
            val appIntent = HomeWidgetLaunchIntent.getActivity(
                context, 
                MainActivity::class.java
            )
            views.setOnClickPendingIntent(R.id.focus_widget_container, appIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
