package com.example.second_brain

import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import org.json.JSONArray
import android.util.Log

class CortexAgendaWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return CortexAgendaWidgetFactory(applicationContext, intent)
    }
}

class CortexAgendaWidgetFactory(private val context: Context, intent: Intent) : RemoteViewsService.RemoteViewsFactory {

    private var agendaItems: List<AgendaItem> = ArrayList()

    data class AgendaItem(val title: String, val date: String, val category: String)

    override fun onCreate() {
        loadAgendaData()
    }

    override fun onDataSetChanged() {
        loadAgendaData()
    }

    private fun loadAgendaData() {
        val items = ArrayList<AgendaItem>()
        try {
            // Retrieve agenda_data JSON from FlutterSharedPreferences
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val jsonString = prefs.getString("flutter.agenda_data", "[]") ?: "[]"
            
            val jsonArray = JSONArray(jsonString)
            for (i in 0 until jsonArray.length()) {
                val obj = jsonArray.getJSONObject(i)
                val title = obj.optString("title", "No Title")
                val date = obj.optString("date", "")
                val category = obj.optString("category", "GENERAL")
                items.add(AgendaItem(title, date, category))
            }
        } catch (e: Exception) {
            Log.e("CortexAgendaWidget", "Failed to parse agenda JSON", e)
        }
        agendaItems = items
    }

    override fun onDestroy() {
        // Clear resources
    }

    override fun getCount(): Int {
        return agendaItems.size
    }

    override fun getViewAt(position: Int): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_agenda_item)
        if (position >= agendaItems.size) return views

        val item = agendaItems[position]
        views.setTextViewText(R.id.item_title, item.title)
        views.setTextViewText(R.id.item_date, item.date)
        views.setTextViewText(R.id.item_category, item.category.uppercase())

        // Set a fill-in intent so clicking the item opens the app
        val fillInIntent = Intent()
        views.setOnClickFillInIntent(R.id.item_title, fillInIntent)

        return views
    }

    override fun getLoadingView(): RemoteViews? {
        return null
    }

    override fun getViewTypeCount(): Int {
        return 1
    }

    override fun getItemId(position: Int): Long {
        return position.toLong()
    }

    override fun hasStableIds(): Boolean {
        return true
    }
}
