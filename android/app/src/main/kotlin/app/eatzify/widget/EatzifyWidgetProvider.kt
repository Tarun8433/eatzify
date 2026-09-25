package app.eatzify.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import app.eatzify.MainActivity
import app.eatzify.R
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import java.text.NumberFormat

/**
 * Today, on the launcher (D-210) — the medium entry in the widget picker, and the class every widget
 * placed before D-219 is bound to, which is why it keeps this name.
 *
 * **It renders and nothing else.** Every figure was written by the Flutter side; the only arithmetic
 * here is how far along a progress bar is, exactly as on iOS. The 04:00 IST boundary has one
 * implementation (api/CLAUDE.md rule 4) and a launcher widget is not going to become the second.
 *
 * All three entries render the same way: the layout follows the widget's real size, so a small one
 * stretched to four by four shows the large layout.
 */
open class EatzifyWidgetProvider : AppWidgetProvider() {

    /** The layout to use before the launcher has reported a size. */
    protected open val defaultSize: SizeF = EatzifyWidgetRenderer.MEDIUM

    override fun onUpdate(context: Context, manager: AppWidgetManager, widgetIds: IntArray) {
        widgetIds.forEach { EatzifyWidgetRenderer.render(context, manager, it, defaultSize) }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        widgetId: Int,
        newOptions: Bundle,
    ) {
        EatzifyWidgetRenderer.render(context, manager, widgetId, defaultSize)
    }
}

/** Two by two: calories, steps and burned, and the glass button. */
class EatzifyWidgetSmall : EatzifyWidgetProvider() {
    override val defaultSize: SizeF = EatzifyWidgetRenderer.SMALL
}

/** Four by four: everything, with water against its own target. */
class EatzifyWidgetLarge : EatzifyWidgetProvider() {
    override val defaultSize: SizeF = EatzifyWidgetRenderer.LARGE
}

internal object EatzifyWidgetRenderer {
    /** The smallest size, in dp, each layout is drawn for. */
    val SMALL = SizeF(100f, 100f)
    val MEDIUM = SizeF(240f, 130f)
    val LARGE = SizeF(240f, 250f)

    private const val PROGRESS_MAX = 1000

    /** The "+" only. The water tile opens the day instead — seeing water is not adding to it. */
    private val WATER: Uri = Uri.parse("eatzify://water")
    private val TODAY: Uri = Uri.parse("eatzify://today")
    private val MEAL: Uri = Uri.parse("eatzify://meal")
    private val STEPS: Uri = Uri.parse("eatzify://steps")

    fun render(context: Context, manager: AppWidgetManager, widgetId: Int, fallback: SizeF) {
        val today = Today.load(context)
        val views = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12+: hand the launcher all three and let it pick for the space it has — which
            // it redoes on every resize without calling back.
            RemoteViews(
                mapOf(
                    SMALL to small(context, today),
                    MEDIUM to medium(context, today),
                    LARGE to large(context, today),
                ),
            )
        } else {
            forSize(sizeOf(manager.getAppWidgetOptions(widgetId)) ?: fallback, context, today)
        }
        manager.updateAppWidget(widgetId, views)
    }

    /** Portrait: the width is the narrower bound, the height the taller. Null before any is known. */
    private fun sizeOf(options: Bundle): SizeF? {
        val width = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
        val height = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT)
        return if (width == 0 || height == 0) null else SizeF(width.toFloat(), height.toFloat())
    }

    private fun forSize(size: SizeF, context: Context, today: Today): RemoteViews = when {
        size.fits(LARGE) -> large(context, today)
        size.fits(MEDIUM) -> medium(context, today)
        else -> small(context, today)
    }

    private fun SizeF.fits(layout: SizeF) = width >= layout.width && height >= layout.height

    private fun small(context: Context, t: Today) =
        RemoteViews(context.packageName, R.layout.eatzify_widget_small).apply {
            bindCalories(context, t, R.string.widget_of_kcal)
            setTextViewText(R.id.steps_value, t.show(t.steps))
            setTextViewText(R.id.burned_value, t.show(t.burnedKcal))
            setOnClickPendingIntent(R.id.add_water, addWater(context))
            // Too small for a target per figure: the rest of the card opens the app.
            setOnClickPendingIntent(android.R.id.background, open(context, null))
        }

    private fun medium(context: Context, t: Today) =
        RemoteViews(context.packageName, R.layout.eatzify_widget_medium).apply {
            bindCalories(context, t, R.string.widget_of_calories)
            // Water carries its target because the plan sets one; steps and burned have none, so
            // neither is shown against a goal nobody set.
            setTextViewText(
                R.id.water_value,
                if (t.waterMl != null && t.waterTargetMl != null) {
                    "${t.show(t.waterMl)}/${t.show(t.waterTargetMl)}"
                } else {
                    t.show(t.waterMl)
                },
            )
            setTextViewText(R.id.steps_value, t.show(t.steps))
            setTextViewText(R.id.burned_value, t.show(t.burnedKcal))
            bindTaps(context)
        }

    private fun large(context: Context, t: Today) =
        RemoteViews(context.packageName, R.layout.eatzify_widget_large).apply {
            bindCalories(context, t, R.string.widget_of_calories)
            setTextViewText(R.id.water_value, t.show(t.waterMl))
            setTextViewText(
                R.id.water_caption,
                t.waterTargetMl?.let { context.getString(R.string.widget_of_ml, t.show(it)) }
                    ?: context.getString(R.string.widget_ml_today),
            )
            // No target, no bar: a bar against nothing would be a comparison to zero.
            setViewVisibility(
                R.id.water_progress,
                if (t.waterTargetMl == null) View.GONE else View.VISIBLE,
            )
            setProgressBar(R.id.water_progress, PROGRESS_MAX, progress(t.waterMl, t.waterTargetMl), false)
            setTextViewText(R.id.steps_value, t.show(t.steps))
            setTextViewText(R.id.burned_value, t.show(t.burnedKcal))
            bindTaps(context)
        }

    /** The headline: what was eaten, against the plan when there is one. */
    private fun RemoteViews.bindCalories(context: Context, t: Today, ofTarget: Int) {
        setTextViewText(R.id.kcal_value, t.show(t.kcal))
        setTextViewText(
            R.id.kcal_caption,
            t.kcalTarget?.let { context.getString(ofTarget, t.show(it)) }
                ?: context.getString(R.string.widget_calories_today),
        )
        setProgressBar(R.id.kcal_progress, PROGRESS_MAX, progress(t.kcal, t.kcalTarget), false)
    }

    /**
     * Two kinds of tap, and the difference matters. The glass button uses a BACKGROUND intent — one
     * integer with one meaning, logged without the app coming to the front. Everything else opens
     * the app, because choosing a food is a screen rather than a button.
     */
    private fun RemoteViews.bindTaps(context: Context) {
        setOnClickPendingIntent(R.id.add_water, addWater(context))
        setOnClickPendingIntent(R.id.water_tile, open(context, TODAY))
        setOnClickPendingIntent(R.id.steps_tile, open(context, STEPS))
        // Burned comes from the same place steps do, and opens the same screen.
        setOnClickPendingIntent(R.id.burned_tile, open(context, STEPS))
        setOnClickPendingIntent(R.id.meal_tile, open(context, MEAL))
    }

    private fun progress(value: Int?, target: Int?): Int {
        if (value == null || target == null || target <= 0) return 0
        return (value.toLong() * PROGRESS_MAX / target).coerceIn(0, PROGRESS_MAX.toLong()).toInt()
    }

    private fun addWater(context: Context) = HomeWidgetBackgroundIntent.getBroadcast(context, WATER)

    private fun open(context: Context, uri: Uri?) =
        HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, uri)
}

/** Today, as the Flutter side wrote it. */
private data class Today(
    val waterMl: Int?,
    val waterTargetMl: Int?,
    val steps: Int?,
    val kcal: Int?,
    val kcalTarget: Int?,
    val burnedKcal: Int?,
) {
    private val numbers: NumberFormat = NumberFormat.getIntegerInstance()

    /** Grouped for the reader's locale, and an em dash for what nobody measured — never a zero. */
    fun show(value: Int?): String = value?.let(numbers::format) ?: "—"

    companion object {
        fun load(context: Context): Today {
            val data = HomeWidgetPlugin.getData(context)
            // Checked with `contains` because SharedPreferences has no nullable int, and a default
            // would turn "nobody measured" into "they drank nothing" (D-80). Dart removes the key
            // when it writes a null.
            fun read(key: String): Int? = if (data.contains(key)) data.getInt(key, 0) else null

            return Today(
                waterMl = read("water_ml"),
                waterTargetMl = read("water_target_ml"),
                steps = read("steps"),
                kcal = read("kcal"),
                kcalTarget = read("kcal_target"),
                burnedKcal = read("burned_kcal"),
            )
        }
    }
}
