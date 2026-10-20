/*
 * The glass shader (res/raw/liquidglass_effect.agsl) and the refraction technique come from
 * AndroidLiquidGlassView (https://github.com/QmDeve/AndroidLiquidGlassView).
 * MIT License, Copyright (c) 2025-2026 Donny Yang. Full text: Android/third_party/liquidglass/LICENSE.
 */
package app.zelefin.client.ui

import android.content.Context
import android.graphics.RenderEffect
import android.graphics.RuntimeShader
import android.graphics.Shader
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.annotation.RequiresApi
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.asComposeRenderEffect
import androidx.compose.ui.graphics.drawOutline
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.layer.GraphicsLayer
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import app.zelefin.client.AppTab
import app.zelefin.client.R
import java.util.concurrent.ConcurrentLinkedQueue
import kotlin.math.roundToInt

/**
 * The page the glass refracts. The page records itself into [layer] as it draws, and every
 * pane draws that same layer through the shader, so nothing is drawn twice by hand. The glass
 * must sit outside the page, or the page would record the glass into itself.
 */
@Stable
class GlassSource {
    internal var layer: GraphicsLayer? by mutableStateOf(null)
    internal var origin by mutableStateOf(Offset.Zero)
}

val LocalGlassSource = staticCompositionLocalOf<GlassSource?> { null }

/** Dark tab bar glass: a refracting lens edge, optional frost, and a tint so labels read. */
data class GlassStyle(
    val refractionHeight: Dp = 16.dp,
    val refractionOffset: Dp = 44.dp,
    val blur: Dp = 0.dp,
    val dispersion: Float = 0.3f,
    val saturation: Float = 1.2f,
    val tint: Color = Color(0xFF16161A),
    val tintAlpha: Float = 0.18f,
    /** Below Android 13 there is no RuntimeShader; a frosted dark fill stands in. */
    val fallbackFill: Color = Color(0xD91C1C1E),
)

/** iOS 26.1 Settings → Display & Brightness → Liquid Glass, plus Off and the adjuster's Custom. */
enum class GlassMode(val raw: String, val title: String, val preset: GlassStyle?) {
    Clear(
        "clear",
        "Clear",
        GlassStyle(),
    ),
    Tinted(
        "tinted",
        "Tinted",
        GlassStyle(
            blur = 3.dp,
            dispersion = 0.2f,
            saturation = 1.3f,
            tintAlpha = 0.58f,
            fallbackFill = Color(0xF71C1C1E),
        ),
    ),

    /** Set from the Liquid Glass adjuster's sliders. */
    Custom("custom", "Custom", null),

    /** No live refraction at all — a static frosted bar. The cheapest option; always smooth. */
    Off(
        "off",
        "Off",
        GlassStyle(fallbackFill = Color(0xF21C1C1E)),
    ),
}

/** The adjuster's sliders and their ranges. Refraction ranges follow the library's limits. */
enum class GlassKnob(val title: String, val range: ClosedFloatingPointRange<Float>) {
    Frost("Frost", 0f..10f),
    Darkness("Darkness", 0f..0.85f),
    Refraction("Refraction", 20f..120f),
    EdgeWidth("Edge Width", 12f..50f),
    ColorFringe("Color Fringe", 0f..1f),
    Vibrance("Vibrance", 0.6f..2f),
    ;

    fun read(style: GlassStyle): Float = when (this) {
        Frost -> style.blur.value
        Darkness -> style.tintAlpha
        Refraction -> style.refractionOffset.value
        EdgeWidth -> style.refractionHeight.value
        ColorFringe -> style.dispersion
        Vibrance -> style.saturation
    }

    fun write(style: GlassStyle, value: Float): GlassStyle {
        val v = value.coerceIn(range)
        return when (this) {
            Frost -> style.copy(blur = v.dp)
            Darkness -> style.copy(tintAlpha = v, fallbackFill = fallbackFor(v))
            Refraction -> style.copy(refractionOffset = v.dp)
            EdgeWidth -> style.copy(refractionHeight = v.dp)
            ColorFringe -> style.copy(dispersion = v)
            Vibrance -> style.copy(saturation = v)
        }
    }

    fun label(value: Float): String = when (this) {
        Frost, Refraction, EdgeWidth -> "${value.roundToInt()}"
        Darkness, ColorFringe -> "${(value * 100).roundToInt()}%"
        Vibrance -> "%.1f×".format(value)
    }

    private companion object {
        /** Older Androids show a solid fill; darker glass gets a more opaque one. */
        fun fallbackFor(tintAlpha: Float) = Color(0xFF1C1C1E).copy(alpha = 0.82f + 0.17f * (tintAlpha / 0.85f))
    }
}

object GlassPreferences {
    var mode by mutableStateOf(GlassMode.Clear)
        private set
    var custom by mutableStateOf(GlassStyle())
        private set

    val style: GlassStyle get() = mode.preset ?: custom

    fun load(context: Context) {
        val prefs = prefs(context)
        val raw = prefs.getString(KEY, null)
        mode = GlassMode.entries.firstOrNull { it.raw == raw } ?: GlassMode.Clear
        custom = GlassKnob.entries.fold(GlassStyle()) { style, knob ->
            if (prefs.contains(knobKey(knob))) knob.write(style, prefs.getFloat(knobKey(knob), knob.read(style))) else style
        }
    }

    fun setMode(context: Context, next: GlassMode) {
        mode = next
        prefs(context).edit().putString(KEY, next.raw).apply()
    }

    /** Moving a slider starts from the look on screen (Clear if glass was Off) and switches to Custom. */
    fun adjust(context: Context, knob: GlassKnob, value: Float) {
        val base = if (mode == GlassMode.Off) GlassMode.Clear.preset!! else style
        custom = knob.write(base, value)
        mode = GlassMode.Custom
        val edit = prefs(context).edit().putString(KEY, GlassMode.Custom.raw)
        GlassKnob.entries.forEach { edit.putFloat(knobKey(it), it.read(custom)) }
        edit.apply()
    }

    /** Drops the custom slider values and goes back to Clear, the default look. */
    fun resetCustom(context: Context) {
        custom = GlassStyle()
        mode = GlassMode.Clear
        val edit = prefs(context).edit().putString(KEY, GlassMode.Clear.raw)
        GlassKnob.entries.forEach { edit.remove(knobKey(it)) }
        edit.apply()
    }

    private fun knobKey(knob: GlassKnob) = "$KEY.${knob.name.lowercase()}"

    private fun prefs(context: Context) = context.getSharedPreferences("zelefin.interface", Context.MODE_PRIVATE)

    private const val KEY = "zelefin.liquid-glass"
}

/**
 * A glass bar over [backdrop] for the adjuster. It samples its own backdrop, since Settings
 * sits over the page and the dock is hidden there.
 */
@Composable
fun LiquidGlassPreview(modifier: Modifier = Modifier, backdrop: @Composable () -> Unit) {
    val preview = remember { GlassSource() }
    Box(modifier.clip(RoundedCornerShape(16.dp))) {
        Box(Modifier.matchParentSize().glassSource(preview)) {
            Box(
                Modifier
                    .matchParentSize()
                    .background(Brush.linearGradient(listOf(Color(0xFF2AD4FC), Color(0xFF7B5CFF), Color(0xFFFF8A3D)))),
            )
            backdrop()
        }
        CompositionLocalProvider(LocalGlassSource provides preview) {
            Box(
                Modifier
                    .align(Alignment.BottomCenter)
                    .padding(horizontal = 20.dp, vertical = 16.dp)
                    .fillMaxWidth()
                    .height(56.dp),
            ) {
                LiquidGlassPane(28.dp, Modifier.matchParentSize())
                Row(
                    Modifier.matchParentSize(),
                    horizontalArrangement = Arrangement.SpaceEvenly,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    listOf(AppTab.Home, AppTab.Movies, AppTab.Shows, AppTab.Library).forEachIndexed { index, tab ->
                        DockTabIcon(
                            tab,
                            selected = index == 0,
                            description = null,
                            tint = if (index == 0) ZelefinCyan else Color.White,
                            modifier = Modifier.size(22.dp),
                        )
                    }
                }
            }
        }
    }
}

internal val GlassRim = Brush.verticalGradient(
    listOf(Color.White.copy(alpha = 0.22f), Color.White.copy(alpha = 0.06f)),
)

/**
 * A RuntimeShader compiles its AGSL when it is built, and launch is the busiest moment on the
 * main thread. The shaders are built on a background thread instead, and panes show the frosted
 * fallback until they and the first screen are ready.
 */
object GlassShaders {
    private const val PREBUILT = 4
    private const val SETTLE_MILLIS = 700L
    private val pool = ConcurrentLinkedQueue<RuntimeShader>()
    private var source: String? = null
    private var started = false

    var ready by mutableStateOf(false)
        private set

    fun warmUp(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || started) return
        started = true
        val app = context.applicationContext
        val startedAt = SystemClock.uptimeMillis()
        Thread({
            val code = shaderSource(app)
            repeat(PREBUILT) { pool.add(RuntimeShader(code)) }
            val wait = (SETTLE_MILLIS - (SystemClock.uptimeMillis() - startedAt)).coerceAtLeast(0L)
            Handler(Looper.getMainLooper()).postDelayed({ ready = true }, wait)
        }, "zelefin-glass-warmup").apply { isDaemon = true }.start()
    }

    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    internal fun take(context: Context): RuntimeShader = pool.poll() ?: RuntimeShader(shaderSource(context))

    private fun shaderSource(context: Context): String = source
        ?: context.resources.openRawResource(R.raw.liquidglass_effect).bufferedReader().use { it.readText() }
            .also { source = it }
}

/** Marks the page content the dock and mini player glass refract. */
@Composable
fun Modifier.glassSource(source: GlassSource): Modifier {
    val layer = rememberGraphicsLayer()
    DisposableEffect(source, layer) {
        source.layer = layer
        onDispose { if (source.layer === layer) source.layer = null }
    }
    // Only capture the screen into the layer when the glass is actually live (shader supported and
    // not turned Off); otherwise draw straight to the screen and skip the cost.
    val live = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && GlassPreferences.mode != GlassMode.Off
    return this
        .onGloballyPositioned { source.origin = it.positionInRoot() }
        .drawWithContent {
            if (live) {
                layer.record { this@drawWithContent.drawContent() }
                drawLayer(layer)
            } else {
                drawContent()
            }
        }
}

/**
 * A rounded glass pane over whatever [LocalGlassSource] shows behind it. Callers draw their
 * controls in a sibling on top.
 */
@Composable
fun LiquidGlassPane(
    cornerRadius: Dp,
    modifier: Modifier = Modifier,
    style: GlassStyle = GlassPreferences.style,
) {
    val paneShape = RoundedCornerShape(cornerRadius)
    val source = LocalGlassSource.current
    val sourceLayer = source?.layer
    val supported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && source != null && sourceLayer != null
    // Live glass unless the user has turned it off; then the static frosted fill stands in.
    val live = supported && GlassShaders.ready && GlassPreferences.mode != GlassMode.Off
    val glassAlpha by animateFloatAsState(
        targetValue = if (live) 1f else 0f,
        animationSpec = tween(220),
        label = "glassIn",
    )
    Box(modifier) {
        if (glassAlpha < 1f) {
            Box(Modifier.matchParentSize().clip(paneShape).background(style.fallbackFill))
        }
        if (supported && GlassShaders.ready && source != null && sourceLayer != null) {
            val context = LocalContext.current
            val glass = remember { GlassEffect(context) }
            var origin by remember { mutableStateOf(Offset.Zero) }
            var size by remember { mutableStateOf(IntSize.Zero) }
            Box(
                Modifier
                    .matchParentSize()
                    .onGloballyPositioned {
                        origin = it.positionInRoot()
                        size = it.size
                    }
                    .graphicsLayer {
                        alpha = glassAlpha
                        renderEffect = glass.effect(
                            size = size,
                            cornerRadius = cornerRadius.toPx(),
                            refractionHeight = style.refractionHeight.toPx(),
                            refractionOffset = style.refractionOffset.toPx(),
                            blur = style.blur.toPx(),
                            style = style,
                        )
                        shape = paneShape
                        clip = true
                    }
                    .drawBehind {
                        val offset = source.origin - origin
                        translate(offset.x, offset.y) { drawLayer(sourceLayer) }
                    },
            )
        }
        Box(Modifier.matchParentSize().border(0.75.dp, GlassRim, paneShape))
    }
}

/**
 * Liquid glass behind this element's content, for surfaces of any shape (menus, alerts). Uses a
 * heavier frost and tint than the dock so text on it stays readable, like iOS menus. Without a
 * live source (inside the page, Off, or below Android 13) it draws [fallback].
 */
@Composable
fun Modifier.zelefinLiquidGlassBackground(
    shape: Shape,
    fallback: Color,
    style: GlassStyle = GlassPreferences.style.let { base ->
        base.copy(blur = maxOf(base.blur, 14.dp), tintAlpha = maxOf(base.tintAlpha, 0.55f))
    },
    /** Draw the glass rim on [fallback] too, so a tinted stand-in still reads as glass. */
    rimOnFallback: Boolean = false,
): Modifier {
    val source = LocalGlassSource.current
    val sourceLayer = source?.layer
    val live = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && source != null && sourceLayer != null &&
        GlassShaders.ready && GlassPreferences.mode != GlassMode.Off
    if (!live || source == null || sourceLayer == null) {
        val filled = this.background(fallback, shape)
        return if (rimOnFallback) filled.border(0.75.dp, GlassRim, shape) else filled
    }
    val context = LocalContext.current
    val glass = remember { GlassEffect(context) }
    val glassLayer = rememberGraphicsLayer()
    var origin by remember { mutableStateOf(Offset.Zero) }
    return this
        .onGloballyPositioned { origin = it.positionInRoot() }
        .drawWithContent {
            val outline = shape.createOutline(size, layoutDirection, this)
            val radius = (outline as? Outline.Rounded)?.roundRect?.topLeftCornerRadius?.x ?: 0f
            glassLayer.renderEffect = glass.effect(
                size = IntSize(size.width.roundToInt(), size.height.roundToInt()),
                cornerRadius = radius,
                refractionHeight = style.refractionHeight.toPx(),
                refractionOffset = style.refractionOffset.toPx(),
                blur = style.blur.toPx(),
                style = style,
            )
            glassLayer.record {
                val offset = source.origin - origin
                translate(offset.x, offset.y) { drawLayer(sourceLayer) }
            }
            drawLayer(glassLayer)
            drawOutline(outline, GlassRim, style = Stroke(0.75.dp.toPx()))
            drawContent()
        }
}

/** The shader effect for one pane, rebuilt only when its size or shape changes. */
@RequiresApi(Build.VERSION_CODES.TIRAMISU)
private class GlassEffect(context: Context) {
    private val shader = GlassShaders.take(context)
    private var key: List<Any>? = null
    private var cached: androidx.compose.ui.graphics.RenderEffect? = null

    fun effect(
        size: IntSize,
        cornerRadius: Float,
        refractionHeight: Float,
        refractionOffset: Float,
        blur: Float,
        style: GlassStyle,
    ): androidx.compose.ui.graphics.RenderEffect? {
        if (size.width <= 0 || size.height <= 0) return null
        val next = listOf(size, cornerRadius, refractionHeight, refractionOffset, blur, style)
        if (next == key) return cached
        key = next
        val width = size.width.toFloat()
        val height = size.height.toFloat()
        val half = minOf(width, height) / 2f
        val radius = cornerRadius.coerceIn(0f, half)
        shader.setFloatUniform("size", width, height)
        shader.setFloatUniform("offset", 0f, 0f)
        shader.setFloatUniform("cornerRadii", radius, radius, radius, radius)
        shader.setFloatUniform("refractionHeight", refractionHeight.coerceIn(1f, half.coerceAtLeast(1f)))
        // The shader bends inward for a negative amount, the same sign the library passes.
        shader.setFloatUniform("refractionAmount", -refractionOffset)
        shader.setFloatUniform("depthEffect", 0.3f)
        shader.setFloatUniform("chromaticAberration", style.dispersion)
        shader.setFloatUniform("contrast", 0f)
        shader.setFloatUniform("whitePoint", 0f)
        shader.setFloatUniform("chromaMultiplier", style.saturation)
        shader.setFloatUniform("tintColor", style.tint.red, style.tint.green, style.tint.blue)
        shader.setFloatUniform("tintAlpha", style.tintAlpha)
        val glass = RenderEffect.createRuntimeShaderEffect(shader, "content")
        val effect = if (blur > 0.5f) {
            RenderEffect.createChainEffect(glass, RenderEffect.createBlurEffect(blur, blur, Shader.TileMode.CLAMP))
        } else {
            glass
        }
        return effect.asComposeRenderEffect().also { cached = it }
    }
}
