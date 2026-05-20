package com.example.second_brain

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import es.antonborri.home_widget.HomeWidgetLaunchIntent

class VaultSearchWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.vault_search_widget)

            // 1. Search text area clicks (launch app into Search screen)
            val searchIntent = HomeWidgetLaunchIntent.getActivity(
                context, 
                MainActivity::class.java, 
                Uri.parse("secondbrain://action/quick_ask")
            )
            views.setOnClickPendingIntent(R.id.search_input_area, searchIntent)

            // 2. Microphone icon clicks (launch app into voice chat screen)
            val voiceIntent = HomeWidgetLaunchIntent.getActivity(
                context, 
                MainActivity::class.java, 
                Uri.parse("secondbrain://action/voice")
            )
            views.setOnClickPendingIntent(R.id.btn_voice_search, voiceIntent)

            // 3. Main container click (open app normally)
            val appIntent = HomeWidgetLaunchIntent.getActivity(
                context, 
                MainActivity::class.java
            )
            views.setOnClickPendingIntent(R.id.search_widget_container, appIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
