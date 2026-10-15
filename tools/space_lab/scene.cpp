// The Space lab's ray caster (see lab.py): one body of each style, placed as
// GraphStyleKit and GraphStyleAnimator place its pieces, shaded per pixel by
// the real shader modifiers (shaders.h, generated). The scene is in view
// space: the camera at the origin looking down -z, y up, so the world and
// view transforms are the same.
#include "shaders.h"
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>
#include <functional>

static float3 v3(float x, float y, float z) { return mk_float3(x, y, z); }
static float3 nrm(float3 a) { return normalize(a); }

struct R3 { float3 x, y, z; };  // rotation, by columns
static R3 ident() { return {v3(1, 0, 0), v3(0, 1, 0), v3(0, 0, 1)}; }
static float3 act(const R3 &r, float3 v) { return r.x * v.x + r.y * v.y + r.z * v.z; }
static R3 mul(const R3 &a, const R3 &b) { return {act(a, b.x), act(a, b.y), act(a, b.z)}; }
static R3 rot(float3 axis, float angle) {
    float3 k = nrm(axis);
    float c = std::cos(angle), s = std::sin(angle);
    auto r = [&](float3 v) { return v * c + cross(k, v) * s + k * (dot(k, v) * (1 - c)); };
    return {r(v3(1, 0, 0)), r(v3(0, 1, 0)), r(v3(0, 0, 1))};
}
// a turn whose y is `along` and whose z leans as far towards the eye as it can
static R3 facing(float3 y, float3 eye) {
    float3 z = eye - y * dot(y, eye);
    if (dot(z, z) < 1e-6f) z = cross(y, std::fabs(y.x) < 0.9f ? v3(1, 0, 0) : v3(0, 1, 0));
    z = nrm(z);
    return {cross(y, z), y, z};
}

static float4x4 trs(float3 t, const R3 &r, float3 s) {
    float4x4 m;
    m.c[0] = mk_float4(r.x * s.x, 0);
    m.c[1] = mk_float4(r.y * s.y, 0);
    m.c[2] = mk_float4(r.z * s.z, 0);
    m.c[3] = mk_float4(t, 1);
    return m;
}

static bool invert(const float4x4 &m, float4x4 &out) {
    float a[4][8];
    for (int r = 0; r < 4; r++)
        for (int c = 0; c < 4; c++) { a[r][c] = m.c[c][r]; a[r][c + 4] = r == c ? 1 : 0; }
    for (int c = 0; c < 4; c++) {
        int p = c;
        for (int r = c + 1; r < 4; r++) if (std::fabs(a[r][c]) > std::fabs(a[p][c])) p = r;
        if (std::fabs(a[p][c]) < 1e-12f) return false;
        for (int k = 0; k < 8; k++) std::swap(a[c][k], a[p][k]);
        float d = a[c][c];
        for (int k = 0; k < 8; k++) a[c][k] /= d;
        for (int r = 0; r < 4; r++) if (r != c) {
            float f = a[r][c];
            for (int k = 0; k < 8; k++) a[r][k] -= f * a[c][k];
        }
    }
    for (int r = 0; r < 4; r++) for (int c = 0; c < 4; c++) out.c[c][r] = a[r][c + 4];
    return true;
}
static float3 point(const float4x4 &m, float3 p) { float4 q = m * mk_float4(p, 1); return v3(q.x, q.y, q.z); }
static float3 dirn(const float4x4 &m, float3 p) { float4 q = m * mk_float4(p, 0); return v3(q.x, q.y, q.z); }

typedef void (*Entry)(SCNShaderSurface &, const SCNNodeBuffer &, const SCNFrameBuffer &);

struct Obj {
    bool sphere;
    float4x4 M, inv;
    Entry fn;
    std::function<void()> args;
    float opacity;
};

static std::vector<Obj> objs;
static void add(bool sphere, float4x4 M, Entry fn, std::function<void()> args, float opacity = 1) {
    Obj o{sphere, M, M, fn, args, opacity};
    invert(M, o.inv);
    objs.push_back(o);
}

// the frame's values
static float T = 7.3f;        // the shaders' clock
static float M = 0;           // the body's motion level (0 at rest)
static float3 VEL;            // its velocity (view space)
static const float3 KEY = v3(-0.75f, 0.4f, 0.45f);
static float4 SUN0, SUN1, SUN2, SUN3;

#define COMMON(ns) ns::rpClock = T; ns::rpMotion = 1; ns::rpProbe = 0;
#define LIGHTS(ns) ns::rpSun0 = SUN0; ns::rpSun1 = SUN1; ns::rpSun2 = SUN2; ns::rpSun3 = SUN3; ns::rpKey = nrm(KEY);

static float halfHeight = 3.2f;
static float3 BODY;

// the note's tilt frame, as GraphStyleKit seeds it, leaning into the drag
static R3 tiltFrame(float lean, float roll, float yaw, float gain) {
    R3 flat = rot(v3(1, 0, 0), lean - 1.5707963f);
    R3 rolled = rot(v3(0, 0, 1), roll);
    R3 turned = rot(v3(0, 1, 0), yaw);
    R3 base = mul(turned, mul(rolled, flat));
    if (M > 0) {
        float3 n0 = act(base, v3(0, 0, 1));
        float3 t = cross(n0, VEL) * gain;
        float len = length(t);
        if (len > 0.6f) t = t * (0.6f / len);
        if (length(t) > 1e-5f) base = mul(rot(t, length(t)), base);
    }
    return base;
}

// the billboard glow in front of the body: lifted towards the eye, screen
// aligned, stretched along the motion, turned by `turn`
static float4x4 billboard(float lift, float side, float code, float turn, float stretchGain, float swell) {
    float3 toEye = nrm(BODY * -1.0f);
    float3 at = BODY + toEye * lift;
    // GraphSim.ringFit: the lifted plane shrunk so its limb meets the body's
    float dist = length(BODY);
    float fit = std::fmin(std::fmax((dist - 1.08f) / std::sqrt(std::fmax(dist * dist - 1, 1e-4f)), 0.5f), 1.05f);
    float angle = 0;
    float stretch = 1, along = fit, across = fit;
    if (M > 0.002f) {
        angle = std::atan2(VEL.y, VEL.x);
        stretch = 1 + 0.22f * M * stretchGain;
        float sw = 1 + swell * M;
        along = fit * stretch * sw;
        across = fit * sw / std::sqrt(stretch);
    }
    // holder (identity) > stretch (turned by angle, scaled along/across) > leaf (turned by turn - angle)
    R3 rs = rot(v3(0, 0, 1), angle);
    R3 rl = rot(v3(0, 0, 1), turn - angle);
    float4x4 S = trs(at, rs, v3(along, across, 1));
    float4x4 L = trs(v3(0, 0, 0), rl, v3(side, side, code));
    float4x4 out;
    for (int c = 0; c < 4; c++) out.c[c] = S * L.c[c];
    return out;
}

static void blackHole() {
    halfHeight = 3.0f;
    BODY = v3(0, 0, -halfHeight / std::tan(27.5f * 3.14159265f / 180));
    float r = 1;
    R3 base = tiltFrame(0.14f, 0.12f, 0.5f, 0.22f);
    R3 bodyR = mul(base, rot(v3(1, 0, 0), 1.5707963f));
    add(true, trs(BODY, bodyR, v3(r, r, r)), nullptr, [] {});
    float3 n = act(base, v3(0, 0, 1));
    float3 toEye = nrm(BODY * -1.0f);
    float3 q = cross(toEye, n);
    float k = std::fmin(length(q), 1.0f);
    float turn = std::atan2(q.y, q.x);
    float above = dot(n, toEye) >= 0 ? 1 : -1;
    float v = (std::floor(k * 255) + 0.02f + M * 0.96f) / 256;
    add(false, billboard(r * 1.08f, r * 6.0f, 2 + v * above, turn, 0, 0), sh_bhRing::entry,
        [] { COMMON(sh_bhRing) sh_bhRing::rpDetail = 1; sh_bhRing::rpDisk = 1; }, 1);
}

static void sun() {
    halfHeight = 2.4f;
    BODY = v3(0, 0, -halfHeight / std::tan(27.5f * 3.14159265f / 180));
    float br = 1.1f;
    R3 base = tiltFrame(0.33f, 0.12f, 0.5f, 0.1f);
    R3 bodyR = mul(mul(base, rot(v3(1, 0, 0), 1.5707963f)), rot(v3(0, 1, 0), 0.4f));
    add(true, trs(BODY, bodyR, v3(br, br, br * (1 + 0.004f * M))), sh_sunBody::entry,
        [] { COMMON(sh_sunBody) sh_sunBody::rpDetail = 1; });
    float s = std::floor(0.3f * 32) / 32;
    float code = 2 + s + M * (0.96f / 32);
    add(false, billboard(br * 1.08f, br * 8, code, 0, 0, 0), sh_sunCorona::entry,
        [] { COMMON(sh_sunCorona) sh_sunCorona::rpDetail = 1; }, 0.85f + 0.15f * M);
}

static float3 ROCK[4] = {v3(0.02f, 0.08f, 0.24f), v3(0.05f, 0.36f, 0.45f), v3(0.16f, 0.3f, 0.1f), v3(0.66f, 0.52f, 0.32f)};
static float3 GAS[4] = {v3(0.93f, 0.85f, 0.68f), v3(0.78f, 0.56f, 0.36f), v3(0.6f, 0.33f, 0.2f), v3(0.5f, 0.56f, 0.62f)};

static void rocky() {
    halfHeight = 2.3f;
    BODY = v3(0, 0, -halfHeight / std::tan(27.5f * 3.14159265f / 180));
    float br = 0.9f;
    R3 base = tiltFrame(0.33f, 0.12f, 0.5f, 0.1f);
    R3 bodyR = mul(mul(base, rot(v3(1, 0, 0), 1.5707963f)), rot(v3(0, 1, 0), 2.2f));
    add(true, trs(BODY, bodyR, v3(br, br, br)), sh_rockBody::entry, [] {
        COMMON(sh_rockBody) LIGHTS(sh_rockBody) sh_rockBody::rpDetail = 1;
        sh_rockBody::rpTintA = ROCK[0]; sh_rockBody::rpTintB = ROCK[1];
        sh_rockBody::rpTintC = ROCK[2]; sh_rockBody::rpTintD = ROCK[3];
    });
    add(false, billboard(br * 1.08f, br * 3, 1, 0, 0, 0), sh_halo::entry, [] {
        sh_halo::rpProbe = 0; LIGHTS(sh_halo) sh_halo::rpThin = 1; sh_halo::rpTintA = v3(0.38f, 0.64f, 1.0f);
    }, 0.85f + 0.15f * M);
    // the moon on its orbit (lagging when dragged)
    float3 e1 = act(base, v3(1, 0, 0));
    float3 n = act(base, v3(0, 0, 1));
    float3 e2 = cross(n, e1);
    float ang = 2.6f;
    float3 off = (e1 * std::cos(ang) + e2 * std::sin(ang)) * (br * 2.3f);
    if (M > 0) off = off - VEL * 0.35f;
    float ms = br * 0.27f;
    add(true, trs(BODY + off, ident(), v3(ms, ms, ms)), sh_moonBody::entry, [] {
        sh_moonBody::rpProbe = 0; LIGHTS(sh_moonBody) sh_moonBody::rpDetail = 1;
    });
}

static void gasGiant() {
    halfHeight = 3.0f;
    BODY = v3(0, 0, -halfHeight / std::tan(27.5f * 3.14159265f / 180));
    float br = 1.15f;
    R3 base = tiltFrame(0.33f, 0.12f, 0.5f, 0.22f);
    R3 bodyR = mul(mul(base, rot(v3(1, 0, 0), 1.5707963f)), rot(v3(0, 1, 0), 1.0f));
    add(true, trs(BODY, bodyR, v3(br, br * 0.94f, br * (1 + 0.004f * M))), sh_gasBody::entry, [] {
        COMMON(sh_gasBody) LIGHTS(sh_gasBody) sh_gasBody::rpDetail = 1; sh_gasBody::rpRinged = 1;
        sh_gasBody::rpTintA = GAS[0]; sh_gasBody::rpTintB = GAS[1];
        sh_gasBody::rpTintC = GAS[2]; sh_gasBody::rpTintD = GAS[3];
    });
    float side = br * 4.8f;
    R3 diskR = mul(base, rot(v3(0, 0, 1), 0.7f));
    add(false, trs(BODY, diskR, v3(side, side, side * (1 + M))), sh_gasRing::entry,
        [] { sh_gasRing::rpProbe = 0; LIGHTS(sh_gasRing) });
    add(false, billboard(br * 1.08f, br * 3, 1, 0, 0, 0), sh_halo::entry, [] {
        sh_halo::rpProbe = 0; LIGHTS(sh_halo) sh_halo::rpThin = 0; sh_halo::rpTintA = v3(0.5f, 0.4f, 0.27f);
    }, 0.85f + 0.15f * M);
}

static void pulsar() {
    halfHeight = 3.6f;
    BODY = v3(0, 0, -halfHeight / std::tan(27.5f * 3.14159265f / 180));
    float r = 1, br = 0.3f;
    R3 base = tiltFrame(0.33f, 0.12f, 0.5f, 0.22f);
    if (M > 0) base = mul(rot(act(base, v3(1, 0, 0)), M * 0.35f * std::sin(T * 7)), base);
    add(true, trs(BODY, mul(base, rot(v3(1, 0, 0), 1.5707963f)), v3(br, br, br)), sh_pulsarCore::entry,
        [] { COMMON(sh_pulsarCore) });
    float3 n = act(base, v3(0, 0, 1));
    float3 e1 = act(base, v3(1, 0, 0));
    float3 e2 = cross(n, e1);
    float3 toEye = nrm(BODY * -1.0f);
    // the nebula: +y along the axis as seen
    float ax = n.x, ay = n.y;
    float edgeOn = std::fmin(length(cross(toEye, n)), 1.0f);
    float turn = std::sqrt(ax * ax + ay * ay) > 1e-5f ? std::atan2(ay, ax) - 1.5707963f : 0;
    add(false, billboard(r * 0.45f * 1.08f, r * 5, 2 + edgeOn, turn, 0.4f, 0), sh_pulsarGlow::entry,
        [] { COMMON(sh_pulsarGlow) }, 0.85f + 0.15f * M);
    float period = 0.75f;
    float tt = T / period;
    float phase = (tt - std::floor(tt)) * 6.2831853f + 0.3f * 6.2831853f;
    float3 around = e1 * std::cos(phase) + e2 * std::sin(phase);
    float3 b = nrm(n * std::cos(0.61f) + around * std::sin(0.61f));
    float face = std::fabs(dot(b, toEye));
    float w = r * 0.9f * 2, lg = r * 6 * 2 * (1 + 0.35f * M);
    add(false, trs(BODY, facing(b, toEye), v3(w, lg, w * (1 + face))), sh_pulsarBeam::entry,
        [] { COMMON(sh_pulsarBeam) });
}

static void comet() {
    halfHeight = 3.4f;
    BODY = v3(-1.2f, 1.0f, -halfHeight / std::tan(27.5f * 3.14159265f / 180));
    float r = 1, br = 0.3f;
    R3 base = tiltFrame(0.33f, 0.12f, 0.5f, 0.22f);
    float nr = br * 0.35f;
    add(true, trs(BODY, mul(base, rot(v3(1, 0, 0), 1.5707963f)), v3(nr, nr, nr)), sh_cometNucleus::entry,
        [] { sh_cometNucleus::rpProbe = 0; LIGHTS(sh_cometNucleus) });
    add(false, billboard(r * 0.45f * 1.08f, r * 3.2f, 1, 0, 0.4f, 0), sh_cometComa::entry,
        [] { COMMON(sh_cometComa) LIGHTS(sh_cometComa) }, 0.85f + 0.15f * M);
    float3 away = nrm(KEY) * -1.0f;
    float3 dust = away;
    float speed = length(VEL);
    if (speed > 1e-4f) {
        float3 acr = VEL - away * dot(VEL, away);
        float lag = std::fmin(speed * 2.5f, 0.7f);
        dust = nrm(away - nrm(acr) * lag);
    }
    float3 toEye = nrm(BODY * -1.0f);
    float lg = r * 7 * (1 + 1.2f * M), wd = r * 2 * 0.8f;
    add(false, trs(BODY + away * (lg * 0.5f), facing(away, toEye), v3(wd, lg, wd * (1 + M))), sh_cometTail::entry,
        [] { COMMON(sh_cometTail) });
    float dl = r * 7 * 0.85f * (1 + 0.9f * M), dw = r * 2 * 1.5f;
    R3 tr = facing(dust, toEye);
    if (dot(tr.x, dust - away) < 0) tr = mul(tr, rot(v3(0, 1, 0), 3.14159265f));
    add(false, trs(BODY + dust * (dl * 0.5f), tr, v3(dw, dl, dw * (1 + M))), sh_cometDust::entry,
        [] { COMMON(sh_cometDust) });
}

static float srgb(float c) {
    c = c < 0 ? 0 : (c > 1 ? 1 : c);
    return c <= 0.0031308f ? 12.92f * c : 1.055f * std::pow(c, 1 / 2.4f) - 0.055f;
}

int main(int argc, char **argv) {
    if (argc < 5) { std::fprintf(stderr, "lab <body> <rest|dragged> <size> <out.ppm>\n"); return 2; }
    std::string body = argv[1];
    bool dragged = std::string(argv[2]) == "dragged";
    int size = std::atoi(argv[3]);
    if (dragged) { M = 0.85f; VEL = v3(0, 1.6f, 0); }
    SUN0 = SUN1 = SUN2 = SUN3 = mk_float4(0, 0, 0, 0);
    if (body == "blackHole") blackHole();
    else if (body == "sun") sun();
    else if (body == "rocky") rocky();
    else if (body == "gasGiant") gasGiant();
    else if (body == "pulsar") pulsar();
    else comet();
    float tanHalf = std::tan(27.5f * 3.14159265f / 180);
    std::vector<unsigned char> img(size * size * 3);
    SCNFrameBuffer frame{};
    const int ss = 2;
    for (int py = 0; py < size; py++) {
        for (int px = 0; px < size; px++) {
            float3 acc = mk_float3(0.0f);
            for (int sy = 0; sy < ss; sy++) for (int sx = 0; sx < ss; sx++) {
                float x = ((px + (sx + 0.5f) / ss) / size * 2 - 1) * tanHalf;
                float y = (1 - (py + (sy + 0.5f) / ss) / size * 2) * tanHalf;
                float3 d = nrm(v3(x, y, -1));
                float best = 1e9f;
                int hit = -1;
                float3 hitLocal;
                for (size_t k = 0; k < objs.size(); k++) {
                    if (!objs[k].sphere) continue;
                    float3 o = point(objs[k].inv, mk_float3(0.0f));
                    float3 dl = dirn(objs[k].inv, d);
                    float a = dot(dl, dl), b = dot(o, dl), c = dot(o, o) - 1;
                    float disc = b * b - a * c;
                    if (disc < 0) continue;
                    float t = (-b - std::sqrt(disc)) / a;
                    if (t > 0 && t < best) { best = t; hit = (int)k; hitLocal = o + dl * t; }
                }
                float3 col = mk_float3(0.0f);
                if (hit >= 0) {
                    Obj &ob = objs[hit];
                    if (ob.fn) {
                        SCNShaderSurface s{};
                        float3 p = d * best;
                        float3 nl = hitLocal;
                        // the normal: the inverse transpose of the model
                        float3 nv;
                        nv = nrm(v3(dot(v3(ob.inv.c[0].x, ob.inv.c[0].y, ob.inv.c[0].z), nl),
                                    dot(v3(ob.inv.c[1].x, ob.inv.c[1].y, ob.inv.c[1].z), nl),
                                    dot(v3(ob.inv.c[2].x, ob.inv.c[2].y, ob.inv.c[2].z), nl)));
                        s.normal = nv; s.geometryNormal = nv;
                        s.view = nrm(p * -1.0f);
                        s.position = p;
                        s.diffuseTexcoord = mk_float2(0.5f + std::atan2(nl.x, nl.z) / 6.2831853f, std::acos(nl.y) / 3.14159265f);
                        SCNNodeBuffer nb{};
                        nb.modelTransform = ob.M; nb.modelViewTransform = ob.M;
                        ob.args();
                        ob.fn(s, nb, frame);
                        col = mk_float3(s.diffuse.x, s.diffuse.y, s.diffuse.z);
                    }
                }
                for (size_t k = 0; k < objs.size(); k++) {
                    Obj &ob = objs[k];
                    if (ob.sphere) continue;
                    float3 o = point(ob.inv, mk_float3(0.0f));
                    float3 dl = dirn(ob.inv, d);
                    if (std::fabs(dl.z) < 1e-9f) continue;
                    float t = -o.z / dl.z;
                    if (t <= 0 || t >= best) continue;
                    float3 h = o + dl * t;
                    if (std::fabs(h.x) > 0.5f || std::fabs(h.y) > 0.5f) continue;
                    SCNShaderSurface s{};
                    float3 p = d * t;
                    float3 nv = nrm(ob.M.c[2].xyz);
                    if (dot(nv, d) > 0) nv = nv * -1.0f;
                    s.normal = nv; s.geometryNormal = nv;
                    s.view = nrm(p * -1.0f);
                    s.position = p;
                    s.diffuseTexcoord = mk_float2(h.x + 0.5f, 0.5f - h.y);
                    SCNNodeBuffer nb{};
                    nb.modelTransform = ob.M; nb.modelViewTransform = ob.M;
                    ob.args();
                    ob.fn(s, nb, frame);
                    col = col + mk_float3(s.diffuse.x, s.diffuse.y, s.diffuse.z) * ob.opacity;
                }
                acc = acc + col;
            }
            acc = acc / float(ss * ss);
            unsigned char *q = &img[(py * size + px) * 3];
            q[0] = (unsigned char)(srgb(acc.x) * 255 + 0.5f);
            q[1] = (unsigned char)(srgb(acc.y) * 255 + 0.5f);
            q[2] = (unsigned char)(srgb(acc.z) * 255 + 0.5f);
        }
    }
    FILE *f = std::fopen(argv[4], "wb");
    std::fprintf(f, "P6\n%d %d\n255\n", size, size);
    std::fwrite(img.data(), 1, img.size(), f);
    std::fclose(f);
    return 0;
}
