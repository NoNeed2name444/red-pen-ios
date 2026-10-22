package com.stethoscore.app.ui.map

import android.content.res.AssetManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.opengl.GLES30
import android.util.Log
import com.stethoscore.app.map.EarthMaps
import com.stethoscore.app.map.SpaceBodies
import com.stethoscore.app.map.SpaceShaders
import com.stethoscore.app.map.SpaceStyle
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import kotlin.concurrent.thread
import kotlin.math.max
import kotlin.math.min

/**
 * Draws the Space theme's bodies and their links' beams (SpaceShaders) for [GlMapRenderer]:
 * one program per style, one camera-facing billboard per body, bodies drawn far to near with
 * premultiplied blending (a body hides what is behind it; its glows add), and the beams
 * before them. A style whose shader does not build on this device is left as points.
 */
internal class SpaceGl(private val assets: AssetManager?) {
    private val programs = IntArray(6)
    private var linkProgram = 0
    private var quadVbo = 0
    private var stripVbo = 0
    private var bodyVbo = 0
    private var beamVbo = 0
    private var bodyVao = 0
    private var beamVao = 0
    private var dayTexture = 0
    private var auxTexture = 0
    private var earthReady = false
    private var bodyBuffer: FloatBuffer = floats(96 * SpaceBodies.STRIDE)
    private var beamBuffer: FloatBuffer = floats(64 * SpaceBodies.BEAM_STRIDE)
    private var maxTexture = 2048

    /** Called on the GL thread with a new context; marks which styles can be drawn. */
    fun create(bodies: SpaceBodies, detail: Float) {
        for (style in SpaceStyle.entries) {
            programs[style.code] = runCatching { buildProgram(SpaceShaders.bodyVertex, SpaceShaders.fragment(style)) }
                .onFailure { Log.w("SpaceGl", "${style.label}: ${it.message}") }.getOrDefault(0)
            bodies.enabled[style.code] = programs[style.code] != 0
        }
        linkProgram = runCatching { buildProgram(SpaceShaders.linkVertex, SpaceShaders.link) }
            .onFailure { Log.w("SpaceGl", "links: ${it.message}") }.getOrDefault(0)
        val ids = IntArray(4)
        GLES30.glGenBuffers(4, ids, 0)
        quadVbo = ids[0]; stripVbo = ids[1]; bodyVbo = ids[2]; beamVbo = ids[3]
        val quad = floatArrayOf(-1f, -1f, 1f, -1f, 1f, 1f, -1f, -1f, 1f, 1f, -1f, 1f)
        GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, quadVbo)
        GLES30.glBufferData(GLES30.GL_ARRAY_BUFFER, quad.size * 4, floats(quad.size).put(quad).flip(), GLES30.GL_STATIC_DRAW)
        val strip = floatArrayOf(0f, -1f, 1f, -1f, 1f, 1f, 0f, -1f, 1f, 1f, 0f, 1f)
        GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, stripVbo)
        GLES30.glBufferData(GLES30.GL_ARRAY_BUFFER, strip.size * 4, floats(strip.size).put(strip).flip(), GLES30.GL_STATIC_DRAW)
        GLES30.glGenVertexArrays(2, ids, 0)
        bodyVao = ids[0]; beamVao = ids[1]
        GLES30.glBindVertexArray(bodyVao)
        GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, quadVbo)
        GLES30.glEnableVertexAttribArray(0); GLES30.glVertexAttribPointer(0, 2, GLES30.GL_FLOAT, false, 8, 0)
        for (loc in 1..4) { GLES30.glEnableVertexAttribArray(loc); GLES30.glVertexAttribDivisor(loc, 1) }
        GLES30.glBindVertexArray(beamVao)
        GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, stripVbo)
        GLES30.glEnableVertexAttribArray(0); GLES30.glVertexAttribPointer(0, 2, GLES30.GL_FLOAT, false, 8, 0)
        GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, beamVbo)
        val stride = SpaceBodies.BEAM_STRIDE * 4
        for ((loc, comps, off) in listOf(Triple(1, 4, 0), Triple(2, 4, 16), Triple(3, 2, 32))) {
            GLES30.glEnableVertexAttribArray(loc)
            GLES30.glVertexAttribPointer(loc, comps, GLES30.GL_FLOAT, false, stride, off)
            GLES30.glVertexAttribDivisor(loc, 1)
        }
        GLES30.glBindVertexArray(0)
        val range = IntArray(1)
        GLES30.glGetIntegerv(GLES30.GL_MAX_TEXTURE_SIZE, range, 0)
        maxTexture = range[0]
        // a new context has no textures: the maps are made again (decoded once per process)
        GLES30.glGenTextures(2, ids, 0)
        dayTexture = ids[0]; auxTexture = ids[1]
        earthReady = false
        if (programs[SpaceStyle.ROCKY.code] != 0) EarthLoader.request(assets, EarthMaps.useLarge(maxTexture, Runtime.getRuntime().maxMemory(), detail))
    }

    /**
     * Draws the beams, then the bodies, with premultiplied blending; restores additive blending.
     * [fade] is the depth band (SpaceDepthBand.uniform), [focalDp] the focal length in dp for the
     * shaders' detail by size, [forward] the camera's unit view direction.
     */
    fun draw(bodies: SpaceBodies, viewProj: FloatArray, eye: FloatArray, right: FloatArray, up: FloatArray, focal: Float, clock: Float, shaderDetail: Float,
             fade: FloatArray = FloatArray(4), focalDp: Float = 0f, forward: FloatArray = FloatArray(3)) {
        if (!earthReady) uploadEarth()
        GLES30.glBlendFunc(GLES30.GL_ONE, GLES30.GL_ONE_MINUS_SRC_ALPHA)
        if (bodies.beamCount > 0 && linkProgram != 0) {
            beamBuffer = ensure(beamBuffer, bodies.beamCount * SpaceBodies.BEAM_STRIDE)
            beamBuffer.put(bodies.beams, 0, bodies.beamCount * SpaceBodies.BEAM_STRIDE).flip()
            GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, beamVbo)
            GLES30.glBufferData(GLES30.GL_ARRAY_BUFFER, bodies.beamCount * SpaceBodies.BEAM_STRIDE * 4, beamBuffer, GLES30.GL_STREAM_DRAW)
            val p = linkProgram
            GLES30.glUseProgram(p)
            GLES30.glUniformMatrix4fv(loc(p, "uVP"), 1, false, viewProj, 0)
            GLES30.glUniform3fv(loc(p, "uEye"), 1, eye, 0)
            GLES30.glUniform1f(loc(p, "uUnit"), bodies.nodeRadius)
            GLES30.glUniform1f(loc(p, "uHalf"), 0.18f)
            GLES30.glUniform1f(loc(p, "uFocal"), focal)
            GLES30.glUniform1f(loc(p, "rpClock"), clock)
            GLES30.glUniform1f(loc(p, "rpMotion"), 1f)
            GLES30.glUniform1f(loc(p, "rpEnergy"), 1f)
            GLES30.glUniform1f(loc(p, "rpSolid"), 0f)
            GLES30.glUniform1f(loc(p, "rpReach"), 0.75f)
            GLES30.glUniform4fv(loc(p, "rpFade"), 1, fade, 0)
            GLES30.glBindVertexArray(beamVao)
            GLES30.glDrawArraysInstanced(GLES30.GL_TRIANGLES, 0, 6, bodies.beamCount)
        }
        if (bodies.count > 0) {
            bodyBuffer = ensure(bodyBuffer, bodies.count * SpaceBodies.STRIDE)
            bodyBuffer.put(bodies.data, 0, bodies.count * SpaceBodies.STRIDE).flip()
            GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, bodyVbo)
            GLES30.glBufferData(GLES30.GL_ARRAY_BUFFER, bodies.count * SpaceBodies.STRIDE * 4, bodyBuffer, GLES30.GL_STREAM_DRAW)
            GLES30.glBindVertexArray(bodyVao)
            val stride = SpaceBodies.STRIDE * 4
            for (style in SpaceStyle.entries) {
                val from = bodies.styleStart[style.code]; val to = bodies.styleStart[style.code + 1]
                val p = programs[style.code]
                if (to <= from || p == 0) continue
                for (k in 0 until 4) GLES30.glVertexAttribPointer(1 + k, 4, GLES30.GL_FLOAT, false, stride, from * stride + k * 16)
                GLES30.glUseProgram(p)
                GLES30.glUniformMatrix4fv(loc(p, "uVP"), 1, false, viewProj, 0)
                GLES30.glUniform3fv(loc(p, "uEye"), 1, eye, 0)
                GLES30.glUniform3fv(loc(p, "uRight"), 1, right, 0)
                GLES30.glUniform3fv(loc(p, "uUp"), 1, up, 0)
                GLES30.glUniform1f(loc(p, "uExtent"), style.extent)
                GLES30.glUniform1f(loc(p, "uFocal"), focal)
                GLES30.glUniform1f(loc(p, "rpClock"), clock)
                GLES30.glUniform1f(loc(p, "rpMotion"), 1f)
                GLES30.glUniform1f(loc(p, "rpDetail"), shaderDetail)
                GLES30.glUniform1f(loc(p, "rpDisk"), 1f)
                GLES30.glUniform4fv(loc(p, "rpFade"), 1, fade, 0)
                GLES30.glUniform1f(loc(p, "rpFocal"), focalDp)
                GLES30.glUniform3fv(loc(p, "uForward"), 1, forward, 0)
                when (style) {
                    SpaceStyle.ROCKY -> {
                        GLES30.glActiveTexture(GLES30.GL_TEXTURE2); GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, dayTexture)
                        GLES30.glActiveTexture(GLES30.GL_TEXTURE3); GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, auxTexture)
                        GLES30.glActiveTexture(GLES30.GL_TEXTURE0)
                        GLES30.glUniform1i(loc(p, "rpEarthDay"), 2)
                        GLES30.glUniform1i(loc(p, "rpEarthAux"), 3)
                        GLES30.glUniform1f(loc(p, "uEarthReady"), if (earthReady) 1f else 0f)
                    }
                    SpaceStyle.GAS_GIANT -> {
                        // after Jupiter and Saturn: cream zones, tan belts, rust, greyer poles
                        GLES30.glUniform1f(loc(p, "rpRinged"), 1f)
                        GLES30.glUniform3f(loc(p, "rpTintA"), 0.96f, 0.9f, 0.78f)
                        GLES30.glUniform3f(loc(p, "rpTintB"), 0.83f, 0.66f, 0.47f)
                        GLES30.glUniform3f(loc(p, "rpTintC"), 0.62f, 0.36f, 0.22f)
                        GLES30.glUniform3f(loc(p, "rpTintD"), 0.56f, 0.52f, 0.5f)
                    }
                    else -> {}
                }
                GLES30.glDrawArraysInstanced(GLES30.GL_TRIANGLES, 0, 6, to - from)
            }
        }
        GLES30.glBindVertexArray(0)
        GLES30.glBlendFunc(GLES30.GL_ONE, GLES30.GL_ONE)
    }

    private fun uploadEarth() {
        val maps = EarthLoader.ready ?: return
        GLES30.glPixelStorei(GLES30.GL_UNPACK_ALIGNMENT, 1)
        upload(dayTexture, GLES30.GL_SRGB8_ALPHA8, GLES30.GL_RGBA, maps.dayWidth, maps.dayHeight, maps.day)
        upload(auxTexture, GLES30.GL_RG8, GLES30.GL_RG, maps.auxWidth, maps.auxHeight, maps.aux)
        GLES30.glPixelStorei(GLES30.GL_UNPACK_ALIGNMENT, 4)
        earthReady = true
    }

    private fun upload(texture: Int, internal: Int, format: Int, w: Int, h: Int, pixels: ByteBuffer) {
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, texture)
        pixels.position(0)
        GLES30.glTexImage2D(GLES30.GL_TEXTURE_2D, 0, internal, w, h, 0, format, GLES30.GL_UNSIGNED_BYTE, pixels)
        GLES30.glGenerateMipmap(GLES30.GL_TEXTURE_2D)
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MIN_FILTER, GLES30.GL_LINEAR_MIPMAP_LINEAR)
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MAG_FILTER, GLES30.GL_LINEAR)
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_WRAP_S, EarthMaps.WRAP_S)
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_WRAP_T, EarthMaps.WRAP_T)
        // up to 8x anisotropy towards the limb, where the device has it
        if (GLES30.glGetString(GLES30.GL_EXTENSIONS)?.contains("GL_EXT_texture_filter_anisotropic") == true) {
            val most = FloatArray(1)
            GLES30.glGetFloatv(MAX_ANISOTROPY, most, 0)
            GLES30.glTexParameterf(GLES30.GL_TEXTURE_2D, ANISOTROPY, min(8f, max(1f, most[0])))
        }
    }

    private fun loc(program: Int, name: String) = GLES30.glGetUniformLocation(program, name)

    private fun ensure(buffer: FloatBuffer, size: Int): FloatBuffer {
        if (buffer.capacity() >= size) { buffer.clear(); return buffer }
        return floats(max(size, buffer.capacity() * 2))
    }

    companion object {
        private const val ANISOTROPY = 0x84FE
        private const val MAX_ANISOTROPY = 0x84FF

        private fun floats(n: Int): FloatBuffer = ByteBuffer.allocateDirect(n * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()

        fun buildProgram(vs: String, fs: String): Int {
            fun shader(type: Int, source: String): Int {
                val s = GLES30.glCreateShader(type)
                GLES30.glShaderSource(s, source); GLES30.glCompileShader(s)
                val ok = IntArray(1); GLES30.glGetShaderiv(s, GLES30.GL_COMPILE_STATUS, ok, 0)
                if (ok[0] == 0) { val log = GLES30.glGetShaderInfoLog(s); GLES30.glDeleteShader(s); error("did not compile: $log") }
                return s
            }
            val v = shader(GLES30.GL_VERTEX_SHADER, vs)
            val f = shader(GLES30.GL_FRAGMENT_SHADER, fs)
            val p = GLES30.glCreateProgram()
            GLES30.glAttachShader(p, v); GLES30.glAttachShader(p, f)
            GLES30.glLinkProgram(p)
            GLES30.glDeleteShader(v); GLES30.glDeleteShader(f)
            val ok = IntArray(1); GLES30.glGetProgramiv(p, GLES30.GL_LINK_STATUS, ok, 0)
            if (ok[0] == 0) { val log = GLES30.glGetProgramInfoLog(p); GLES30.glDeleteProgram(p); error("did not link: $log") }
            return p
        }
    }
}

/**
 * The Earth's maps (assets/earth, NASA imagery; SOURCES.md beside them), decoded off the GL
 * thread once per process and packed as the rocky planet's shader reads them: the day colour
 * (sRGB) with the cloud cover in alpha, and the lights at night (red) with the open water
 * (green). Until they are ready the planet is drawn from noise instead; a failure is not kept,
 * so the next request tries again.
 */
internal object EarthLoader {
    class Maps(val day: ByteBuffer, val dayWidth: Int, val dayHeight: Int, val aux: ByteBuffer, val auxWidth: Int, val auxHeight: Int)

    @Volatile var ready: Maps? = null; private set
    @Volatile private var loading = false

    @Synchronized fun request(assets: AssetManager?, large: Boolean) {
        if (assets == null || ready != null || loading) return
        loading = true
        thread(name = "earth-maps", isDaemon = true, priority = Thread.MIN_PRIORITY) {
            ready = runCatching { load(assets, large) }.onFailure { Log.w("EarthLoader", "maps not loaded: ${it.message}") }.getOrNull()
            loading = false
        }
    }

    private fun decode(assets: AssetManager, name: String, sample: Int): Bitmap =
        assets.open("${EarthMaps.FOLDER}/$name").use { stream ->
            BitmapFactory.decodeStream(stream, null, BitmapFactory.Options().apply { inSampleSize = sample; inPreferredConfig = Bitmap.Config.ARGB_8888 })
        } ?: error("$name did not decode")

    private fun load(assets: AssetManager, large: Boolean): Maps {
        val sample = if (large) 1 else EarthMaps.LARGE_WIDTH / EarthMaps.SMALL_WIDTH
        val day = decode(assets, EarthMaps.DAY, sample)
        val clouds = decode(assets, EarthMaps.CLOUDS, sample)
        val w = day.width; val h = day.height
        val dayBytes = ByteArray(w * h * 4)
        val rowA = IntArray(w); val rowB = IntArray(w)
        for (y in 0 until h) {
            day.getPixels(rowA, 0, w, 0, y, w, 1)
            clouds.getPixels(rowB, 0, w, 0, y * clouds.height / h, min(w, clouds.width), 1)
            EarthMaps.packDay(rowA, rowB, dayBytes, y * w * 4, w)
        }
        day.recycle(); clouds.recycle()
        val lights = decode(assets, EarthMaps.LIGHTS, 1)
        val water = decode(assets, EarthMaps.WATER, 1)
        val aw = lights.width; val ah = lights.height
        val auxBytes = ByteArray(aw * ah * 2)
        val rowC = IntArray(aw); val rowD = IntArray(aw)
        for (y in 0 until ah) {
            lights.getPixels(rowC, 0, aw, 0, y, aw, 1)
            water.getPixels(rowD, 0, aw, 0, y * water.height / ah, min(aw, water.width), 1)
            EarthMaps.packAux(rowC, rowD, auxBytes, y * aw * 2, aw)
        }
        lights.recycle(); water.recycle()
        fun direct(bytes: ByteArray) = ByteBuffer.allocateDirect(bytes.size).order(ByteOrder.nativeOrder()).put(bytes).also { it.position(0) }
        return Maps(direct(dayBytes), w, h, direct(auxBytes), aw, ah)
    }
}
