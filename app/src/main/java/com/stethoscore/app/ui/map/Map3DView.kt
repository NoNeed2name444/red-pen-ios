package com.stethoscore.app.ui.map

import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import android.content.ContextWrapper
import android.opengl.GLSurfaceView
import android.os.Build
import android.view.Choreographer
import android.view.Display
import android.view.Surface
import android.view.SurfaceHolder
import android.view.WindowManager
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculateCentroid
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.CenterFocusStrong
import androidx.compose.material.icons.rounded.Remove
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.foundation.layout.Row
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalViewConfiguration
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.stethoscore.app.map.DisplayModeInfo
import com.stethoscore.app.map.MapGraph
import com.stethoscore.app.map.Octree
import com.stethoscore.app.map.OrbitCamera
import com.stethoscore.app.map.RefreshRate
import com.stethoscore.app.map.Vec3
import com.stethoscore.app.map.grouped
import java.util.Locale
import kotlin.math.cbrt
import kotlin.math.max

/** A map ready to draw: its octree, how big a node is, and the notes behind the nodes. */
class MapScene(val tree: Octree, val nodeRadius: Float, val titles: List<String>, val ids: List<String>) {
    companion object {
        fun of(graph: MapGraph, leafCapacity: Int = 4096): MapScene {
            val tree = Octree.build(graph, leafCapacity)
            // a node is about a third of the typical spacing between neighbours in its chunk
            var spacing = 0.0; var weight = 0
            for (leaf in 0 until tree.leafCount) {
                val cell = tree.leafCell[leaf]
                if (tree.count[cell] < 2) continue
                spacing += 1.6 * tree.radius[cell] / cbrt(tree.count[cell].toDouble()) * tree.count[cell]
                weight += tree.count[cell]
            }
            val radius = if (weight == 0) 0.35f else (spacing / weight * 0.3).toFloat().coerceIn(0.01f, 0.45f)
            return MapScene(tree, radius, graph.titles, graph.ids)
        }
    }
}

/** True when this device can run the OpenGL ES 3.0 map. */
fun supportsGles3(context: Context): Boolean {
    val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager ?: return false
    return am.deviceConfigurationInfo.reqGlEsVersion >= 0x30000
}

private fun Context.findActivity(): Activity? {
    var c: Context? = this
    while (c is ContextWrapper) { if (c is Activity) return c; c = c.baseContext }
    return null
}

private fun Display.Mode.info() = DisplayModeInfo(modeId, physicalWidth, physicalHeight, refreshRate)

/**
 * The 3D map on screen. Frames follow Choreographer's vsync; the window asks for the
 * display's highest refresh mode and the surface for its highest frame rate, so the map
 * runs at the screen's own rate (plan 4e). With [continuous] false the map stops drawing
 * once nothing moves, and any touch brings it straight back.
 */
@Composable fun Map3DView(
    scene: MapScene,
    modifier: Modifier = Modifier,
    description: String,
    continuous: Boolean = false,
    autoOrbit: Boolean = false,
    onOpenNode: ((Int) -> Unit)? = null,
) {
    val context = LocalContext.current
    val activity = remember(context) { context.findActivity() }
    val display: Display? = remember(context) {
        if (Build.VERSION.SDK_INT >= 30) context.display else @Suppress("DEPRECATION") (context.getSystemService(Context.WINDOW_SERVICE) as WindowManager).defaultDisplay
    }
    val modes = remember(display) { display?.supportedModes?.map { it.info() } ?: emptyList() }
    val maxHz = remember(modes) { RefreshRate.maxHz(modes, display?.refreshRate ?: 60f) }
    var readout by remember { mutableStateOf(MapReadout(displayMaxHz = maxHz)) }
    var screenNodes by remember { mutableStateOf<List<ScreenNode>>(emptyList()) }
    val hz = remember { floatArrayOf(display?.refreshRate ?: 60f) }
    val tree = scene.tree
    val camera = remember(scene) {
        OrbitCamera(target = Vec3(tree.cx[0], tree.cy[0], tree.cz[0]), distance = max(tree.radius[0] * 2.4f, 4f)).apply {
            minDistance = scene.nodeRadius * 4; maxDistance = max(tree.radius[0], 1f) * 80
        }
    }
    val home = remember(scene) { Triple(camera.target, camera.distance, camera.yaw to camera.pitch) }
    val mainHandler = remember { android.os.Handler(android.os.Looper.getMainLooper()) }
    val renderer = remember(scene) {
        GlMapRenderer(
            scene.tree, camera, scene.nodeRadius, displayHz = { hz[0] }, displayMaxHz = maxHz,
            onReadout = { r -> mainHandler.post { readout = r } },
            onScreenNodes = if (scene.titles.isEmpty()) null else { nodes -> mainHandler.post { screenNodes = nodes } },
        )
    }
    val gles3 = remember(context) { supportsGles3(context) }
    val loop = remember(renderer) { FrameLoop(renderer, continuous, autoOrbit, camera) { display?.refreshRate?.let { hz[0] = it } } }

    // Ask the window for the highest refresh mode at this resolution while the map is shown.
    DisposableEffect(activity, modes) {
        val window = activity?.window
        val previous = window?.attributes?.preferredDisplayModeId ?: 0
        val current = display?.mode?.info()
        val best = current?.let { RefreshRate.bestMode(modes, it) }
        if (window != null && best != null) window.attributes = window.attributes.also { it.preferredDisplayModeId = best.id }
        onDispose { if (window != null && best != null) window.attributes = window.attributes.also { it.preferredDisplayModeId = previous } }
    }

    val lifecycle = LocalLifecycleOwner.current.lifecycle
    Box(modifier.background(Color(0xFF0E1B2C), RoundedCornerShape(24.dp)).semantics { contentDescription = description }) {
        if (!gles3) {
            Text("This device has no OpenGL ES 3, which the 3D map needs.", Modifier.align(Alignment.Center).padding(24.dp), color = Color.White)
            return@Box
        }
        AndroidView(
            factory = { ctx ->
                GLSurfaceView(ctx).apply {
                    setEGLContextClientVersion(3)
                    preserveEGLContextOnPause = true
                    setRenderer(renderer)
                    renderMode = GLSurfaceView.RENDERMODE_WHEN_DIRTY
                    holder.addCallback(object : SurfaceHolder.Callback {
                        override fun surfaceCreated(h: SurfaceHolder) = requestFrameRate(h.surface, maxHz)
                        override fun surfaceChanged(h: SurfaceHolder, format: Int, width: Int, height: Int) = requestFrameRate(h.surface, maxHz)
                        override fun surfaceDestroyed(h: SurfaceHolder) {}
                    })
                    loop.view = this
                }
            },
            modifier = Modifier.fillMaxSize(),
        )
        DisposableEffect(lifecycle, loop) {
            val observer = LifecycleEventObserver { _, event ->
                when (event) {
                    Lifecycle.Event.ON_RESUME -> { loop.view?.onResume(); loop.start() }
                    Lifecycle.Event.ON_PAUSE -> { loop.stop(); loop.view?.onPause() }
                    else -> {}
                }
            }
            lifecycle.addObserver(observer)
            if (lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) loop.start()
            onDispose { lifecycle.removeObserver(observer); loop.stop() }
        }
        val slop = LocalViewConfiguration.current.touchSlop
        Canvas(
            Modifier.fillMaxSize().pointerInput(scene) {
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false)
                    loop.touched()
                    var moved = 0f
                    var multi = false
                    while (true) {
                        val event = awaitPointerEvent()
                        val pressed = event.changes.filter { it.pressed }
                        if (pressed.isEmpty()) break
                        loop.touched()
                        if (pressed.size >= 2) {
                            multi = true
                            val zoom = event.calculateZoom()
                            val pan = event.calculatePan()
                            synchronized(camera) {
                                camera.zoom(zoom)
                                camera.pan(pan.x / size.height, pan.y / size.height)
                            }
                            moved += pan.getDistance() + kotlin.math.abs(zoom - 1f) * 100
                        } else {
                            val change = pressed.first()
                            val delta = change.position - change.previousPosition
                            moved += delta.getDistance()
                            if (moved > slop || multi) synchronized(camera) { camera.orbit(-delta.x / size.width * 3.2f, delta.y / size.height * 2.4f) }
                        }
                        event.changes.forEach { if (it.positionChanged()) it.consume() }
                    }
                    if (!multi && moved <= slop && onOpenNode != null) {
                        val hit = screenNodes.filter { it.pixels > 2f }.minByOrNull { (Offset(it.x, it.y) - down.position).getDistance() }
                        if (hit != null && (Offset(hit.x, hit.y) - down.position).getDistance() < 40.dp.toPx()) onOpenNode(hit.index)
                    }
                }
            },
        ) {
            // labels grow with their node's size on screen: no fading, only size
            if (scene.titles.isEmpty()) return@Canvas
            drawIntoCanvas { canvas ->
                val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
                    color = android.graphics.Color.rgb(225, 235, 249); textAlign = android.graphics.Paint.Align.CENTER
                    typeface = android.graphics.Typeface.create("sans-serif-medium", android.graphics.Typeface.NORMAL)
                }
                for (node in screenNodes) {
                    val textSize = (node.pixels * 0.9f).coerceAtMost(12.sp.toPx())
                    if (textSize < 5f) continue
                    paint.textSize = textSize
                    val title = scene.titles.getOrNull(node.index) ?: continue
                    val label = if (title.length > 23) title.take(22) + "…" else title
                    canvas.nativeCanvas.drawText(label, node.x, node.y + node.pixels / 2 + textSize * 1.4f, paint)
                }
            }
        }
        Readout(readout, Modifier.align(Alignment.TopStart).padding(10.dp))
        Row(Modifier.align(Alignment.BottomEnd).padding(10.dp).background(Color(0xFF1D3047), RoundedCornerShape(24.dp))) {
            IconButton(onClick = { loop.touched(); synchronized(camera) { camera.zoom(1 / 1.25f) } }) { Icon(Icons.Rounded.Remove, "Zoom out", tint = Color.White) }
            IconButton(onClick = {
                loop.touched()
                synchronized(camera) { camera.target = home.first; camera.distance = home.second; camera.yaw = home.third.first; camera.pitch = home.third.second }
            }) { Icon(Icons.Rounded.CenterFocusStrong, "Recenter map", tint = Color.White) }
            IconButton(onClick = { loop.touched(); synchronized(camera) { camera.zoom(1.25f) } }) { Icon(Icons.Rounded.Add, "Zoom in", tint = Color.White) }
        }
    }
}

@Composable private fun Readout(r: MapReadout, modifier: Modifier) {
    val style = Modifier.background(Color(0xCC0A1422), RoundedCornerShape(10.dp)).padding(horizontal = 10.dp, vertical = 6.dp)
    Column(modifier.then(style)) {
        val line1 = String.format(Locale.ROOT, "%.0f fps · %.0f Hz max · %.1f ms frame · %.1f ms work", r.fps, r.displayMaxHz, r.frameMs, r.workMs)
        Text(line1, color = Color(0xFFE1EBF9), fontSize = 11.sp, fontFamily = FontFamily.Monospace)
        Text("${grouped(r.nodes)} nodes · ${grouped(r.links)} links", color = Color(0xFFB8C8DE), fontSize = 11.sp, fontFamily = FontFamily.Monospace)
        Text("${grouped(r.drawnNodes)} drawn · ${r.chunks} chunks · ${grouped(r.summaries)} summaries · ${grouped(r.bundles)} bundles",
            color = Color(0xFF8FA6C4), fontSize = 10.sp, fontFamily = FontFamily.Monospace)
    }
}

private fun requestFrameRate(surface: Surface, hz: Float) {
    if (!surface.isValid) return
    runCatching {
        when {
            Build.VERSION.SDK_INT >= 31 -> surface.setFrameRate(hz, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT, Surface.CHANGE_FRAME_RATE_ALWAYS)
            Build.VERSION.SDK_INT >= 30 -> surface.setFrameRate(hz, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT)
        }
    }
}

/**
 * Drives frames from Choreographer: each vsync hands its timestamp to the renderer and
 * asks for one frame. Idle maps stop after a quiet second; a touch restarts at once.
 */
private class FrameLoop(
    private val renderer: GlMapRenderer,
    private val continuous: Boolean,
    private var autoOrbit: Boolean,
    private val camera: OrbitCamera,
    private val sampleDisplay: () -> Unit,
) : Choreographer.FrameCallback {
    var view: GLSurfaceView? = null
    private var running = false
    private var lastActive = 0L
    private var lastFrame = 0L
    private var frames = 0

    fun start() { if (!running) { running = true; lastActive = System.nanoTime(); Choreographer.getInstance().postFrameCallback(this) } }
    fun stop() { running = false; Choreographer.getInstance().removeFrameCallback(this) }
    fun touched() { autoOrbit = false; lastActive = System.nanoTime(); if (!running && view != null) start() }

    override fun doFrame(frameTimeNanos: Long) {
        if (!running) return
        if (frames++ % 60 == 0) sampleDisplay()
        if (autoOrbit && lastFrame != 0L) synchronized(camera) { camera.orbit(((frameTimeNanos - lastFrame) / 1e9f) * 0.08f, 0f) }
        lastFrame = frameTimeNanos
        renderer.vsyncNanos = frameTimeNanos
        view?.requestRender()
        if (renderer.animating || autoOrbit) lastActive = frameTimeNanos
        if (continuous || frameTimeNanos - lastActive < 1_000_000_000L) Choreographer.getInstance().postFrameCallback(this) else running = false
    }
}
