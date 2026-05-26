package com.example.second_brain

import android.content.Intent
import android.widget.RemoteViewsService

class AgendaRemoteViewsService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return AgendaRemoteViewsFactory(applicationContext, intent)
    }
}
