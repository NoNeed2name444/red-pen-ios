// tools/atlas_lab's renderer: atlas structures (dump.swift's file) drawn with
// the atlas's own surface modifiers (shaders.h: AtlasShaders through
// tools/shader_check.py's stand-in for Metal, run per pixel) under a
// stand-in for AnatomyAtlasView's light (AtlasLight): a directional key
// from up and to the left of the eye, a faint fill from the eye, a studio of
// grey bands for ambient light and reflections, and screen-space ambient
// occlusion. A z-buffer rasteriser draws each structure into a G-buffer
// (supersampled), the occlusion is worked out from its depths, then every
// pixel is shaded: the surface modifier first (with screen derivatives from
// the neighbouring pixels, as a GPU has them), then a physically based
// light (GGX, Schlick's Fresnel, F0 0.04, Karis's split-sum fit for the
// studio's reflections). It is a stand-in, not SceneKit: the light's
// scaling, its occlusion and its tone are close, not exact.
//
//   lab <dump> <out.ppm> <width> <height> <dx,dy,dz> <margin> <frame filter|all> [ssao 0|1] [detail 0|1] [plain 0|1]
#include "shaders.h"
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

static float3 v3(float x, float y, float z) { return mk_float3(x, y, z); }
static float3 nrm(float3 a) { float l = length(a); return l > 0 ? a / l : a; }

struct Mesh {
    float3 colour; float rough; int surface; float3 axis; float bundle; float3 tendon; std::string name;
    std::vector<float3> p, n, relief; std::vector<float2> tc; std::vector<uint32_t> idx;
};

static std::vector<Mesh> load(const char *path) {
    std::vector<Mesh> out;
    FILE *f = std::fopen(path, "rb");
    if (!f) { std::perror(path); std::exit(2); }
    char magic[4];
    if (std::fread(magic, 1, 4, f) != 4 || std::memcmp(magic, "ATL3", 4) != 0) { std::fprintf(stderr, "not a dump\n"); std::exit(2); }
    auto u32 = [&]() { uint32_t v = 0; if (std::fread(&v, 4, 1, f) != 1) std::exit(3); return v; };
    auto f32 = [&]() { float v = 0; if (std::fread(&v, 4, 1, f) != 1) std::exit(3); return v; };
    uint32_t count = u32();
    for (uint32_t s = 0; s < count; s++) {
        Mesh m;
        float r = f32(), g = f32(), b = f32();
        m.colour = v3(r, g, b); m.rough = f32(); m.surface = (int)u32();
        float ax = f32(), ay = f32(), az = f32();
        m.axis = v3(ax, ay, az); m.bundle = f32();
        float tr = f32(), tg = f32(), tb = f32();
        m.tendon = v3(tr, tg, tb);
        uint32_t nl = u32(); m.name.resize(nl);
        if (nl && std::fread(&m.name[0], 1, nl, f) != nl) std::exit(3);
        uint32_t nv = u32(), nt = u32();
        std::vector<float> buf(nv * 3);
        if (nv && std::fread(buf.data(), 4, nv * 3, f) != nv * 3) std::exit(3);
        for (uint32_t i = 0; i < nv; i++) m.p.push_back(v3(buf[3 * i], buf[3 * i + 1], buf[3 * i + 2]));
        if (nv && std::fread(buf.data(), 4, nv * 3, f) != nv * 3) std::exit(3);
        for (uint32_t i = 0; i < nv; i++) m.n.push_back(v3(buf[3 * i], buf[3 * i + 1], buf[3 * i + 2]));
        if (nv && std::fread(buf.data(), 4, nv * 3, f) != nv * 3) std::exit(3);
        for (uint32_t i = 0; i < nv; i++) m.relief.push_back(v3(buf[3 * i], buf[3 * i + 1], buf[3 * i + 2]));
        if (nv && std::fread(buf.data(), 4, nv * 2, f) != nv * 2) std::exit(3);
        for (uint32_t i = 0; i < nv; i++) m.tc.push_back(mk_float2(buf[2 * i], buf[2 * i + 1]));
        m.idx.resize(nt * 3);
        if (nt && std::fread(m.idx.data(), 4, nt * 3, f) != nt * 3) std::exit(3);
        out.push_back(std::move(m));
    }
    std::fclose(f);
    return out;
}

// MARK: the light (AtlasLight's numbers)

static float KEY_PITCH = -0.5f, KEY_YAW = -0.45f, KEY = 850, FILL = 120, STUDIO = 0.7f;
// LAB_KEY, LAB_FILL, LAB_STUDIO, LAB_PITCH and LAB_YAW try other numbers without a rebuild
static void overrides() {
    if (const char *v = std::getenv("LAB_KEY")) KEY = (float)std::atof(v);
    if (const char *v = std::getenv("LAB_FILL")) FILL = (float)std::atof(v);
    if (const char *v = std::getenv("LAB_STUDIO")) STUDIO = (float)std::atof(v);
    if (const char *v = std::getenv("LAB_PITCH")) KEY_PITCH = (float)std::atof(v);
    if (const char *v = std::getenv("LAB_YAW")) KEY_YAW = (float)std::atof(v);
}
static const float BANDS[4][2] = {{0, 0.66f}, {0.42f, 0.56f}, {0.55f, 0.46f}, {1, 0.2f}};
static const float SSAO_INTENSITY = 1.1f, SSAO_RADIUS = 0.012f, SSAO_BIAS = 0.0004f, SSAO_DEPTH = 0.03f;
static float lin(float c) { return c <= 0.04045f ? c / 12.92f : std::pow((c + 0.055f) / 1.055f, 2.4f); }
static float srgb(float c) {
    c = c < 0 ? 0 : (c > 1 ? 1 : c);
    return c <= 0.0031308f ? 12.92f * c : 1.055f * std::pow(c, 1 / 2.4f) - 0.055f;
}
// the studio's radiance in a direction whose height is y (linear, before STUDIO)
static float studio(float y) {
    float v = std::acos(std::max(-1.0f, std::min(1.0f, y))) / 3.14159265f;
    for (int k = 0; k < 3; k++) {
        if (v <= BANDS[k + 1][0]) {
            float t = (v - BANDS[k][0]) / (BANDS[k + 1][0] - BANDS[k][0]);
            return lin(BANDS[k][1] + (BANDS[k + 1][1] - BANDS[k][1]) * t);
        }
    }
    return lin(BANDS[3][1]);
}
// the light falling on a surface facing a direction of height y, from the
// whole studio (cosine weighted, so a uniform studio of 1 gives 1)
static float IRR[129];
static void irradianceTable() {
    for (int k = 0; k <= 128; k++) {
        float ny = -1 + 2.0f * k / 128, nx = std::sqrt(std::max(0.0f, 1 - ny * ny));
        double sum = 0, wsum = 0;
        for (int a = 0; a < 96; a++) for (int b = 0; b < 48; b++) {
            float th = (b + 0.5f) / 48 * 3.14159265f, ph = (a + 0.5f) / 96 * 6.2831853f;
            float dx = std::sin(th) * std::cos(ph), dy = std::cos(th), dz = std::sin(th) * std::sin(ph);
            float c = nx * dx + ny * dy;
            float w = std::sin(th);
            wsum += w * std::max(0.0f, c);
            sum += w * std::max(0.0f, c) * studio(dy);
            (void)dz;
        }
        IRR[k] = (float)(sum / wsum);
    }
}
static float irradiance(float y) {
    float t = (std::max(-1.0f, std::min(1.0f, y)) + 1) * 64;
    int k = std::min(127, (int)t);
    return IRR[k] + (IRR[k + 1] - IRR[k]) * (t - k);
}

static float3 light(const SCNShaderSurface &s, const float3 &worldN, const float3 &worldR, float ao) {
    float3 albedo = mk_float3(s.diffuse.x, s.diffuse.y, s.diffuse.z);
    float rough = std::max(0.04f, std::min(1.0f, s.roughness));
    float3 n = nrm(s.normal), v = nrm(s.view);
    float nv = std::max(1e-4f, dot(n, v));
    // the key from up and to the left (SceneKit turns roll, then yaw, then pitch), the fill from the eye
    float3 d = v3(-std::sin(KEY_YAW), 0, -std::cos(KEY_YAW));
    d = v3(d.x, d.y * std::cos(KEY_PITCH) - d.z * std::sin(KEY_PITCH), d.y * std::sin(KEY_PITCH) + d.z * std::cos(KEY_PITCH));
    float3 lights[2] = {d * -1.0f, v3(0, 0, 1)};
    float power[2] = {KEY / 1000, FILL / 1000};
    float3 out = mk_float3(0.0f);
    float a = rough * rough, k = (rough + 1) * (rough + 1) / 8;
    for (int i = 0; i < 2; i++) {
        float3 l = lights[i];
        float nl = dot(n, l);
        if (nl <= 0) continue;
        float3 h = nrm(l + v);
        float nh = std::max(0.0f, dot(n, h)), vh = std::max(0.0f, dot(v, h));
        float dd = a * a / (3.14159265f * std::pow(nh * nh * (a * a - 1) + 1, 2.0f));
        float g = nl / (nl * (1 - k) + k) * nv / (nv * (1 - k) + k);
        float f = 0.04f + 0.96f * std::pow(1 - vh, 5.0f);
        float spec = dd * g * f / (4 * nl * nv);
        out = out + (albedo * ((1 - f) / 3.14159265f) + mk_float3(spec)) * (power[i] * nl * 3.14159265f);
    }
    // the studio: its light on the surface, and its reflection (Karis's fit)
    float c0[4] = {-1, -0.0275f, -0.572f, 0.022f}, c1[4] = {1, 0.0425f, 1.04f, -0.04f};
    float r0 = rough * c0[0] + c1[0], r1 = rough * c0[1] + c1[1], r2 = rough * c0[2] + c1[2], r3 = rough * c0[3] + c1[3];
    float a004 = std::min(r0 * r0, std::exp2(-9.28f * nv)) * r0 + r1;
    float envSpec = 0.04f * (-1.04f * a004 + r2) + (1.04f * a004 + r3);
    float blur = std::sqrt(rough);
    float pref = studio(worldR.y) * (1 - blur) + irradiance(worldR.y) * blur;
    out = out + (albedo * irradiance(worldN.y) + mk_float3(pref * envSpec)) * (STUDIO * ao);
    return out;
}

// MARK: derivatives, as space_lab has them: the shader run at the pixel to
// the right and below first, each dfdx/dfdy value kept, then at the pixel

static int DPASS = 0;
static std::vector<float4> DREC[2];
static size_t DIDX[2];
float4 rp_derivative(float4 v, int axis) {
    size_t k = DIDX[axis]++;
    if (DPASS == 0) return k < DREC[axis].size() ? DREC[axis][k] - v : mk_float4(0.0f);
    if (DPASS == axis + 1) DREC[axis].push_back(v);
    return mk_float4(0.0f);
}
float4 rp_texture_sample(const void *, float2, float2, float2, int) { return mk_float4(0.0f); }

static void runShader(int surface, SCNShaderSurface &s, const SCNNodeBuffer &nb, const SCNFrameBuffer &fb) {
    if (surface == 1) sh_atlasBone::entry(s, nb, fb);
    else if (surface == 2) sh_atlasMuscle::entry(s, nb, fb);
}

int main(int argc, char **argv) {
    if (argc < 8) { std::fprintf(stderr, "lab <dump> <out.ppm> <w> <h> <dx,dy,dz> <margin> <filter|all> [ssao] [detail] [plain]\n"); return 2; }
    std::vector<Mesh> meshes = load(argv[1]);
    int W = std::atoi(argv[3]), H = std::atoi(argv[4]);
    float dx, dy, dz;
    std::sscanf(argv[5], "%f,%f,%f", &dx, &dy, &dz);
    float margin = (float)std::atof(argv[6]);
    std::string filter = argv[7];
    bool ssao = argc > 8 ? std::atoi(argv[8]) != 0 : true;
    float detail = argc > 9 ? (float)std::atof(argv[9]) : 1.0f;
    bool plain = argc > 10 && std::atoi(argv[10]) != 0;
    overrides();
    irradianceTable();
    // LAB_BONE (an sRGB hex colour) tries another colour for bone
    if (const char *v = std::getenv("LAB_BONE")) {
        unsigned hex = (unsigned)std::strtoul(v, nullptr, 16);
        float3 c = v3(lin(((hex >> 16) & 255) / 255.0f), lin(((hex >> 8) & 255) / 255.0f), lin((hex & 255) / 255.0f));
        for (Mesh &m : meshes) if (m.surface == 1) m.colour = c;
    }

    // the camera: framed on the structures whose names hold the filter, as AtlasModel.frame does (35° high)
    float3 lo = mk_float3(1e9f), hi = mk_float3(-1e9f);
    for (const Mesh &m : meshes) {
        bool take = filter == "all";
        if (!take) {
            size_t a = 0;
            while (!take && a <= filter.size()) {
                size_t b = filter.find(',', a);
                std::string part = filter.substr(a, b == std::string::npos ? std::string::npos : b - a);
                if (!part.empty() && m.name.find(part) != std::string::npos) take = true;
                if (b == std::string::npos) break;
                a = b + 1;
            }
        }
        if (!take) continue;
        for (const float3 &p : m.p) { lo = min(lo, p); hi = max(hi, p); }
    }
    if (lo.x > hi.x) { std::fprintf(stderr, "nothing matches %s\n", filter.c_str()); return 2; }
    float3 centre = (lo + hi) * 0.5f, back = nrm(v3(dx, dy, dz));
    float3 fwd = back * -1.0f, right = nrm(cross(fwd, v3(0, 1, 0))), up = cross(right, fwd);
    float half = std::tan(35.0f * 3.14159265f / 360), aspect = (float)W / H;
    float er = 0, eu = 0, ef = 0;
    for (int c = 0; c < 8; c++) {
        float3 q = v3(c & 1 ? hi.x : lo.x, c & 2 ? hi.y : lo.y, c & 4 ? hi.z : lo.z) - centre;
        er = std::max(er, std::fabs(dot(q, right))); eu = std::max(eu, std::fabs(dot(q, up))); ef = std::max(ef, std::fabs(dot(q, fwd)));
    }
    float distance = std::max(0.15f, std::max(eu / half, er / (half * std::max(0.3f, aspect))) * margin + ef);
    float3 eye = centre + back * distance;
    SCNNodeBuffer nb{};
    nb.inverseModelViewTransform.c[0] = mk_float4(right, 0); nb.inverseModelViewTransform.c[1] = mk_float4(up, 0);
    nb.inverseModelViewTransform.c[2] = mk_float4(back, 0); nb.inverseModelViewTransform.c[3] = mk_float4(eye, 1);
    nb.modelViewTransform.c[0] = mk_float4(right.x, up.x, back.x, 0); nb.modelViewTransform.c[1] = mk_float4(right.y, up.y, back.y, 0);
    nb.modelViewTransform.c[2] = mk_float4(right.z, up.z, back.z, 0);
    nb.modelViewTransform.c[3] = mk_float4(-dot(right, eye), -dot(up, eye), -dot(back, eye), 1);
    SCNFrameBuffer fb{};
    auto toView = [&](float3 p) { float3 q = p - eye; return v3(dot(q, right), dot(q, up), dot(q, back)); };
    auto rot = [&](float3 n) { return v3(dot(n, right), dot(n, up), dot(n, back)); };
    auto toWorld = [&](float3 n) { return right * n.x + up * n.y + back * n.z; };

    // the G-buffer, two by two samples a pixel
    const int SS = 2, SW = W * SS, SH = H * SS;
    std::vector<float> depth(SW * SH, 1e9f);
    std::vector<int> id(SW * SH, -1);
    std::vector<float3> pos(SW * SH), nor(SW * SH), rel(SW * SH);
    std::vector<float2> tcs(SW * SH);
    // LAB_RELIEF=0 draws without the relief's shade (AtlasRelief)
    const char *reliefEnv = std::getenv("LAB_RELIEF");
    const char *fibreEnv = std::getenv("LAB_FIBRES");
    bool fibreDebug = fibreEnv && std::atoi(fibreEnv) != 0;
    bool relief = !(reliefEnv && std::atoi(reliefEnv) == 0);
    float sx = SW / (2 * half * aspect), sy = SH / (2 * half);
    for (size_t mi = 0; mi < meshes.size(); mi++) {
        const Mesh &m = meshes[mi];
        std::vector<float3> vp(m.p.size()), vn(m.n.size());
        for (size_t i = 0; i < m.p.size(); i++) { vp[i] = toView(m.p[i]); vn[i] = rot(m.n[i]); }
        for (size_t t = 0; t + 2 < m.idx.size(); t += 3) {
            int ia = m.idx[t], ib = m.idx[t + 1], ic = m.idx[t + 2];
            float3 A = vp[ia], B = vp[ib], C = vp[ic];
            if (A.z > -0.005f || B.z > -0.005f || C.z > -0.005f) continue;
            float ax = SW / 2.0f + A.x / -A.z * sx, ay = SH / 2.0f - A.y / -A.z * sy;
            float bx = SW / 2.0f + B.x / -B.z * sx, by = SH / 2.0f - B.y / -B.z * sy;
            float cx = SW / 2.0f + C.x / -C.z * sx, cy = SH / 2.0f - C.y / -C.z * sy;
            float area = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
            if (std::fabs(area) < 1e-12f) continue;
            int x0 = std::max(0, (int)std::floor(std::min({ax, bx, cx}))), x1 = std::min(SW - 1, (int)std::ceil(std::max({ax, bx, cx})));
            int y0 = std::max(0, (int)std::floor(std::min({ay, by, cy}))), y1 = std::min(SH - 1, (int)std::ceil(std::max({ay, by, cy})));
            for (int y = y0; y <= y1; y++) for (int x = x0; x <= x1; x++) {
                float px = x + 0.5f, py = y + 0.5f;
                float w0 = ((bx - px) * (cy - py) - (by - py) * (cx - px)) / area;
                float w1 = ((cx - px) * (ay - py) - (cy - py) * (ax - px)) / area;
                float w2 = 1 - w0 - w1;
                if (w0 < 0 || w1 < 0 || w2 < 0) continue;
                float iz = w0 / -A.z + w1 / -B.z + w2 / -C.z, z = 1 / iz;
                int k = y * SW + x;
                if (z >= depth[k]) continue;
                depth[k] = z; id[k] = (int)mi;
                pos[k] = (A * (w0 / -A.z) + B * (w1 / -B.z) + C * (w2 / -C.z)) * z;
                rel[k] = relief ? (m.relief[ia] * (w0 / -A.z) + m.relief[ib] * (w1 / -B.z) + m.relief[ic] * (w2 / -C.z)) * z : mk_float3(1.0f);
                tcs[k] = (m.tc[ia] * (w0 / -A.z) + m.tc[ib] * (w1 / -B.z) + m.tc[ic] * (w2 / -C.z)) * z;
                float3 n = nrm((vn[ia] * (w0 / -A.z) + vn[ib] * (w1 / -B.z) + vn[ic] * (w2 / -C.z)) * z);
                // both faces drawn: a face turned away shows its inside, lit as facing the eye
                if (dot(n, pos[k]) > 0) n = n * -1.0f;
                nor[k] = n;
            }
        }
    }

    // screen-space ambient occlusion from the depths, then a small blur
    std::vector<float> ao(SW * SH, 1.0f);
    if (ssao) {
        float3 kernel[16];
        for (int i = 0; i < 16; i++) {
            float u = (i + 0.5f) / 16, ph = i * 2.39996f;
            float r = std::sqrt(1 - u * u);
            float scale = 0.15f + 0.85f * (i / 16.0f) * (i / 16.0f);
            kernel[i] = v3(r * std::cos(ph), r * std::sin(ph), u) * scale;
        }
        std::vector<float> raw(SW * SH, 1.0f);
        for (int y = 0; y < SH; y++) for (int x = 0; x < SW; x++) {
            int k = y * SW + x;
            if (id[k] < 0) continue;
            float3 n = nor[k], p = pos[k];
            float3 t = nrm(std::fabs(n.x) < 0.9f ? cross(n, v3(1, 0, 0)) : cross(n, v3(0, 1, 0))), b = cross(n, t);
            float turn = ((x & 3) * 4 + (y & 3)) * 0.3927f;
            float ct = std::cos(turn), st = std::sin(turn);
            int hit = 0, used = 0;
            for (int i = 0; i < 16; i++) {
                float3 kk = kernel[i];
                float3 q = p + (t * (kk.x * ct - kk.y * st) + b * (kk.x * st + kk.y * ct) + n * kk.z) * SSAO_RADIUS;
                if (q.z >= -0.001f) continue;
                int qx = (int)(SW / 2.0f + q.x / -q.z * sx), qy = (int)(SH / 2.0f - q.y / -q.z * sy);
                if (qx < 0 || qy < 0 || qx >= SW || qy >= SH) continue;
                used++;
                float zs = depth[qy * SW + qx], zq = -q.z;
                if (zs < zq - SSAO_BIAS && zq - zs < SSAO_DEPTH) hit++;
            }
            raw[k] = used ? std::max(0.0f, 1 - SSAO_INTENSITY * hit / (float)used) : 1.0f;
        }
        for (int y = 0; y < SH; y++) for (int x = 0; x < SW; x++) {
            int k = y * SW + x;
            if (id[k] < 0) continue;
            float s = 0; int c = 0;
            for (int j = -2; j <= 1; j++) for (int i = -2; i <= 1; i++) {
                int xx = x + i, yy = y + j;
                if (xx < 0 || yy < 0 || xx >= SW || yy >= SH) continue;
                int q = yy * SW + xx;
                if (id[q] < 0 || std::fabs(depth[q] - depth[k]) > SSAO_DEPTH) continue;
                s += raw[q]; c++;
            }
            ao[k] = c ? s / c : 1.0f;
        }
    }

    // shading
    sh_atlasBone::rpProbe = 0; sh_atlasBone::rpDetail = detail;
    sh_atlasMuscle::rpProbe = 0; sh_atlasMuscle::rpDetail = detail;
    auto surfaceAt = [&](int x, int y, int mi, const float3 &p0, const float3 &n0, const float3 &r0, const float2 &t0) {
        SCNShaderSurface s{};
        float3 p, n;
        float2 tc = t0;
        int k = y * SW + x;
        if (x >= 0 && y >= 0 && x < SW && y < SH && id[k] == mi) { p = pos[k]; n = nor[k]; tc = tcs[k]; }
        else {
            // off the structure: where this pixel's ray meets the plane of the first
            float3 d = nrm(v3((x + 0.5f - SW / 2.0f) / sx, -(y + 0.5f - SH / 2.0f) / sy, -1));
            float dn = dot(d, n0);
            p = std::fabs(dn) > 1e-6f ? d * (dot(p0, n0) / dn) : p0; n = n0;
        }
        const Mesh &m = meshes[mi];
        s.position = p; s.normal = n; s.geometryNormal = n; s.view = nrm(p * -1.0f); s.diffuseTexcoord = tc;
        // the relief's shade, a vertex colour, multiplies the material's (as SceneKit has it)
        s.diffuse = mk_float4(m.colour * r0, 1.0f); s.roughness = m.rough; s.metalness = 0; s.ambientOcclusion = 1;
        return s;
    };
    std::vector<float3> col(SW * SH);
    float3 background = v3(lin(0.075f), lin(0.08f), lin(0.09f));
    long bonePixels = 0; double boneLum = 0;
    for (int y = 0; y < SH; y++) for (int x = 0; x < SW; x++) {
        int k = y * SW + x, mi = id[k];
        if (mi < 0) { col[k] = background; continue; }
        const Mesh &m = meshes[mi];
        SCNShaderSurface s = surfaceAt(x, y, mi, pos[k], nor[k], rel[k], tcs[k]);
        if (m.surface && !plain) {
            if (m.surface == 2) { sh_atlasMuscle::rpBundle = m.bundle; sh_atlasMuscle::rpTendon = m.tendon; }
            DREC[0].clear(); DREC[1].clear();
            SCNShaderSurface sxs = surfaceAt(x + SS, y, mi, pos[k], nor[k], rel[k], tcs[k]);
            DPASS = 1; DIDX[0] = DIDX[1] = 0; runShader(m.surface, sxs, nb, fb);
            SCNShaderSurface sys = surfaceAt(x, y + SS, mi, pos[k], nor[k], rel[k], tcs[k]);
            DPASS = 2; DIDX[0] = DIDX[1] = 0; runShader(m.surface, sys, nb, fb);
            DPASS = 0; DIDX[0] = DIDX[1] = 0; runShader(m.surface, s, nb, fb);
        }
        float3 wn = toWorld(s.normal), v = nrm(s.view);
        float3 r = s.normal * (2 * dot(s.normal, v)) - v;
        col[k] = light(s, wn, toWorld(r), ao[k]);
        // LAB_FIBRES=1 paints a muscle by its bundles (hue: where it lies across them, a turn every ten), tendon
        // white and forks black
        if (m.surface == 2 && fibreDebug) {
            float2 t = tcs[k]; float a = t.x * 0.6283185f;
            float3 hue = v3(0.5f + 0.5f * std::cos(a), 0.5f + 0.5f * std::cos(a - 2.094f), 0.5f + 0.5f * std::cos(a + 2.094f));
            float tend = std::max(0.0f, std::min(1.0f, t.y));
            col[k] = t.y < -0.5f ? v3(0, 0, 0) : (hue * (1 - tend) + v3(1, 1, 1) * tend) * 0.6f;
        }
        if (m.surface == 1) { bonePixels++; boneLum += 0.2126f * col[k].x + 0.7152f * col[k].y + 0.0722f * col[k].z; }
    }
    std::vector<unsigned char> img(W * H * 3);
    for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) {
        float3 a = mk_float3(0.0f);
        for (int j = 0; j < SS; j++) for (int i = 0; i < SS; i++) a = a + col[(y * SS + j) * SW + x * SS + i];
        a = a / float(SS * SS);
        unsigned char *q = &img[(y * W + x) * 3];
        q[0] = (unsigned char)(srgb(a.x) * 255 + 0.5f); q[1] = (unsigned char)(srgb(a.y) * 255 + 0.5f); q[2] = (unsigned char)(srgb(a.z) * 255 + 0.5f);
    }
    FILE *f = std::fopen(argv[2], "wb");
    std::fprintf(f, "P6\n%d %d\n255\n", W, H);
    std::fwrite(img.data(), 1, img.size(), f);
    std::fclose(f);
    if (bonePixels) std::printf("bone: mean linear luminance %.3f over %ld samples\n", boneLum / bonePixels, bonePixels);
    return 0;
}
