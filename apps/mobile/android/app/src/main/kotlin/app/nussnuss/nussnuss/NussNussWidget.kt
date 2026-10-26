package app.nussnuss.nussnuss

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * The home-screen balance widget: "Your balance", the main currency's amount ("AED 110.00") and
 * "You get back" or "You owe". When everything is even the app sends no amount, and the widget
 * says "All settled" in the big line. The app saves the three lines after each overview
 * (MethodChannel "nussnuss/widget" "update"); tapping the widget opens the app.
 */
class NussNussWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) manager.updateAppWidget(id, views(context))
    }

    companion object {
        private const val PREFS = "nussnuss_widget"

        /** Keeps the lines the app sent and redraws every widget on the home screen. */
        fun save(context: Context, title: String, amount: String, sub: String) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putString("title", title)
                .putString("amount", amount)
                .putString("sub", sub)
                .apply()
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, NussNussWidget::class.java))
            for (id in ids) manager.updateAppWidget(id, views(context))
        }

        private fun views(context: Context): RemoteViews {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val views = RemoteViews(context.packageName, R.layout.nussnuss_widget)
            val title = prefs.getString("title", null)
            val amount = prefs.getString("amount", null)
            val sub = prefs.getString("sub", null)
            views.setTextViewText(
                R.id.widget_title,
                if (title.isNullOrEmpty()) context.getString(R.string.widget_name) else title,
            )
            if (amount.isNullOrEmpty()) {
                // Even (or not opened yet): one line says so, without repeating it underneath.
                views.setTextViewText(
                    R.id.widget_amount,
                    if (sub.isNullOrEmpty()) context.getString(R.string.widget_empty) else sub,
                )
                views.setTextViewText(R.id.widget_sub, "")
            } else {
                views.setTextViewText(R.id.widget_amount, amount)
                views.setTextViewText(R.id.widget_sub, sub ?: "")
            }
            val open = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            views.setOnClickPendingIntent(
                R.id.widget_root,
                PendingIntent.getActivity(
                    context,
                    0,
                    open,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            )
            return views
        }
    }
}
