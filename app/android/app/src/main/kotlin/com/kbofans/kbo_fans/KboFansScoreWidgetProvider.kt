package com.kbofans.kbo_fans

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class KboFansScoreWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.kbo_score_widget).apply {
                val pendingIntent =
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
                setOnClickPendingIntent(R.id.widget_container, pendingIntent)

                setTextViewText(
                    R.id.widget_title,
                    widgetData.getString("widget_title", "오늘 경기 없음") ?: "오늘 경기 없음",
                )
                setTextViewText(
                    R.id.widget_subtitle,
                    widgetData.getString("widget_subtitle", "KBO Fans") ?: "KBO Fans",
                )
                setTextViewText(
                    R.id.widget_status,
                    widgetData.getString("widget_status", "") ?: "",
                )
                setTextViewText(
                    R.id.widget_score,
                    widgetData.getString("widget_score", "") ?: "",
                )
                val batter = widgetData.getString("widget_batter", "") ?: ""
                val pitcher = widgetData.getString("widget_pitcher", "") ?: ""
                setTextViewText(R.id.widget_batter, batter)
                setTextViewText(R.id.widget_pitcher, pitcher)
                setViewVisibility(
                    R.id.widget_batter,
                    if (batter.isNotEmpty()) View.VISIBLE else View.GONE,
                )
                setViewVisibility(
                    R.id.widget_pitcher,
                    if (pitcher.isNotEmpty()) View.VISIBLE else View.GONE,
                )
                setTextViewText(
                    R.id.widget_updated_at,
                    "업데이트 ${widgetData.getString("widget_updated_at", "--:--") ?: "--:--"}",
                )
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
