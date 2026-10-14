package com.stethoscore.app.ui.map

import android.opengl.GLES30
import android.opengl.GLSurfaceView
import com.stethoscore.app.map.ChunkCache
import com.stethoscore.app.map.FrameBudget
import com.stethoscore.app.map.FramePlan
import com.stethoscore.app.map.FrameStats
import com.stethoscore.app.map.GuardBand
import com.stethoscore.app.map.LodSelector
import com.stethoscore.app.map.MapPalette
import com.stethoscore.app.map.Mat4
import com.stethoscore.app.map.Octree
import com.stethoscore.app.map.OrbitCamera
import com.stethoscore.app.map.Vec3
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.nio.IntBuffer
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min

/** What the frame readout shows, published a few times a second. */
data class MapReadout(
    val fps: Double = 0.0,
    val displayMaxHz: Float = 60f,
    val displayHz: Float = 60f,
    val frameMs: Double = 0.0,
    val workMs: Double = 0.0,
    val nodes: Int = 0,
    val links: Int = 0,
    val drawnNodes: Int = 0,
    val chunks: Int = 0,
    val summaries: Int = 0,
    val bundles: Int = 0,
    val resident: Int = 0,
    val detail: Float = 1f,
)

/** A node's place on screen, for labels and taps (real notes only). */
data class ScreenNode(val index: Int, val x: Float, val y: Float, val pixels: Float)

/**
 * Draws the 3D Ideas map with OpenGL ES 3.0, the baseline every Android 8+ phone has.
 * Every node (12 bytes: 16-bit position, chunk id, colour group) is resident in one GPU
 * buffer from the first frame, and each chunk's morph state is one texel of a float
 * texture, so changing the level of detail is choosing ranges and writing a few kilobytes,
 * never moving the million nodes. Link lists stream into a paged GPU pool through the LRU
 * [ChunkCache]. Draws: link bundles (instanced quads), links, summary points, nodes, all
 * additive, so detail changes by size and position, never by opacity.
 */
class GlMapRenderer(
    val tree: Octree,
    val camera: OrbitCamera,
    private val nodeRadius: Float,
    /** Display refresh rate now, read every frame (it changes when the mode switches). */
    private val displayHz: () -> Float,
    private val displayMaxHz: Float,
    private val onReadout: (MapReadout) -> Unit,
    private val onScreenNodes: ((List<ScreenNode>) -> Unit)? = null,
) : GLSurfaceView.Renderer {
    /** The vsync time (Choreographer) of the frame being drawn; 0 when unknown. */
    @Volatile var vsyncNanos = 0L
    /** Camera velocity (world units a second), smoothed; read by the guard band. */
    private var velocity = Vec3.ZERO
    private var lastEye: Vec3? = null
    private var lastTarget: Vec3? = null

    val budget = FrameBudget(displayHz())
    private val stats = FrameStats()
    private val pageSize = 8192
    private fun newCache() = ChunkCache(
        pageCount = max(256, (tree.leafEdges.size.coerceAtMost(2_000_000) + pageSize - 1) / pageSize + 8)
            .coerceAtLeast((0 until tree.leafCount).maxOfOrNull { (tree.leafEdgeIndexCount(it) + pageSize - 1) / pageSize * 3 } ?: 1),
        pageSize = pageSize,
    ) { tree.leafEdgeIndexCount(it) }
    // A new GL context starts with an empty link pool, so both are made again in onSurfaceCreated.
    private var cache = newCache()
    private var lod = LodSelector(tree, cache)

    @Volatile var animating = true; private set
    private var frame = 0
    private var lastVsync = 0L
    private var lastReadout = 0L
    private var width = 1; private var height = 1
    private var maxPointSize = 64f

    private var nodeProgram = 0; private var edgeProgram = 0; private var summaryProgram = 0; private var bundleProgram = 0
    private var nodeVao = 0; private var edgeVao = 0; private var summaryVao = 0; private var bundleVao = 0
    private var nodeVbo = 0; private var edgeIbo = 0; private var summaryVbo = 0; private var bundleVbo = 0; private var cornerVbo = 0
    private var leafTexture = 0
    private val leafTexWidth = 1024
    private var leafTexHeight = 1
    private lateinit var leafStateBuffer: FloatBuffer
    private var summaryBuffer: FloatBuffer = floats(7 * 1024)
    private var bundleBuffer: FloatBuffer = floats(10 * 1024)
    private val center = FloatArray(3)
    private val half = FloatArray(3)
    private var viewProj = Mat4.identity()

    init { require(tree.leafCount < 65_536) { "chunk ids are 16-bit" } }

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        nodeProgram = program(NODE_VS, NODE_FS)
        edgeProgram = program(EDGE_VS, EDGE_FS)
        summaryProgram = program(SUMMARY_VS, SUMMARY_FS)
        bundleProgram = program(BUNDLE_VS, BUNDLE_FS)
        val range = FloatArray(2)
        GLES30.glGetFloatv(GLES30.GL_ALIASED_POINT_SIZE_RANGE, range, 0)
        maxPointSize = max(range[1], 1f)
        uploadNodes()
        uploadLeafTexture()
        val ids = IntArray(4)
        GLES30.glGenBuffers(4, ids, 0)
        edgeIbo = ids[0]; summaryVbo = ids[1]; bundleVbo = ids[2]; cornerVbo = ids[3]
        // the edge pool: pages of link indices, filled as chunks stream in
        GLES30.glGenVertexArrays(1, ids, 0); edgeVao = ids[0]
        GLES30.glBindVertexArray(edgeVao)
        bindNodeAttributes()
        GLES30.glBindBuffer(GLES30.GL_ELEMENT_ARRAY_BUFFER, edgeIbo)
        GLES30.glBufferData(GLES30.GL_ELEMENT_ARRAY_BUFFER, cache.pageCount * pageSize * 4, null, GLES30.GL_DYNAMIC_DRAW)
        GLES30.glBindVertexArray(0)
        // summaries: x, y, z, diameter, r, g, b
        GLES30.glGenVertexArrays(1, ids, 0); summaryVao = ids[0]
        GLES30.glBindVertexArray(summaryVao)
        GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, summaryVbo)
        GLES30.glEnableVertexAttribArray(0); GLES30.glVertexAttribPointer(0, 3, GLES30.GL_FLOAT, false, 28, 0)
        GLES30.glEnableVertexAttribArray(1); GLES30.glVertexAttribPointer(1, 1, GLES30.GL_FLOAT, false, 28, 12)
        GLES30.glEnableVertexAttribArray(2); GLES30.glVertexAttribPointer(2, 3, GLES30.GL_FLOAT, false, 28, 16)
        GLES30.glBindVertexArray(0)
        // bundles: one instanced quad each
        GLES30.glGenVertexArrays(1, ids, 0); bundleVao = ids[0]
        GLES30.glBindVertexArray(bundleVao)
        GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, cornerVbo)
        val corners = floatArrayOf(0f, -1f, 1f, -1f, 1f, 1f, 0f, -1f, 1f, 1f, 0f, 1f)
        GLES30.glBufferData(GLES30.GL_ARRAY_BUFFER, corners.size * 4, floats(corners.size).put(corners).flip(), GLES30.GL_STATIC_DRAW)
        GLES30.glEnableVertexAttribArray(0); GLES30.glVertexAttribPointer(0, 2, GLES30.GL_FLOAT, false, 8, 0)
        GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, bundleVbo)
        for ((loc, comps, off) in listOf(Triple(1, 3, 0), Triple(2, 3, 12), Triple(3, 1, 24), Triple(4, 3, 28))) {
            GLES30.glEnableVertexAttribArray(loc)
            GLES30.glVertexAttribPointer(loc, comps, GLES30.GL_FLOAT, false, 40, off)
            GLES30.glVertexAttribDivisor(loc, 1)
        }
        GLES30.glBindVertexArray(0)
        GLES30.glDisable(GLES30.GL_DEPTH_TEST)
        GLES30.glEnable(GLES30.GL_BLEND)
        GLES30.glBlendFunc(GLES30.GL_ONE, GLES30.GL_ONE)
        // a new context has an empty pool: everything streams again
        cache = newCache()
        lod = LodSelector(tree, cache)
    }

    override fun onSurfaceChanged(gl: GL10?, w: Int, h: Int) {
        width = max(w, 1); height = max(h, 1)
        GLES30.glViewport(0, 0, width, height)
    }

    override fun onDrawFrame(gl: GL10?) {
        val start = System.nanoTime()
        val vsync = vsyncNanos.takeIf { it > 0 } ?: start
        val intervalMs = if (lastVsync == 0L) 1000.0 / displayHz() else (vsync - lastVsync).coerceAtLeast(0L) / 1e6
        val dt = (intervalMs / 1000.0).toFloat().coerceIn(0f, 0.25f)
        lastVsync = vsync
        frame++
        budget.refreshHz = displayHz()

        val eye: Vec3; val target: Vec3; val view: FloatArray; val proj: FloatArray; val focal: Float
        val aspect = width.toFloat() / height
        synchronized(camera) {
            eye = camera.eye(); target = camera.target
            view = camera.view(); proj = camera.projection(aspect); focal = camera.focalPixels(height.toFloat())
        }
        val moved = lastEye?.let { (eye - it).length() + (target - (lastTarget ?: target)).length() } ?: 0f
        if (dt > 0f) {
            val instant = lastEye?.let { (eye - it) * (1f / dt) } ?: Vec3.ZERO
            val k = 1f - exp(-dt * 8f)
            velocity = velocity + (instant - velocity) * k
        }
        lastEye = eye; lastTarget = target
        viewProj = Mat4.multiply(proj, view)
        val guardCamera = synchronized(camera) { OrbitCamera(camera.target, camera.distance, camera.yaw, camera.pitch, camera.fovY) }
        val guard = GuardBand.predict(guardCamera, aspect, velocity, lookaheadSeconds = 0.35f)
        val plan = lod.select(eye, focal, guard.view, guard, budget.openPixels, budget.maxDetailNodes, dt, frame)
        cache.pump(frame, budget.uploadBudget) { chunk, pages -> uploadChunk(chunk, pages) }
        animating = moved > 1e-5f || plan.detailLeaves.size.let { n -> (0 until n).any { plan.leafState[plan.detailLeaves[it] * 4 + 3] < 1f } } || cache.uploadedThisFrame > 0

        GLES30.glClearColor(0.055f, 0.106f, 0.173f, 1f)
        GLES30.glClear(GLES30.GL_COLOR_BUFFER_BIT or GLES30.GL_DEPTH_BUFFER_BIT)
        uploadLeafState(plan)
        drawBundles(plan)
        drawEdges(plan, eye, focal)
        drawSummaries(plan)
        val drawn = drawNodes(plan, eye, focal)
        publishScreenNodes(plan)

        val workMs = (System.nanoTime() - start) / 1e6
        budget.onFrame(intervalMs, workMs)
        stats.add(vsync, intervalMs, workMs)
        if (vsync - lastReadout > 250_000_000L) {
            lastReadout = vsync
            onReadout(MapReadout(
                fps = stats.fps(vsync), displayMaxHz = displayMaxHz, displayHz = displayHz(),
                frameMs = stats.medianInterval(), workMs = stats.medianWork(),
                nodes = tree.nodeCount, links = tree.edgeCount, drawnNodes = drawn, chunks = plan.detailLeaves.size,
                summaries = plan.summaryCount, bundles = plan.bundleCount, resident = cache.residentCount, detail = budget.detail,
            ))
        }
    }

    // ---- uploads ----

    private fun uploadNodes() {
        val n = tree.nodeCount
        val p = tree.positions
        var minX = Float.MAX_VALUE; var minY = Float.MAX_VALUE; var minZ = Float.MAX_VALUE
        var maxX = -Float.MAX_VALUE; var maxY = -Float.MAX_VALUE; var maxZ = -Float.MAX_VALUE
        for (i in 0 until n) {
            minX = min(minX, p[3 * i]); maxX = max(maxX, p[3 * i]); minY = min(minY, p[3 * i + 1]); maxY = max(maxY, p[3 * i + 1])
            minZ = min(minZ, p[3 * i + 2]); maxZ = max(maxZ, p[3 * i + 2])
        }
        center[0] = (minX + maxX) / 2; center[1] = (minY + maxY) / 2; center[2] = (minZ + maxZ) / 2
        half[0] = max((maxX - minX) / 2, 1e-3f); half[1] = max((maxY - minY) / 2, 1e-3f); half[2] = max((maxZ - minZ) / 2, 1e-3f)
        val buffer = ByteBuffer.allocateDirect(max(n, 1) * NODE_STRIDE).order(ByteOrder.nativeOrder())
        for (i in 0 until n) {
            for (a in 0 until 3) buffer.putShort(((p[3 * i + a] - center[a]) / half[a] * 32767f).toInt().coerceIn(-32767, 32767).toShort())
            buffer.putShort(tree.leafOfNode[i].toShort())
            buffer.put(tree.groups[i]); buffer.put(0); buffer.put(0); buffer.put(0)
        }
        buffer.flip()
        val ids = IntArray(1)
        GLES30.glGenBuffers(1, ids, 0); nodeVbo = ids[0]
        GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, nodeVbo)
        GLES30.glBufferData(GLES30.GL_ARRAY_BUFFER, buffer.capacity(), buffer, GLES30.GL_STATIC_DRAW)
        GLES30.glGenVertexArrays(1, ids, 0); nodeVao = ids[0]
        GLES30.glBindVertexArray(nodeVao)
        bindNodeAttributes()
        GLES30.glBindVertexArray(0)
    }

    private fun bindNodeAttributes() {
        GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, nodeVbo)
        GLES30.glEnableVertexAttribArray(0)
        GLES30.glVertexAttribPointer(0, 3, GLES30.GL_SHORT, true, NODE_STRIDE, 0)
        GLES30.glEnableVertexAttribArray(1)
        GLES30.glVertexAttribIPointer(1, 1, GLES30.GL_UNSIGNED_SHORT, NODE_STRIDE, 6)
        GLES30.glEnableVertexAttribArray(2)
        GLES30.glVertexAttribIPointer(2, 1, GLES30.GL_UNSIGNED_BYTE, NODE_STRIDE, 8)
    }

    private fun uploadLeafTexture() {
        leafTexHeight = max(1, (tree.leafCount + leafTexWidth - 1) / leafTexWidth)
        leafStateBuffer = floats(leafTexWidth * leafTexHeight * 4)
        val ids = IntArray(1)
        GLES30.glGenTextures(1, ids, 0); leafTexture = ids[0]
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, leafTexture)
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MIN_FILTER, GLES30.GL_NEAREST)
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MAG_FILTER, GLES30.GL_NEAREST)
        GLES30.glTexImage2D(GLES30.GL_TEXTURE_2D, 0, GLES30.GL_RGBA32F, leafTexWidth, leafTexHeight, 0, GLES30.GL_RGBA, GLES30.GL_FLOAT, null)
    }

    private fun uploadLeafState(plan: FramePlan) {
        leafStateBuffer.clear()
        leafStateBuffer.put(plan.leafState, 0, min(plan.leafState.size, leafStateBuffer.capacity()))
        leafStateBuffer.position(0)
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, leafTexture)
        GLES30.glTexSubImage2D(GLES30.GL_TEXTURE_2D, 0, 0, 0, leafTexWidth, leafTexHeight, GLES30.GL_RGBA, GLES30.GL_FLOAT, leafStateBuffer)
    }

    private var uploadScratch: IntBuffer = ByteBuffer.allocateDirect(8192 * 4).order(ByteOrder.nativeOrder()).asIntBuffer()

    private fun uploadChunk(chunk: Int, pages: IntArray) {
        GLES30.glBindVertexArray(0)
        GLES30.glBindBuffer(GLES30.GL_ELEMENT_ARRAY_BUFFER, edgeIbo)
        val from = tree.leafEdgeStart[chunk]
        val total = tree.leafEdgeIndexCount(chunk)
        for ((k, page) in pages.withIndex()) {
            val offset = k * pageSize
            val count = min(pageSize, total - offset)
            if (count <= 0) break
            uploadScratch.clear()
            uploadScratch.put(tree.leafEdges, from + offset, count)
            uploadScratch.flip()
            GLES30.glBufferSubData(GLES30.GL_ELEMENT_ARRAY_BUFFER, page * pageSize * 4, count * 4, uploadScratch)
        }
    }

    // ---- draws ----

    private fun setCommon(program: Int, focal: Float) {
        GLES30.glUseProgram(program)
        GLES30.glUniformMatrix4fv(GLES30.glGetUniformLocation(program, "uVP"), 1, false, viewProj, 0)
        GLES30.glUniform3fv(GLES30.glGetUniformLocation(program, "uCenter"), 1, center, 0)
        GLES30.glUniform3fv(GLES30.glGetUniformLocation(program, "uHalf"), 1, half, 0)
        GLES30.glUniform3fv(GLES30.glGetUniformLocation(program, "uPalette"), 6, MapPalette.rgb, 0)
        GLES30.glUniform1f(GLES30.glGetUniformLocation(program, "uFocal"), focal)
        GLES30.glUniform1f(GLES30.glGetUniformLocation(program, "uNodeRadius"), nodeRadius)
        GLES30.glUniform1f(GLES30.glGetUniformLocation(program, "uMaxPoint"), min(maxPointSize, 64f))
        GLES30.glActiveTexture(GLES30.GL_TEXTURE0)
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, leafTexture)
        GLES30.glUniform1i(GLES30.glGetUniformLocation(program, "uLeafState"), 0)
    }

    private fun drawNodes(plan: FramePlan, eye: Vec3, focal: Float): Int {
        if (plan.detailLeaves.size == 0) return 0
        setCommon(nodeProgram, focal)
        GLES30.glBindVertexArray(nodeVao)
        var drawn = 0
        for (k in 0 until plan.detailLeaves.size) {
            val cell = tree.leafCell[plan.detailLeaves[k]]
            GLES30.glDrawArrays(GLES30.GL_POINTS, tree.start[cell], tree.count[cell])
            drawn += tree.count[cell]
        }
        GLES30.glBindVertexArray(0)
        return drawn
    }

    private fun drawEdges(plan: FramePlan, eye: Vec3, focal: Float) {
        if (plan.detailLeaves.size == 0) return
        setCommon(edgeProgram, focal)
        GLES30.glBindVertexArray(edgeVao)
        for (k in 0 until plan.detailLeaves.size) {
            val leaf = plan.detailLeaves[k]
            val pages = cache.pages(leaf) ?: continue
            val total = tree.leafEdgeIndexCount(leaf)
            for ((i, page) in pages.withIndex()) {
                val count = min(pageSize, total - i * pageSize)
                if (count <= 0) break
                GLES30.glDrawElements(GLES30.GL_LINES, count, GLES30.GL_UNSIGNED_INT, page * pageSize * 4)
            }
        }
        GLES30.glBindVertexArray(0)
    }

    private fun drawSummaries(plan: FramePlan) {
        if (plan.summaryCount == 0) return
        summaryBuffer = ensure(summaryBuffer, plan.summaries.size)
        summaryBuffer.put(plan.summaries.data, 0, plan.summaries.size).flip()
        GLES30.glUseProgram(summaryProgram)
        GLES30.glUniformMatrix4fv(GLES30.glGetUniformLocation(summaryProgram, "uVP"), 1, false, viewProj, 0)
        GLES30.glUniform1f(GLES30.glGetUniformLocation(summaryProgram, "uMaxPoint"), maxPointSize)
        GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, summaryVbo)
        GLES30.glBufferData(GLES30.GL_ARRAY_BUFFER, plan.summaries.size * 4, summaryBuffer, GLES30.GL_STREAM_DRAW)
        GLES30.glBindVertexArray(summaryVao)
        GLES30.glDrawArrays(GLES30.GL_POINTS, 0, plan.summaryCount)
        GLES30.glBindVertexArray(0)
    }

    private fun drawBundles(plan: FramePlan) {
        if (plan.bundleCount == 0) return
        bundleBuffer = ensure(bundleBuffer, plan.bundles.size)
        bundleBuffer.put(plan.bundles.data, 0, plan.bundles.size).flip()
        GLES30.glUseProgram(bundleProgram)
        GLES30.glUniformMatrix4fv(GLES30.glGetUniformLocation(bundleProgram, "uVP"), 1, false, viewProj, 0)
        GLES30.glUniform2f(GLES30.glGetUniformLocation(bundleProgram, "uViewport"), width.toFloat(), height.toFloat())
        GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, bundleVbo)
        GLES30.glBufferData(GLES30.GL_ARRAY_BUFFER, plan.bundles.size * 4, bundleBuffer, GLES30.GL_STREAM_DRAW)
        GLES30.glBindVertexArray(bundleVao)
        GLES30.glDrawArraysInstanced(GLES30.GL_TRIANGLES, 0, 6, plan.bundleCount)
        GLES30.glBindVertexArray(0)
    }

    private val clip = FloatArray(4)

    /** Real notes only: where each node is on screen and how big, for labels and taps. */
    private fun publishScreenNodes(plan: FramePlan) {
        val callback = onScreenNodes ?: return
        val out = ArrayList<ScreenNode>(tree.nodeCount)
        val focal = camera.focalPixels(height.toFloat())
        for (k in 0 until tree.nodeCount) {
            val leaf = tree.leafOfNode[k]
            val t = plan.leafState[leaf * 4 + 3]
            if (t <= 0f) continue
            val s = leaf * 4
            val x = plan.leafState[s] + (tree.positions[3 * k] - plan.leafState[s]) * t
            val y = plan.leafState[s + 1] + (tree.positions[3 * k + 1] - plan.leafState[s + 1]) * t
            val z = plan.leafState[s + 2] + (tree.positions[3 * k + 2] - plan.leafState[s + 2]) * t
            Mat4.project(viewProj, x, y, z, clip)
            if (clip[3] <= 1e-4f) continue
            val sx = (clip[0] / clip[3] * 0.5f + 0.5f) * width
            val sy = (1f - (clip[1] / clip[3] * 0.5f + 0.5f)) * height
            out.add(ScreenNode(tree.order[k], sx, sy, nodeRadius * focal / clip[3] * 2f * t))
        }
        callback(out)
    }

    // ---- helpers ----

    private fun ensure(buffer: FloatBuffer, size: Int): FloatBuffer {
        if (buffer.capacity() >= size) { buffer.clear(); return buffer }
        return floats(max(size, buffer.capacity() * 2))
    }

    private fun program(vs: String, fs: String): Int {
        fun shader(type: Int, source: String): Int {
            val s = GLES30.glCreateShader(type)
            GLES30.glShaderSource(s, source); GLES30.glCompileShader(s)
            val ok = IntArray(1); GLES30.glGetShaderiv(s, GLES30.GL_COMPILE_STATUS, ok, 0)
            check(ok[0] != 0) { "Map shader did not compile: " + GLES30.glGetShaderInfoLog(s) }
            return s
        }
        val p = GLES30.glCreateProgram()
        GLES30.glAttachShader(p, shader(GLES30.GL_VERTEX_SHADER, vs))
        GLES30.glAttachShader(p, shader(GLES30.GL_FRAGMENT_SHADER, fs))
        GLES30.glLinkProgram(p)
        val ok = IntArray(1); GLES30.glGetProgramiv(p, GLES30.GL_LINK_STATUS, ok, 0)
        check(ok[0] != 0) { "Map shader did not link: " + GLES30.glGetProgramInfoLog(p) }
        return p
    }

    companion object {
        const val NODE_STRIDE = 12

        private fun floats(n: Int): FloatBuffer = ByteBuffer.allocateDirect(n * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()

        // Each node morphs between its chunk's summary point and its own place by the chunk's
        // openness t, and its point grows with t: a summary point grows into its nodes.
        private const val NODE_HEADER = """#version 300 es
precision highp float;
precision highp int;
layout(location = 0) in vec3 aPos;
layout(location = 1) in uint aLeaf;
layout(location = 2) in uint aGroup;
uniform mat4 uVP;
uniform vec3 uCenter;
uniform vec3 uHalf;
uniform vec3 uPalette[6];
uniform float uFocal;
uniform float uNodeRadius;
uniform float uMaxPoint;
uniform highp sampler2D uLeafState;
vec4 leafState() { int l = int(aLeaf); return texelFetch(uLeafState, ivec2(l % 1024, l / 1024), 0); }
vec3 placed(vec4 st) { return mix(st.xyz, uCenter + aPos * uHalf, st.w); }
"""

        private const val NODE_VS = NODE_HEADER + """
out vec3 vColor;
out float vSize;
void main() {
    vec4 st = leafState();
    gl_Position = uVP * vec4(placed(st), 1.0);
    float w = max(gl_Position.w, 1e-4);
    // detail follows the pixels a node covers: a plain point, then shading, then glow
    float px = 2.0 * uNodeRadius * uFocal / w * st.w;
    vSize = clamp(px, 1.0, uMaxPoint);
    gl_PointSize = vSize;
    // a node smaller than a pixel lights the pixel by the area it covers, so dense far
    // clusters stay coloured instead of adding up to white
    float cover = clamp(px, 0.35, 1.0);
    vColor = uPalette[int(aGroup) % 6] * cover * cover;
}
"""

        private const val NODE_FS = """#version 300 es
precision mediump float;
in vec3 vColor;
in float vSize;
out vec4 fragColor;
void main() {
    vec2 c = gl_PointCoord * 2.0 - 1.0;
    float r2 = dot(c, c);
    if (r2 > 1.0) discard;
    float glow = smoothstep(6.0, 28.0, vSize);
    float coreR = mix(1.0, 0.5, glow);
    float r = sqrt(r2);
    float core = 1.0 - smoothstep(coreR - 0.12, coreR, r);
    float z = sqrt(max(0.0, 1.0 - r2 / (coreR * coreR)));
    float shade = mix(1.0, 0.45 + 0.55 * z + 0.35 * pow(max(0.0, dot(normalize(vec3(c, z)), normalize(vec3(-0.4, 0.5, 0.8)))), 12.0), smoothstep(3.0, 10.0, vSize));
    float halo = glow * 0.55 * exp(-r2 * 5.0);
    fragColor = vec4(vColor * (core * shade * 0.9 + halo), 1.0);
}
"""

        private const val EDGE_VS = NODE_HEADER + """
out vec3 vColor;
void main() {
    vec4 st = leafState();
    gl_Position = uVP * vec4(placed(st), 1.0);
    vColor = uPalette[int(aGroup) % 6];
}
"""

        private const val EDGE_FS = """#version 300 es
precision mediump float;
in vec3 vColor;
out vec4 fragColor;
void main() { fragColor = vec4(vColor * 0.32, 1.0); }
"""

        private const val SUMMARY_VS = """#version 300 es
precision highp float;
layout(location = 0) in vec3 aPos;
layout(location = 1) in float aSize;
layout(location = 2) in vec3 aColor;
uniform mat4 uVP;
uniform float uMaxPoint;
out vec3 vColor;
void main() {
    gl_Position = uVP * vec4(aPos, 1.0);
    gl_PointSize = clamp(aSize, 1.0, uMaxPoint);
    vColor = aColor;
}
"""

        // A summary is a soft star: a bright core and a glow, its size set on the CPU from its chunk's on-screen size.
        private const val SUMMARY_FS = """#version 300 es
precision mediump float;
in vec3 vColor;
out vec4 fragColor;
void main() {
    vec2 c = gl_PointCoord * 2.0 - 1.0;
    float r2 = dot(c, c);
    if (r2 > 1.0) discard;
    float core = 1.0 - smoothstep(0.08, 0.3, sqrt(r2));
    float glow = exp(-r2 * 5.0) * 0.35;
    fragColor = vec4(vColor * (core + glow), 1.0);
}
"""

        // A bundle is one quad between two chunk summary points, its width in pixels.
        private const val BUNDLE_VS = """#version 300 es
precision highp float;
layout(location = 0) in vec2 aCorner;
layout(location = 1) in vec3 aA;
layout(location = 2) in vec3 aB;
layout(location = 3) in float aWidth;
layout(location = 4) in vec3 aColor;
uniform mat4 uVP;
uniform vec2 uViewport;
out vec3 vColor;
out float vSide;
void main() {
    vec4 a = uVP * vec4(aA, 1.0);
    vec4 b = uVP * vec4(aB, 1.0);
    if (a.w <= 1e-4 || b.w <= 1e-4) { gl_Position = vec4(2.0, 2.0, 2.0, 1.0); vColor = vec3(0.0); vSide = 0.0; return; }
    vec2 sa = a.xy / a.w * uViewport * 0.5;
    vec2 sb = b.xy / b.w * uViewport * 0.5;
    vec2 d = sb - sa;
    vec2 n = length(d) > 1e-3 ? normalize(vec2(-d.y, d.x)) : vec2(0.0, 1.0);
    vec4 p = mix(a, b, aCorner.x);
    vec2 offset = n * aCorner.y * max(aWidth, 1.0) * 0.5 / (uViewport * 0.5);
    gl_Position = vec4(p.xy + offset * p.w, p.z, p.w);
    // under a pixel, the quad stays a pixel wide and carries the coverage of its true width
    vColor = aColor * min(aWidth, 1.0);
    vSide = aCorner.y;
}
"""

        private const val BUNDLE_FS = """#version 300 es
precision mediump float;
in vec3 vColor;
in float vSide;
out vec4 fragColor;
void main() { fragColor = vec4(vColor * (1.0 - vSide * vSide), 1.0); }
"""
    }
}
