package com.stethoscore.app.map

// The Space theme's bodies and links in GLSL ES 3.0, for the GL map (ui/map/SpaceGl). A port of
// iOS GraphSpaceShaders.swift: each piece's maths is the Metal text with Metal's names turned
// into GLSL's (float3 to vec3, atan2 to atan, a sampler's sample(..., gradient2d) to
// textureGrad), so the two platforms draw the same bodies from the same numbers. What SceneKit
// handed the iOS modifiers (the surface's normal and view, the node's axes, its planes'
// coordinates) is worked out here per fragment instead: each body is one billboard round it,
// and its fragment shader casts the eye's ray at the body's sphere, its ring's plane and its
// beams' and tails' planes. The physics in these strings is the one SpaceOptics holds and
// SpaceStyleTest checks (the tests read these strings).
//
// Uniform names keep iOS's (rpClock, rpMotion, rpDetail, rpReach ...) so the text matches.
// Colours are written as they show on screen: the GL framebuffer is not sRGB, so iOS's final
// pow(2.2) into SceneKit's linear space is left out (the Earth, lit in linear light from an
// sRGB texture, still ends with its own pow(1 / 2.2)).
object SpaceShaders {
    private const val BODY_VS = """#version 300 es
precision highp float;
layout(location = 0) in vec2 aCorner;
layout(location = 1) in vec4 aCenter;
layout(location = 2) in vec4 aLight;
layout(location = 3) in vec4 aA;
layout(location = 4) in vec4 aB;
uniform mat4 uVP;
uniform vec3 uRight;
uniform vec3 uUp;
uniform float uExtent;
out vec3 vWorld;
flat out vec4 vCenter;
flat out vec4 vLight;
flat out vec4 vA;
flat out vec4 vB;
void main() {
    vec3 w = aCenter.xyz + (uRight * aCorner.x + uUp * aCorner.y) * (uExtent * aCenter.w);
    gl_Position = uVP * vec4(w, 1.0);
    vWorld = w;
    vCenter = aCenter;
    vLight = aLight;
    vA = aA;
    vB = aB;
}
"""

    // Per body: vCenter (its place, the note's radius r), vLight (the light's direction, the
    // note's seed), vA and vB (a direction each and a number: see SpaceBodies), and vB.w the
    // note's size on screen in pixels.
    private const val BODY_FS_HEAD = """#version 300 es
precision highp float;
precision highp int;
uniform float rpClock;
uniform float rpMotion;
uniform float rpDetail;
uniform float rpDisk;
uniform vec3 uEye;
uniform vec3 uRight;
uniform vec3 uUp;
uniform float uFocal;
in vec3 vWorld;
flat in vec4 vCenter;
flat in vec4 vLight;
flat in vec4 vA;
flat in vec4 vB;
out vec4 fragColor;
"""

    // GraphShaderKit's noise, fbm and cells, and the ring's density, as functions; and the
    // ray casting that stands in for SceneKit's geometry.
    private const val KIT = """
float rpHash(float n) { return fract(sin(n) * 43758.5453); }
float rpNoise(vec3 p) {
    vec3 i = floor(p);
    vec3 f = p - i;
    vec3 u = f * f * (3.0 - 2.0 * f);
    float n = i.x + i.y * 57.0 + i.z * 113.0;
    float a = mix(rpHash(n), rpHash(n + 1.0), u.x);
    float b = mix(rpHash(n + 57.0), rpHash(n + 58.0), u.x);
    float c = mix(rpHash(n + 113.0), rpHash(n + 114.0), u.x);
    float d = mix(rpHash(n + 170.0), rpHash(n + 171.0), u.x);
    return mix(mix(a, b, u.y), mix(c, d, u.y), u.z);
}
float rpFbm(vec3 p, int octaves) {
    float total = 0.0;
    float wt = 0.5;
    float sum = 0.0;
    vec3 x = p;
    for (int o = 0; o < 8; o++) {
        if (o >= octaves) break;
        total = total + rpNoise(x) * wt;
        sum = sum + wt;
        x = x * 2.03 + vec3(1.7, 9.2, 3.1);
        wt = wt * 0.5;
    }
    return total / max(sum, 0.0001);
}
void rpCells(vec3 p, float wobble, out float f1, out float f2, out float id) {
    vec3 i = floor(p);
    vec3 f = p - i;
    vec3 o = step(vec3(0.5), f) - vec3(1.0);
    f1 = 8.0;
    f2 = 8.0;
    id = 0.0;
    for (int k = 0; k < 8; k++) {
        vec3 c = o + vec3(float(k & 1), float((k >> 1) & 1), float((k >> 2) & 1));
        vec3 g = i + c;
        float h = g.x + g.y * 57.0 + g.z * 113.0;
        vec3 r = fract(sin(vec3(h, h + 31.7, h + 67.3)) * 43758.5453);
        vec3 j = vec3(0.5) + (r - vec3(0.5)) * 0.5 + sin(r * 6.2831853 + vec3(wobble)) * 0.1;
        vec3 d = c + j - f;
        float dd = dot(d, d);
        if (dd < f1) {
            f2 = f1;
            f1 = dd;
            id = r.x;
        } else if (dd < f2) {
            f2 = dd;
        }
    }
    f1 = sqrt(f1);
    f2 = sqrt(f2);
}
float rpRingDensity(float rho) {
    float body = smoothstep(1.3, 1.36, rho) * (1.0 - smoothstep(2.2, 2.3, rho));
    float gd = (rho - 1.95) / 0.03;
    float gap = 1.0 - 0.85 * exp(-gd * gd);
    float lets = 0.78 + 0.22 * sin(rho * 140.0) * sin(rho * 37.0);
    float cring = mix(0.35, 1.0, smoothstep(1.42, 1.52, rho));
    return body * gap * lets * cring;
}
vec3 rpRay() { return normalize(vWorld - uEye); }
// The eye's ray against a sphere: the distance to it (or -1), its outward normal there (on a
// miss, at the limb nearest the ray) and how much of this pixel it covers, so its edge is smooth.
float rpSphere(vec3 rd, vec3 c, float R, out vec3 n, out float cover) {
    vec3 oc = uEye - c;
    float b = dot(oc, rd);
    float q = dot(oc, oc) - b * b;
    float perp = sqrt(max(q, 0.0));
    float pixel = max(-b, 1e-4) / uFocal;
    cover = b < 0.0 ? clamp((R - perp) / pixel + 0.5, 0.0, 1.0) : 0.0;
    float t = -b - sqrt(max(R * R - q, 0.0));
    n = normalize(uEye + rd * t - c);
    return cover > 0.0 ? t : -1.0;
}
// A body's own axes: Y its spin axis, turned by `a` about it.
void rpFrame(vec3 y, float a, out vec3 X, out vec3 Y, out vec3 Z) {
    Y = normalize(y);
    vec3 helper = abs(Y.z) < 0.99 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
    vec3 X0 = normalize(cross(Y, helper));
    vec3 Z0 = cross(X0, Y);
    X = cos(a) * X0 - sin(a) * Z0;
    Z = sin(a) * X0 + cos(a) * Z0;
}
// This fragment on a billboard round `c` of half side h, -1 to 1, y up.
vec2 rpPlane(vec3 c, float h) {
    vec3 d = vWorld - c;
    return vec2(dot(d, uRight), dot(d, uUp)) / h;
}
// Where the ray meets the plane through `c` holding `along` and `across`: (across, along), world units.
vec2 rpStrip(vec3 rd, vec3 c, vec3 along, vec3 across) {
    vec3 nrm = cross(across, along);
    float den = dot(rd, nrm);
    if (abs(den) < 1e-6) return vec2(1e9);
    float t = dot(c - uEye, nrm) / den;
    if (t <= 0.0) return vec2(1e9);
    vec3 p = uEye + rd * t - c;
    return vec2(dot(p, across), dot(p, along));
}
// Square to `along` and to the eye: a plane along it that faces the eye.
vec3 rpAcross(vec3 along, vec3 c) {
    vec3 x = cross(along, normalize(uEye - c));
    float l = length(x);
    return l > 1e-4 ? x / l : uRight;
}
// A light direction in the screen's frame: x right, y up, z towards the eye (iOS's view space).
vec3 rpSeen(vec3 l, vec3 c) { return vec3(dot(l, uRight), dot(l, uUp), dot(l, normalize(uEye - c))); }
vec4 rpOver(vec4 front, vec4 back) { return front + back * (1.0 - front.a); }
"""

    // ---- the black hole (GraphStyleShaders.bhRing) ----

    private const val BH = """
vec3 bhRing(float rp_qx, float rp_qy, float rp_codeIn, float rp_seedIn) {
    float rp_r = length(vec2(rp_qx, rp_qy)) + 0.00001;
    float rp_code = rp_codeIn - 2.0;
    float rp_above = rp_code < 0.0 ? -1.0 : 1.0;
    float rp_v = min(abs(rp_code), 0.99999);
    float rp_kq = floor(rp_v * 256.0);
    float rp_k = rp_kq / 255.0;
    float rp_m = clamp((rp_v * 256.0 - rp_kq - 0.02) / 0.96, 0.0, 1.0) * rpMotion;
    float rp_t = rpClock * rpMotion;
    float rp_seed = rp_seedIn;
    float rp_ci = rp_above * sqrt(max(1.0 - rp_k * rp_k, 0.0));
    vec3 rp_n = vec3(0.0, -rp_k, rp_ci);
    float rp_H = 3.0;
    float rp_X = rp_qx * rp_H;
    float rp_Y = rp_qy * rp_H;
    float rp_b = sqrt(rp_X * rp_X + rp_Y * rp_Y) + 0.00001;
    vec3 rp_e = vec3(rp_X / rp_b, rp_Y / rp_b, 0.0);
    float rp_en = dot(rp_e, rp_n);
    float rp_cs = rp_n.z < 0.0 ? rp_en : -rp_en;
    float rp_psi0 = atan(abs(rp_n.z) + 0.0001, rp_cs);
    float rp_rs = 0.385;
    float rp_rin = 1.155;
    float rp_rout = 2.5 * (1.0 + 0.18 * rp_m);
    vec3 rp_d2 = vec3(0.0, rp_n.z, rp_k);
    vec3 rp_col = vec3(0.0);
    float rp_lit = 0.0;
    float rp_s1 = 0.5;
    float rp_om = 0.9;
    int rp_images = rpDetail > 0.5 ? 2 : 1;
    for (int rp_img = 0; rp_img < rp_images; rp_img++) {
    float rp_two = float(rp_img);
    float rp_psi = rp_psi0 + 3.14159265 * rp_two;
    float rp_bi = mix(rp_b, 1.0 + (rp_b - 1.0) * 3.5, rp_two);
    float rp_sp = sin(rp_psi);
    float rp_cp = cos(rp_psi);
    float rp_x = 1.0 - rp_cp;
    float rp_rr = max(rp_bi, 0.5);
    for (int rp_i = 0; rp_i < 4; rp_i++) {
    float rp_ui = min(rp_rs / rp_rr, 0.95);
    float rp_cai = 1.0 - rp_x * (1.0 - rp_ui);
    float rp_sai = sqrt(max(1.0 - rp_cai * rp_cai, 0.0001));
    rp_rr = max(rp_bi, 0.0) * sqrt(1.0 - rp_ui) / rp_sai;
    }
    float rp_u = min(rp_rs / rp_rr, 0.95);
    float rp_ca = 1.0 - rp_x * (1.0 - rp_u);
    float rp_sa = sqrt(max(1.0 - rp_ca * rp_ca, 0.0001));
    vec3 rp_P = vec3(rp_e.x * rp_sp, rp_e.y * rp_sp, rp_cp);
    float rp_phi = atan(dot(rp_P, rp_d2), rp_P.x);
    float rp_front = rp_b < 1.0 ? 1.0 - smoothstep(1.2, 1.6, rp_psi) : 1.0;
    float rp_seen = mix(rp_front, step(1.0, rp_b) * 0.55, rp_two);
    float rp_on = rp_seen * smoothstep(rp_rin - 0.04, rp_rin + 0.02, rp_rr) * (1.0 - smoothstep(rp_rout * 0.72, rp_rout, rp_rr));
    float rp_rn = max(rp_rr / rp_rin, 1.0);
    float rp_prof = 17.6 * (1.0 - 1.0 / sqrt(rp_rn)) / (rp_rn * rp_rn * rp_rn);
    rp_prof = rp_prof + 0.18 * exp(-(rp_rn - 1.0) * 6.0);
    float rp_lanes = 26.0;
    float rp_ln = floor(rp_rr * rp_lanes);
    float rp_lc = max((rp_ln + 0.5) / rp_lanes, rp_rin);
    rp_om = 0.9 * pow(rp_rin / rp_lc, 1.5);
    float rp_ph = rp_phi - rp_om * rp_t + rp_ln * 1.7 + rp_seed * 6.2831853;
    float rp_lh = fract(sin(rp_ln * 12.9898 + rp_seed * 7.0) * 43758.5453);
    float rp_n1 = rpNoise(vec3(cos(rp_ph) * 2.4, sin(rp_ph) * 2.4, rp_ln * 0.61));
    rp_s1 = rp_n1;
    float rp_streak = 0.45 + 0.9 * rp_n1 * (0.6 + 0.4 * rp_lh);
    if (rpDetail > 0.5) {
    float rp_n2 = rpNoise(vec3(cos(rp_ph) * 7.0, sin(rp_ph) * 7.0, rp_rr * 40.0));
    rp_streak = rp_streak * (0.62 + 0.76 * rp_n2);
    }
    float rp_fine = 0.82 + 0.18 * sin(rp_rr * 150.0 + rp_n1 * 5.0);
    float rp_hA = rp_phi - 0.9 * pow(rp_rin / 1.45, 1.5) * rp_t - 0.7;
    rp_hA = rp_hA - 6.2831853 * floor(rp_hA / 6.2831853 + 0.5);
    float rp_hB = rp_phi - 0.9 * pow(rp_rin / 1.9, 1.5) * rp_t - 3.4;
    rp_hB = rp_hB - 6.2831853 * floor(rp_hB / 6.2831853 + 0.5);
    float rp_dA = (rp_rr - 1.45) / 0.06;
    float rp_dB = (rp_rr - 1.9) / 0.07;
    float rp_hot = exp(-rp_dA * rp_dA - rp_hA * rp_hA * 9.0) * 0.9 + exp(-rp_dB * rp_dB - rp_hB * rp_hB * 7.0) * 0.6;
    float rp_mat = rp_streak * rp_fine + rp_hot;
    float rp_beta = min(sqrt(rp_rs / (2.0 * max(rp_rr - rp_rs, 0.3))), 0.6);
    vec3 rp_vel = cross(rp_n, rp_P);
    vec3 rp_T = vec3(-rp_e.x * rp_cp, -rp_e.y * rp_cp, rp_sp);
    vec3 rp_kd = rp_P * rp_ca + rp_T * rp_sa;
    float rp_cth = dot(rp_vel, rp_kd);
    float rp_gam = 1.0 / sqrt(1.0 - rp_beta * rp_beta);
    float rp_g = sqrt(max(1.0 - 1.5 * rp_rs / rp_rr, 0.05)) / (rp_gam * (1.0 - rp_beta * rp_cth));
    rp_g = mix(1.0, rp_g, 0.8);
    float rp_boost = clamp(rp_g * rp_g * rp_g, 0.04, 6.0);
    float rp_heat = pow(max(rp_prof, 0.0), 0.25) * rp_g * (1.0 + 0.3 * rp_m);
    vec3 rp_hue = mix(vec3(0.45, 0.04, 0.0), vec3(1.0, 0.3, 0.03), clamp(rp_heat / 0.45, 0.0, 1.0));
    rp_hue = mix(rp_hue, vec3(1.0, 0.62, 0.24), clamp((rp_heat - 0.45) / 0.3, 0.0, 1.0));
    rp_hue = mix(rp_hue, vec3(1.0, 0.9, 0.72), clamp((rp_heat - 0.75) / 0.3, 0.0, 1.0));
    rp_hue = mix(rp_hue, vec3(0.86, 0.92, 1.0), clamp((rp_heat - 1.1) / 0.4, 0.0, 1.0));
    float rp_lum = rp_prof * rp_mat * rp_boost * (1.0 + 0.7 * rp_m);
    rp_lum = rp_lum / (1.0 + 0.45 * rp_lum);
    rp_col = rp_col + rp_hue * (rp_lum * 1.3 * rp_on * rpDisk);
    rp_lit = max(rp_lit, rp_lum * rp_on);
    float rp_id = (rp_rr - rp_rin) / 0.018;
    float rp_isco = exp(-rp_id * rp_id) * rp_seen * clamp(rp_boost, 0.3, 2.5) * rpDisk;
    rp_col = rp_col + vec3(1.0, 0.86, 0.6) * (rp_isco * 0.55);
    float rp_sr = rp_rr / rp_rout;
    float rp_arm = rp_phi + 2.6 * log(max(rp_sr, 0.5)) - rp_t * 0.5;
    float rp_sh = rpNoise(vec3(cos(rp_arm) * 2.0, sin(rp_arm) * 2.0, rp_rr * 3.0 - rp_t * 0.4));
    float rp_shed = smoothstep(0.85, 1.0, rp_sr) * exp(-max(rp_sr - 1.0, 0.0) * 2.6) * smoothstep(0.5, 0.8, rp_sh);
    rp_col = rp_col + vec3(1.0, 0.42, 0.08) * (rp_shed * rp_m * rp_seen * clamp(rp_boost, 0.2, 3.0) * 0.5 * rpDisk);
    }
    float rp_side = 0.5 + 0.5 * rp_e.x * rp_k;
    float rp_pd = (rp_b - 1.012) / 0.011;
    float rp_ring = exp(-rp_pd * rp_pd) * (0.35 + 1.4 * rp_side * rp_side);
    float rp_ld = (rp_b - 1.05) / 0.016;
    float rp_echo = exp(-rp_ld * rp_ld) * (0.3 + 0.8 * rp_side) * (0.6 + 0.6 * rp_s1) * rpDisk * (1.0 - rpDetail);
    vec3 rp_ringHue = mix(vec3(1.0, 0.7, 0.35), vec3(1.0, 0.95, 0.86), rp_side);
    rp_col = rp_col + rp_ringHue * (rp_ring * (1.1 + 0.6 * rp_m) + rp_echo * 0.5);
    float rp_out = max(rp_b - 1.0, 0.0);
    rp_col = rp_col + vec3(1.0, 0.5, 0.15) * (exp(-rp_out / 0.35) * 0.05 * step(1.0, rp_b) * (0.5 + rp_side));
    if (rpDetail > 0.5) {
    float rp_sa2 = atan(rp_Y, rp_X);
    float rp_lr = floor(rp_b * 9.0);
    float rp_la = floor(rp_sa2 * 4.0 + rp_lr * 0.37);
    float rp_lsh = fract(sin(rp_la * 12.9898 + rp_lr * 78.233) * 43758.5453);
    float rp_cr = (rp_lr + 0.5) / 9.0;
    float rp_ang = (rp_la + 0.5 - rp_lr * 0.37) / 4.0;
    float rp_dAng = (rp_sa2 - rp_ang) * rp_b;
    float rp_ez = (rp_b - 1.35) / 0.25;
    float rp_ein = exp(-rp_ez * rp_ez);
    float rp_stx = rp_dAng / (0.02 + 0.2 * rp_ein);
    float rp_sty = (rp_b - rp_cr) / 0.012;
    float rp_star = exp(-rp_stx * rp_stx - rp_sty * rp_sty) * step(0.8, rp_lsh) * step(1.06, rp_b);
    rp_col = rp_col + vec3(0.75, 0.85, 1.0) * (rp_star * 0.35 * (1.0 - min(rp_lit, 1.0)));
    }
    float rp_edge = clamp((1.0 - rp_r) / 0.1, 0.0, 1.0);
    rp_col = rp_col * (rp_edge * rp_edge * (3.0 - 2.0 * rp_edge));
    return rp_col;
}
"""

    private const val BH_MAIN = """
void main() {
    vec3 c = vCenter.xyz;
    float r = vCenter.w;
    vec2 q = rpPlane(c, r * 2.1);
    vec2 xP = vA.xy;
    vec2 yP = vec2(-xP.y, xP.x);
    vec3 col = bhRing(dot(q, xP), dot(q, yP), vA.w, vLight.w);
    float b = length(q) * 3.0;
    float side = r * 2.1 * uFocal / max(length(c - uEye), 1e-4);
    float shadow = clamp((1.0 - b) * side / 3.0 + 0.5, 0.0, 1.0);
    fragColor = vec4(col, shadow);
}
"""

    // ---- the sun (sunBody, sunCorona) ----

    private const val SUN = """
vec3 sunBody(vec3 rp_N, vec3 rp_V, vec3 rp_v0, vec3 rp_v1, vec3 rp_v2, float rp_px) {
    float rp_mu = max(dot(rp_N, rp_V), 0.0);
    vec3 rp_p = normalize(vec3(dot(rp_v0, rp_N), dot(rp_v1, rp_N), dot(rp_v2, rp_N)));
    float rp_m = 0.0;
    float rp_t = rpClock * rpMotion;
    float rp_lm = 1.0 - rp_mu;
    float rp_limb = 1.0 - 0.56 * rp_lm - 0.22 * rp_lm * rp_lm;
    float rp_sg = rpNoise(rp_p * 4.0 + vec3(0.0, rp_t * 0.015, 0.0));
    float rp_near = smoothstep(120.0, 420.0, rp_px);
    vec3 rp_gp = rp_p * 46.0 + vec3(rp_sg * 1.2, 0.0, rp_sg * 0.8);
    float rp_gran = 0.86 + 0.28 * (rp_sg - 0.5);
    if (rp_near > 0.001) {
    float rp_c1_f1;
    float rp_c1_f2;
    float rp_c1_id;
    rpCells(rp_gp, rp_t * 0.35, rp_c1_f1, rp_c1_f2, rp_c1_id);
    float rp_lane = rp_c1_f2 - rp_c1_f1;
    float rp_cell = 0.8 + 0.2 * smoothstep(0.0, 0.22, rp_lane);
    rp_cell = rp_cell * (0.93 + 0.14 * rp_c1_id) * (1.0 - 0.12 * smoothstep(0.25, 0.8, rp_c1_f1));
    rp_gran = mix(rp_gran, rp_gran * rp_cell * 1.08, rp_near);
    }
    if (rpDetail > 0.5) {
    float rp_g2 = rpNoise(rp_p * 18.0 + vec3(5.0, 1.0, rp_t * 0.05));
    rp_gran = rp_gran * (0.94 + 0.12 * rp_g2);
    }
    float rp_sd = dot(rp_p, vec3(0.35, 0.28, 0.894));
    float rp_um = smoothstep(0.9935, 0.9965, rp_sd);
    float rp_pen = smoothstep(0.981, 0.9925, rp_sd);
    float rp_fa = atan(dot(rp_p, vec3(0.1021, -0.9599, 0.2607)), dot(rp_p, vec3(-0.931, 0.0, 0.3646)));
    float rp_fil = 0.65 + 0.35 * sin(rp_fa * 60.0 + rp_sg * 6.0);
    float rp_sd2 = dot(rp_p, vec3(0.47, 0.2, 0.86));
    float rp_um2 = smoothstep(0.9978, 0.9991, rp_sd2);
    float rp_pen2 = smoothstep(0.9935, 0.9975, rp_sd2);
    float rp_sd3 = dot(rp_p, vec3(0.29, 0.36, 0.887));
    float rp_um3 = smoothstep(0.9985, 0.9994, rp_sd3);
    float rp_pen3 = smoothstep(0.9958, 0.9984, rp_sd3);
    float rp_spot = (rp_pen - rp_um) * rp_fil * 0.45 + rp_um * 0.78;
    rp_spot = rp_spot + (rp_pen2 - rp_um2) * 0.4 + rp_um2 * 0.72;
    rp_spot = rp_spot + (rp_pen3 - rp_um3) * 0.38 + rp_um3 * 0.7;
    rp_spot = rp_spot * (0.12 + 0.73 * smoothstep(0.2, 0.8, rp_mu));
    float rp_act = smoothstep(0.955, 0.985, rp_sd) * (1.0 - rp_pen) + smoothstep(0.984, 0.993, rp_sd2) * (1.0 - rp_pen2);
    rp_act = min(rp_act + smoothstep(0.989, 0.9955, rp_sd3) * (1.0 - rp_pen3), 1.0);
    float rp_fac = (smoothstep(0.62, 0.8, rp_sg) * 0.3 + rp_act * (0.12 + 0.14 * rp_sg)) * smoothstep(0.35, 0.85, rp_lm);
    float rp_fc = rp_t / 11.0;
    float rp_fl = fract(rp_fc);
    float rp_fd = dot(rp_p, normalize(vec3(0.41, 0.17, 0.9)));
    float rp_fz = (1.0 - rp_fd) / 0.0012;
    float rp_flare = exp(-rp_fz * rp_fz) * exp(-rp_fl * 6.0) * smoothstep(0.0, 0.03, rp_fl) * 1.4 * rpMotion;
    float rp_temp = rp_gran - rp_spot * (1.0 - rp_flare) + rp_fac;
    float rp_heat = rp_temp * (0.12 + 0.88 * rp_limb) * 1.15 * (1.0 + 0.16 * rp_m) + rp_flare;
    vec3 rp_col = mix(vec3(0.55, 0.08, 0.0), vec3(0.98, 0.36, 0.03), clamp(rp_heat / 0.42, 0.0, 1.0));
    rp_col = mix(rp_col, vec3(1.0, 0.7, 0.22), clamp((rp_heat - 0.42) / 0.25, 0.0, 1.0));
    rp_col = mix(rp_col, vec3(1.0, 0.9, 0.62), clamp((rp_heat - 0.67) / 0.22, 0.0, 1.0));
    rp_col = mix(rp_col, vec3(1.0, 0.98, 0.9), clamp((rp_heat - 0.89) / 0.2, 0.0, 1.0));
    rp_col = rp_col * (0.25 + 0.85 * clamp(rp_heat, 0.0, 1.3));
    return rp_col;
}
vec3 sunCorona(float rp_qx, float rp_qy, float rp_codeIn) {
    float rp_r = length(vec2(rp_qx, rp_qy)) + 0.00001;
    float rp_code = clamp(rp_codeIn - 2.0, 0.0, 0.9999);
    float rp_sq = floor(rp_code * 32.0) / 32.0;
    float rp_seed = rp_sq * 6.2831853;
    float rp_mv = clamp((rp_code - rp_sq) * 32.0 / 0.96, 0.0, 1.0) * rpMotion;
    float rp_t = rpClock * rpMotion;
    float rp_rl = 0.25;
    float rp_a = atan(rp_qy, rp_qx);
    float rp_x = rp_r / rp_rl;
    float rp_out = max(rp_x - 1.0, 0.0);
    float rp_sn = rpNoise(vec3(cos(rp_a) * 1.8, sin(rp_a) * 1.8, rp_t * 0.02 + rp_seed));
    float rp_helm = 0.25 + 1.1 * rp_sn * rp_sn;
    float rp_rw = sin(rp_a * 5.0 + rp_seed) * 1.5;
    float rp_ray = 0.5 + 0.5 * sin(rp_a * 23.0 + rp_rw + rp_out * 0.8);
    rp_ray = rp_ray * rp_ray;
    float rp_flow = 0.8 + 0.2 * sin(rp_out * 9.0 - rp_t * (0.8 + 4.0 * rp_mv) + rp_a * 2.0);
    float rp_inner = exp(-rp_out / (0.15 * (1.0 + 0.5 * rp_mv))) * 0.62;
    float rp_k = exp(-rp_out / (0.6 * (1.0 + 0.8 * rp_mv))) * 0.36 * rp_helm;
    float rp_far = exp(-rp_out / (1.8 * (1.0 + 1.2 * rp_mv))) * 0.2 * rp_helm * (0.65 + 0.7 * rp_ray) * rp_flow;
    float rp_cor = (rp_inner + rp_k + rp_far) * step(1.0, rp_x);
    vec3 rp_hue = mix(vec3(1.0, 0.86, 0.6), vec3(1.0, 0.55, 0.2), clamp(rp_out * 0.8, 0.0, 1.0));
    vec3 rp_col = rp_hue * rp_cor;
    float rp_ch = (rp_x - 1.004) / 0.012;
    float rp_spic = 0.7 + 0.3 * sin(rp_a * 160.0 + rp_t * 0.7);
    rp_col = rp_col + vec3(1.0, 0.32, 0.2) * (exp(-rp_ch * rp_ch) * 0.9 * rp_spic);
    vec3 rp_prom = vec3(1.0, 0.36, 0.22);
    float rp_pf = rpNoise(vec3(rp_qx * 34.0, rp_qy * 34.0, rp_t * 0.15));
    float rp_thread = 0.55 + 0.9 * rp_pf;
    float rp_cA = rp_t / 14.0 + rp_seed * 0.1;
    float rp_fA = fract(rp_cA);
    float rp_tA = fract(sin(floor(rp_cA) * 3.7 + rp_seed) * 43758.5453) * 1.4 + 0.3 + rp_seed;
    float rp_lA = rp_rl;
    float rp_xA = rp_qx * cos(rp_tA) + rp_qy * sin(rp_tA);
    float rp_yA = rp_qy * cos(rp_tA) - rp_qx * sin(rp_tA);
    float rp_hA = rp_rl * (0.005 + 0.32 * sin(3.1415927 * rp_fA));
    float rp_wA = rp_rl * (0.01 + 0.12 * sqrt(sin(3.1415927 * rp_fA)));
    float rp_sA = rp_yA / rp_wA;
    float rp_uA = (rp_xA - rp_lA) / rp_hA;
    float rp_eA = sqrt(rp_sA * rp_sA + rp_uA * rp_uA);
    float rp_bA = (rp_eA - 1.0 + (rp_pf - 0.5) * 0.35) / (0.16 + 0.08 * rp_fA);
    float rp_pA = exp(-rp_bA * rp_bA) * step(0.0, rp_xA - rp_rl * 0.995) * (0.7 + 0.5 * exp(-clamp(rp_uA, 0.0, 2.0) * 3.0));
    float rp_cB = rp_t / 19.0 + 0.41 + rp_seed * 0.1;
    float rp_fB = fract(rp_cB);
    float rp_tB = fract(sin(floor(rp_cB) * 3.7 + 11.0 + rp_seed) * 43758.5453) * 1.6 + 2.6 + rp_seed;
    float rp_lB = rp_rl;
    float rp_xB = rp_qx * cos(rp_tB) + rp_qy * sin(rp_tB);
    float rp_yB = rp_qy * cos(rp_tB) - rp_qx * sin(rp_tB);
    float rp_hB = rp_rl * (0.005 + 0.24 * sin(3.1415927 * rp_fB));
    float rp_wB = rp_rl * (0.01 + 0.09 * sqrt(sin(3.1415927 * rp_fB)));
    float rp_sB = rp_yB / rp_wB;
    float rp_uB = (rp_xB - rp_lB) / rp_hB;
    float rp_eB = sqrt(rp_sB * rp_sB + rp_uB * rp_uB);
    float rp_bB = (rp_eB - 1.0 + (rp_pf - 0.5) * 0.35) / (0.18 + 0.08 * rp_fB);
    float rp_pB = exp(-rp_bB * rp_bB) * step(0.0, rp_xB - rp_rl * 0.995) * (0.7 + 0.5 * exp(-clamp(rp_uB, 0.0, 2.0) * 3.0));
    float rp_cC = rp_t / 23.0 + 0.77 + rp_seed * 0.1;
    float rp_fC = fract(rp_cC);
    float rp_tC = fract(sin(floor(rp_cC) * 3.7 + 22.0 + rp_seed) * 43758.5453) * 1.6 + 4.6 + rp_seed;
    float rp_lC = rp_rl;
    float rp_xC = rp_qx * cos(rp_tC) + rp_qy * sin(rp_tC);
    float rp_yC = rp_qy * cos(rp_tC) - rp_qx * sin(rp_tC);
    float rp_hC = rp_rl * (0.005 + 0.19 * sin(3.1415927 * rp_fC));
    float rp_wC = rp_rl * (0.01 + 0.07 * sqrt(sin(3.1415927 * rp_fC)));
    float rp_sC = rp_yC / rp_wC;
    float rp_uC = (rp_xC - rp_lC) / rp_hC;
    float rp_eC = sqrt(rp_sC * rp_sC + rp_uC * rp_uC);
    float rp_bC = (rp_eC - 1.0 + (rp_pf - 0.5) * 0.35) / (0.2 + 0.08 * rp_fC);
    float rp_pC = exp(-rp_bC * rp_bC) * step(0.0, rp_xC - rp_rl * 0.995) * (0.7 + 0.5 * exp(-clamp(rp_uC, 0.0, 2.0) * 3.0));
    float rp_proms = (rp_pA + rp_pB + rp_pC) * rp_thread;
    rp_col = rp_col + rp_prom * (rp_proms * 1.1);
    rp_col = rp_col + vec3(1.0, 0.75, 0.6) * (rp_proms * rp_proms * 0.25);
    float rp_cF = rp_t / 17.0 + rp_seed * 0.3;
    float rp_fl = fract(rp_cF);
    float rp_ft = fract(sin(floor(rp_cF) * 5.3 + rp_seed) * 43758.5453) * 6.2831853;
    float rp_xF = rp_qx * cos(rp_ft) + rp_qy * sin(rp_ft);
    float rp_yF = rp_qy * cos(rp_ft) - rp_qx * sin(rp_ft);
    float rp_sz = rp_rl * (0.03 + 0.42 * sin(3.1415927 * rp_fl));
    float rp_go = rp_rl + rp_sz * 0.45;
    float rp_dF = length(vec2((rp_xF - rp_go) / (rp_sz * 0.7), rp_yF / rp_sz));
    float rp_shell = exp(-(rp_dF - 1.0) * (rp_dF - 1.0) * 30.0) * step(rp_rl, rp_r) * step(rp_go - rp_sz * 0.2, rp_xF + rp_sz * 0.7);
    vec3 rp_fh = mix(vec3(1.0, 0.95, 0.84), vec3(1.0, 0.45, 0.12), rp_fl);
    rp_col = rp_col + rp_fh * (rp_shell * 0.45 * rpMotion * (0.6 + 0.6 * rp_pf));
    float rp_e = clamp((1.0 - rp_r) / 0.5, 0.0, 1.0);
    rp_col = rp_col * (rp_e * rp_e * (3.0 - 2.0 * rp_e));
    return rp_col;
}
"""

    private const val SUN_MAIN = """
void main() {
    vec3 c = vCenter.xyz;
    float r = vCenter.w;
    float R = r * 1.1;
    vec3 rd = rpRay();
    vec3 X;
    vec3 Y;
    vec3 Z;
    rpFrame(vec3(0.0, 1.0, 0.0), rpClock * rpMotion * 0.05 + vLight.w * 6.2831853, X, Y, Z);
    vec3 n;
    float cover;
    rpSphere(rd, c, R, n, cover);
    vec4 res = vec4(sunBody(n, -rd, X, Y, Z, vB.w * 1.1) * cover, cover);
    vec2 q = rpPlane(c, R * 4.0);
    if (abs(q.x) <= 1.0 && abs(q.y) <= 1.0) res.rgb = res.rgb + sunCorona(q.x, q.y, vA.w);
    fragColor = res;
}
"""

    // ---- the rocky planet (rockBody, moonBody, halo) ----

    private const val ROCK = """
uniform sampler2D rpEarthDay;
uniform sampler2D rpEarthAux;
uniform float uEarthReady;
vec3 rockBody(vec3 rp_N, vec3 rp_V, vec3 rp_v0, vec3 rp_v1, vec3 rp_v2, vec3 rp_Lw) {
    vec3 rp_Lv = rp_Lw;
    vec3 rp_Lo = vec3(dot(rp_v0, rp_Lw), dot(rp_v1, rp_Lw), dot(rp_v2, rp_Lw));
    float rp_mu = max(dot(rp_N, rp_V), 0.0);
    vec3 rp_p = normalize(vec3(dot(rp_v0, rp_N), dot(rp_v1, rp_N), dot(rp_v2, rp_N)));
    float rp_t = rpClock * rpMotion;
    float rp_ce = max(sqrt(rp_p.x * rp_p.x + rp_p.z * rp_p.z), 0.02);
    vec2 rp_uv = vec2(0.5 + atan(rp_p.x, rp_p.z) * 0.15915494, 0.5 - asin(clamp(rp_p.y, -1.0, 1.0)) * 0.31830989);
    vec2 rp_gx = dFdx(rp_uv);
    vec2 rp_gy = dFdy(rp_uv);
    rp_gx.x = rp_gx.x - round(rp_gx.x);
    rp_gy.x = rp_gy.x - round(rp_gy.x);
    vec3 rp_alb = textureGrad(rpEarthDay, rp_uv, rp_gx, rp_gy).xyz;
    vec4 rp_aux = textureGrad(rpEarthAux, rp_uv, rp_gx, rp_gy);
    vec2 rp_cuv = vec2(rp_uv.x - rp_t / 3000.0, rp_uv.y);
    float rp_cloud = smoothstep(0.1, 0.82, textureGrad(rpEarthDay, rp_cuv, rp_gx, rp_gy).w);
    if (uEarthReady < 0.5) {
        float rp_land = smoothstep(0.5, 0.56, rpFbm(rp_p * 2.2 + vec3(3.0, 1.0, 5.0), 4));
        rp_alb = mix(vec3(0.02, 0.07, 0.17), vec3(0.22, 0.27, 0.13), rp_land);
        rp_aux = vec4(0.0, 1.0 - rp_land, 0.0, 0.0);
        rp_cloud = smoothstep(0.55, 0.75, rpFbm(rp_p * 3.0 + vec3(rp_t * 0.002, 0.0, 7.0), 4)) * 0.8;
    }
    float rp_ndl = dot(rp_N, rp_Lv);
    float rp_day = smoothstep(-0.08, 0.22, rp_ndl);
    float rp_shade = 1.0;
    if (rpDetail > 0.5) {
    vec3 rp_off = (rp_Lo - rp_p * dot(rp_Lo, rp_p)) * (0.006 / max(dot(rp_Lo, rp_p), 0.2));
    vec2 rp_suv = rp_cuv + vec2(dot(rp_off, vec3(rp_p.z, 0.0, -rp_p.x)) / (6.2831853 * rp_ce * rp_ce), -rp_off.y / (3.1415927 * rp_ce));
    rp_shade = 1.0 - 0.55 * smoothstep(0.1, 0.82, textureGrad(rpEarthDay, rp_suv, rp_gx, rp_gy).w);
    }
    vec3 rp_tau = vec3(0.05, 0.12, 0.33);
    float rp_mv = 1.0 / (rp_mu + 0.035);
    float rp_ms = 1.0 / (max(rp_ndl, 0.0) + 0.035);
    vec3 rp_Ts = exp(-rp_tau * (rp_ms * 0.5));
    vec3 rp_Tv = exp(-rp_tau * (rp_mv * 0.5));
    float rp_sunE = rp_day * max(rp_ndl + 0.04, 0.0) * 0.96;
    float rp_lum = dot(rp_alb, vec3(0.2126, 0.7152, 0.0722));
    float rp_sea = rp_aux.y * (1.0 - smoothstep(0.05, 0.2, rp_lum));
    vec3 rp_H = normalize(rp_Lv + rp_V);
    float rp_nh = max(dot(rp_N, rp_H), 0.0);
    float rp_dd = rp_nh * rp_nh * (0.06 - 1.0) + 1.0;
    float rp_ggx = 0.06 / (3.1415927 * rp_dd * rp_dd);
    float rp_vh = 1.0 - max(dot(rp_V, rp_H), 0.0);
    float rp_fr = 0.02 + 0.98 * rp_vh * rp_vh * rp_vh * rp_vh * rp_vh;
    float rp_glint = 3.1415927 * rp_ggx * rp_fr * max(rp_ndl, 0.0) / (4.0 * max(max(rp_ndl, rp_mu), 0.05));
    rp_glint = rp_glint * rp_sea * (1.0 - rp_cloud) * 1.6;
    float rp_night = 1.0 - smoothstep(-0.16, 0.04, rp_ndl);
    float rp_city = rp_aux.x * rp_aux.x * rp_night * (1.0 - 0.85 * rp_cloud);
    vec3 rp_surf = (rp_alb * (rp_sunE * rp_shade) + vec3(rp_glint)) * rp_Ts + vec3(1.0, 0.62, 0.3) * (rp_city * 0.9);
    rp_surf = rp_surf * rp_Tv;
    float rp_cE = smoothstep(-0.14, 0.24, rp_ndl) * (max(rp_ndl, 0.0) * 0.85 + 0.15);
    vec3 rp_cl = vec3(0.82, 0.82, 0.82) * rp_cE * exp(-rp_tau * ((rp_ms + rp_mv) * 0.2));
    float rp_cosT = dot(rp_Lv, rp_V);
    float rp_msa = 1.0 / (max(rp_ndl + 0.1, 0.0) * 0.91 + 0.035);
    vec3 rp_air = vec3(1.0) - exp(-rp_tau * (rp_msa + rp_mv));
    rp_air = rp_air * (0.1875 * (1.0 + rp_cosT * rp_cosT) * rp_mv / (rp_msa + rp_mv) * smoothstep(-0.12, 0.08, rp_ndl));
    vec3 rp_col = mix(rp_surf, rp_cl, rp_cloud) + rp_air * (1.0 - 0.55 * rp_cloud);
    rp_col = max(rp_col, vec3(0.0));
    vec3 rp_over = max(rp_col - vec3(0.75), vec3(0.0));
    rp_col = min(rp_col, vec3(0.75)) + (vec3(1.0) - exp(-rp_over * 4.0)) * 0.25;
    rp_col = pow(rp_col, vec3(0.45454545));
    return rp_col;
}
vec3 moonBody(vec3 rp_N, vec3 rp_Lw) {
    vec3 rp_Lv = rp_Lw;
    vec3 rp_p = rp_N;
    int rp_oct = rpDetail > 0.5 ? 3 : 2;
    float rp_mh = rpFbm(rp_p * 2.4 + vec3(5.0, 3.0, 1.0), rp_oct);
    float rp_mare = 1.0 - smoothstep(0.4, 0.47, rp_mh);
    float rp_cr = rpNoise(rp_p * 8.5 + vec3(1.0, 2.0, 3.0));
    float rp_rim = smoothstep(0.6, 0.68, rp_cr) * (1.0 - smoothstep(0.7, 0.8, rp_cr));
    float rp_pit = smoothstep(0.74, 0.88, rp_cr);
    float rp_alb = 0.56 - 0.2 * rp_mare + 0.14 * rp_rim - 0.1 * rp_pit + 0.1 * (rp_mh - 0.5);
    float rp_ndl = dot(rp_N, rp_Lv);
    float rp_k = 1.15 * smoothstep(-0.03, 0.14, rp_ndl) * pow(max(rp_ndl, 0.02), 0.85);
    vec3 rp_col = vec3(0.93, 0.9, 0.86) * (rp_alb * (0.012 + rp_k));
    return rp_col;
}
"""

    // The thin air round a planet, and a gas giant's glow (GraphStyleShaders.halo).
    private const val HALO = """
vec3 halo(vec2 rp_q, vec3 rp_Lv, vec3 rpTintA, float rpThin) {
    float rp_qx = rp_q.x;
    float rp_qy = rp_q.y;
    float rp_r = length(rp_q) + 0.00001;
    vec3 rp_v0 = vec3(1.0, 0.0, 0.0);
    vec3 rp_v1 = vec3(0.0, 1.0, 0.0);
    float rp_rl = 0.667;
    float rp_lx = dot(rp_Lv, rp_v0);
    float rp_ly = dot(rp_Lv, rp_v1);
    float rp_dd = (rp_r - rp_rl) / 0.03;
    float rp_thin = exp(-rp_dd * rp_dd) * step(0.0, rp_r - rp_rl + 0.02);
    float rp_soft = exp(-max(rp_r - rp_rl, 0.0) / 0.07) * step(rp_rl, rp_r);
    float rp_dir = (rp_qx * rp_lx + rp_qy * rp_ly) / rp_r;
    float rp_back = max(-rp_Lv.z, 0.0);
    float rp_face = clamp(rp_dir * 0.8 + 0.35, 0.0, 1.0);
    float rp_lit = 0.12 + 1.1 * rp_face + 0.9 * rp_back;
    vec3 rp_col = rpTintA * ((rp_thin * 0.5 * rpThin + rp_soft * 0.35) * rp_lit);
    float rp_edge = exp(-rp_dir * rp_dir * 8.0) * (1.0 - rp_back);
    rp_col = rp_col * mix(vec3(1.0, 1.0, 1.0), vec3(1.35, 0.75, 0.55), rp_edge * 0.6);
    rp_col = rp_col * clamp((1.0 - rp_r) / 0.2, 0.0, 1.0);
    return rp_col;
}
"""

    private const val ROCKY_MAIN = """
void main() {
    vec3 c = vCenter.xyz;
    float r = vCenter.w;
    float R = r * 0.9;
    vec3 rd = rpRay();
    vec3 X;
    vec3 Y;
    vec3 Z;
    rpFrame(vec3(0.0, 1.0, 0.0), rpClock * rpMotion * 0.12 + vLight.w * 6.2831853, X, Y, Z);
    vec3 n;
    float cover;
    float t = rpSphere(rd, c, R, n, cover);
    vec4 planet = vec4(rockBody(n, -rd, X, Y, Z, vLight.xyz) * cover, cover);
    vec3 mn;
    float mcover;
    float mt = rpSphere(rd, c + vA.xyz * r, R * 0.27, mn, mcover);
    vec4 moon = vec4(moonBody(mn, vLight.xyz) * mcover, mcover);
    vec4 res = (mt > 0.0 && (t < 0.0 || mt < t)) ? rpOver(moon, planet) : rpOver(planet, moon);
    res.rgb = res.rgb + halo(rpPlane(c, R * 1.5), rpSeen(vLight.xyz, c), vec3(0.42, 0.66, 1.0), 1.0);
    fragColor = res;
}
"""

    // ---- the gas giant (gasBody, gasRing) ----

    private const val GAS = """
uniform float rpRinged;
uniform vec3 rpTintA;
uniform vec3 rpTintB;
uniform vec3 rpTintC;
uniform vec3 rpTintD;
vec3 gasBody(vec3 rp_N, vec3 rp_V, vec3 rp_v0, vec3 rp_v1, vec3 rp_v2, vec3 rp_Lw) {
    vec3 rp_Lv = rp_Lw;
    vec3 rp_Lo = vec3(dot(rp_v0, rp_Lw), dot(rp_v1, rp_Lw), dot(rp_v2, rp_Lw));
    float rp_mu = max(dot(rp_N, rp_V), 0.0);
    vec3 rp_p = normalize(vec3(dot(rp_v0, rp_N), dot(rp_v1, rp_N), dot(rp_v2, rp_N)));
    float rp_m = 0.0;
    float rp_t = rpClock * rpMotion;
    float rp_lat = rp_p.y;
    float rp_lon = atan(rp_p.z, rp_p.x);
    float rp_cl = sqrt(max(1.0 - rp_lat * rp_lat, 0.0));
    float rp_so = rp_lon + rp_t * 0.02 - 3.9;
    rp_so = rp_so - 6.2831853 * floor(rp_so / 6.2831853 + 0.5);
    float rp_stx = rp_so * rp_cl / 0.27;
    float rp_sty = (rp_lat - 0.3) / 0.1;
    float rp_s2 = rp_stx * rp_stx + rp_sty * rp_sty;
    float rp_sr = sqrt(rp_s2);
    float rp_bq0 = rp_lat * 6.5 + 0.13 * sin(rp_lat * 9.0);
    rp_bq0 = rp_bq0 + 0.35 * exp(-rp_s2 * 0.3) * rp_sty / (1.0 + abs(rp_sty));
    float rp_bi = floor(rp_bq0 + 0.5);
    float rp_way = 1.0 - 2.0 * (rp_bi - 2.0 * floor(rp_bi * 0.5));
    float rp_om = (0.04 + 0.12 * fract(sin(rp_bi * 3.7) * 43758.5453)) * rp_way * (1.0 + 0.8 * rp_m);
    float rp_lb = rp_lon + rp_t * rp_om;
    float rp_R = 1.6 * (1.0 - 0.6 * rp_m);
    vec3 rp_ring3 = vec3(cos(rp_lb) * rp_R, rp_lat * 9.0, sin(rp_lb) * rp_R);
    int rp_oct = rpDetail > 0.5 ? 5 : 3;
    float rp_tb = rpFbm(rp_ring3 + vec3(0.0, 0.0, rp_t * 0.01), rp_oct);
    float rp_ed = rpNoise(vec3(rp_ring3.x * 4.0, rp_lat * 34.0, rp_ring3.z * 4.0));
    float rp_bq = rp_bq0 + (rp_tb - 0.5) * 0.6 + (rp_ed - 0.5) * 0.2 * (1.0 - 0.6 * rp_m);
    float rp_bj = floor(rp_bq);
    float rp_bf = rp_bq - rp_bj;
    float rp_par = rp_bj - 2.0 * floor(rp_bj * 0.5);
    float rp_h1 = fract(sin(rp_bj * 12.9898) * 43758.5453);
    float rp_h2 = fract(sin((rp_bj + 1.0) * 12.9898) * 43758.5453);
    float rp_t1 = mix(0.74 + 0.24 * rp_h1, 0.14 + 0.3 * rp_h1, rp_par);
    float rp_t2 = mix(0.74 + 0.24 * rp_h2, 0.14 + 0.3 * rp_h2, 1.0 - rp_par);
    float rp_tone = mix(rp_t1, rp_t2, smoothstep(0.72, 1.0, rp_bf));
    float rp_zs = rpNoise(vec3(rp_ring3.x * 2.2, rp_bq * 16.0, rp_ring3.z * 2.2));
    rp_tone = rp_tone + (rp_zs - 0.5) * 0.24 + rp_m * 0.07 * sin(rp_bq * 70.0);
    vec3 rp_cloud = mix(rpTintC * (0.8 + 0.3 * rp_h1), rpTintB, smoothstep(0.1, 0.5, rp_tone));
    rp_cloud = mix(rp_cloud, rpTintA, smoothstep(0.5, 0.88, rp_tone));
    float rp_oq = rp_lb * 1.9098593 + 0.3;
    float rp_ox = (fract(rp_oq) - 0.5) / 0.16;
    float rp_oy = (rp_lat - 0.56 + 0.02 * (rp_tb - 0.5)) / 0.032;
    float rp_ov = exp(-rp_ox * rp_ox - rp_oy * rp_oy) * step(0.45, fract(sin(floor(rp_oq) * 7.31) * 43758.5453));
    rp_cloud = mix(rp_cloud, vec3(0.97, 0.95, 0.9), rp_ov * 0.85);
    float rp_pole = smoothstep(0.6, 0.97, abs(rp_lat) + 0.06 * (rp_tb - 0.5));
    rp_cloud = mix(rp_cloud, mix(rp_cloud, rpTintD, 0.6) * (0.8 + 0.4 * rp_tb), rp_pole);
    float rp_sa = atan(rp_sty, rp_stx) + 2.6 * exp(-rp_sr * 1.2) - rp_t * 0.35;
    float rp_sn = rpNoise(vec3(cos(rp_sa) * 2.2, sin(rp_sa) * 2.2, rp_sr * 2.5));
    float rp_sw = rp_sr * (1.0 + 0.16 * (rp_sn - 0.5));
    float rp_storm = 1.0 - smoothstep(0.82, 1.08, rp_sw);
    vec3 rp_red = mix(vec3(0.66, 0.27, 0.15), vec3(0.86, 0.5, 0.34), rp_sn);
    rp_red = rp_red * (0.85 + 0.25 * smoothstep(0.0, 0.7, rp_sr));
    float rp_cd = (rp_sw - 1.2) / 0.16;
    float rp_collar = exp(-rp_cd * rp_cd);
    rp_cloud = mix(rp_cloud, rp_red, rp_storm * 0.92);
    rp_cloud = mix(rp_cloud, vec3(0.95, 0.9, 0.82), rp_collar * 0.45);
    float rp_ly = abs(rp_Lo.y) < 0.001 ? 0.001 : rp_Lo.y;
    float rp_tt = -rp_lat / rp_ly;
    float rp_hx = rp_p.x + rp_Lo.x * rp_tt;
    float rp_hz = rp_p.z + rp_Lo.z * rp_tt;
    float rp_rho = sqrt(rp_hx * rp_hx + rp_hz * rp_hz);
    float rp_den = rpRingDensity(rp_rho);
    float rp_shade = 1.0 - 0.6 * rp_den * step(0.0, rp_tt) * rpRinged;
    vec3 rp_Vo = vec3(dot(rp_v0, rp_V), dot(rp_v1, rp_V), dot(rp_v2, rp_V));
    float rp_vy = abs(rp_Vo.y) < 0.001 ? 0.001 : rp_Vo.y;
    float rp_tv = -rp_lat / rp_vy;
    float rp_vx = rp_p.x + rp_Vo.x * rp_tv;
    float rp_vz = rp_p.z + rp_Vo.z * rp_tv;
    float rq_rho = sqrt(rp_vx * rp_vx + rp_vz * rp_vz);
    float rq_den = rpRingDensity(rq_rho);
    float rp_veil = 1.0 - 0.8 * rq_den * step(0.0, rp_tv) * rpRinged;
    float rp_ndl = dot(rp_N, rp_Lv);
    float rp_day = smoothstep(-0.1, 0.3, rp_ndl) * pow(max(rp_ndl, 0.04), 0.6);
    float rp_k = (0.015 + 1.1 * rp_day * rp_shade) * (0.6 + 0.4 * pow(max(rp_mu, 0.001), 0.45));
    vec3 rp_col = rp_cloud * rp_k;
    float rp_lm = 1.0 - rp_mu;
    float rp_fr = rp_lm * rp_lm * rp_lm;
    rp_col = rp_col + vec3(0.9, 0.78, 0.55) * (rp_fr * 0.18 * smoothstep(-0.3, 0.5, rp_ndl));
    rp_col = rp_col * rp_veil;
    return rp_col;
}
vec3 gasRing(float rp_px, float rp_py, vec3 rp_v0, vec3 rp_v1, vec3 rp_v2, vec3 rp_Lw, vec3 rp_eye, float rp_bodyPx) {
    vec3 rp_Lo = vec3(dot(rp_v0, rp_Lw), dot(rp_v1, rp_Lw), dot(rp_v2, rp_Lw));
    float rp_m = 0.0;
    float rp_rho = sqrt(rp_px * rp_px + rp_py * rp_py);
    float rp_den = rpRingDensity(rp_rho);
    float rp_near = smoothstep(150.0, 600.0, rp_bodyPx);
    float rp_q1 = rp_rho * 46.0;
    float rp_i1 = floor(rp_q1);
    float rp_f1 = fract(rp_q1);
    rp_f1 = rp_f1 * rp_f1 * (3.0 - 2.0 * rp_f1);
    float rp_mid = mix(fract(sin(rp_i1 * 12.9898) * 43758.5453), fract(sin((rp_i1 + 1.0) * 12.9898) * 43758.5453), rp_f1);
    float rp_q2 = rp_rho * 240.0;
    float rp_i2 = floor(rp_q2);
    float rp_f2 = fract(rp_q2);
    rp_f2 = rp_f2 * rp_f2 * (3.0 - 2.0 * rp_f2);
    float rp_fine = mix(fract(sin(rp_i2 * 7.137) * 43758.5453), fract(sin((rp_i2 + 1.0) * 7.137) * 43758.5453), rp_f2);
    float rp_band = (0.72 + 0.4 * rp_mid) * (1.0 + (rp_fine - 0.5) * 0.36 * rp_near);
    float rp_ek = (rp_rho - 2.14) / 0.008;
    float rp_encke = 1.0 - 0.8 * exp(-rp_ek * rp_ek);
    float rp_d = rp_den * rp_band * rp_encke;
    vec3 rp_hue = mix(vec3(0.46, 0.41, 0.36), vec3(0.96, 0.87, 0.7), smoothstep(1.44, 1.6, rp_rho));
    rp_hue = mix(rp_hue, vec3(0.8, 0.76, 0.69), smoothstep(1.98, 2.06, rp_rho));
    vec3 rp_Vo = vec3(dot(rp_v0, rp_eye), dot(rp_v1, rp_eye), dot(rp_v2, rp_eye));
    float rp_face = rp_Lo.z * rp_Vo.z >= 0.0 ? 1.0 : 0.0;
    float rp_lit = (0.3 + 0.7 * abs(rp_Lo.z)) * mix(0.3, 1.0, rp_face);
    float rp_fw = pow(max(-dot(rp_Lo, rp_Vo), 0.0), 6.0) * (1.0 - rp_face) * rp_d * (1.0 - min(rp_d, 1.0)) * 1.6;
    float rp_al = rp_px * rp_Lo.x + rp_py * rp_Lo.y;
    float rp_perp = rp_rho * rp_rho - rp_al * rp_al;
    float rp_sh = (1.0 - step(0.0, rp_al)) * (1.0 - smoothstep(0.85, 1.05, rp_perp));
    float rp_k = rp_d * rp_lit * (1.0 - 0.9 * rp_sh);
    rp_k = rp_k * (0.85 + 0.3 * rp_m);
    vec3 rp_col = rp_hue * (rp_k * 0.95) + vec3(1.0, 0.95, 0.85) * (rp_fw * (1.0 - rp_sh));
    return rp_col;
}
"""

    private const val GAS_MAIN = """
void main() {
    vec3 c = vCenter.xyz;
    float r = vCenter.w;
    float R = r * 1.15;
    vec3 rd = rpRay();
    vec3 X;
    vec3 Y;
    vec3 Z;
    rpFrame(vA.xyz, rpClock * rpMotion * 0.2 + vLight.w * 6.2831853, X, Y, Z);
    vec3 n;
    float cover;
    float t = rpSphere(rd, c, R, n, cover);
    vec4 res = vec4(gasBody(n, -rd, X, Y, Z, vLight.xyz) * cover, cover);
    float den = dot(rd, Y);
    float tr = abs(den) > 1e-6 ? dot(c - uEye, Y) / den : -1.0;
    if (tr > 0.0 && rpRinged > 0.5) {
        vec3 h = uEye + rd * tr - c;
        vec3 ring = gasRing(dot(h, X) / R, dot(h, Z) / R, X, Z, Y, vLight.xyz, normalize(uEye - c), vB.w * 1.15);
        float hidden = (t > 0.0 && tr > t) ? cover : 0.0;
        res.rgb = res.rgb + ring * (1.0 - hidden);
    }
    res.rgb = res.rgb + halo(rpPlane(c, R * 1.5), rpSeen(vLight.xyz, c), rpTintA * 0.8, 0.0);
    fragColor = res;
}
"""

    // ---- the pulsar (pulsarCore, pulsarGlow, pulsarBeam) ----

    private const val PULSAR = """
vec3 pulsarCore(float rp_mu) {
    float rp_t = rpClock * rpMotion;
    float rp_b = 0.5 + 0.5 * cos(rp_t * 1.3333333 * 6.2831853);
    rp_b = rp_b * rp_b;
    rp_b = rp_b * rp_b;
    rp_b = rp_b * rp_b;
    float rp_k = 0.72 + 0.2 * (1.0 - rp_mu) + 0.1 * rp_b;
    vec3 rp_col = vec3(0.82, 0.9, 1.0) * rp_k;
    return rp_col;
}
vec3 pulsarGlow(float rp_qx, float rp_qy, float rp_codeIn) {
    float rp_r = length(vec2(rp_qx, rp_qy)) + 0.00001;
    float rp_k = clamp(rp_codeIn - 2.0, 0.0, 1.0);
    float rp_t = rpClock * rpMotion;
    float rp_rl = 0.12;
    float rp_b = 0.5 + 0.5 * cos(rp_t * 1.3333333 * 6.2831853);
    rp_b = rp_b * rp_b;
    rp_b = rp_b * rp_b;
    rp_b = rp_b * rp_b;
    float rp_x = max(rp_r / rp_rl - 1.0, 0.0);
    float rp_h = 1.0 / (1.0 + rp_x * rp_x * 40.0) + 0.025 / (1.0 + rp_x * 1.5);
    rp_h = rp_h * (0.6 + 0.4 * rp_b) * step(rp_rl * 0.95, rp_r);
    vec3 rp_col = vec3(0.68, 0.8, 1.0) * (rp_h * 0.42);
    float rp_ratio = sqrt(max(1.0 - rp_k * rp_k, 0.0));
    float rp_B = max(rp_ratio, 0.08);
    float rp_ex = rp_qx;
    float rp_ey = rp_qy / rp_B;
    float rp_er = sqrt(rp_ex * rp_ex + rp_ey * rp_ey) + 0.00001;
    float rp_ang = atan(rp_ey, rp_ex);
    float rp_wn = rpNoise(vec3(cos(rp_ang) * 3.0, sin(rp_ang) * 3.0, rp_er * 7.0 - rp_t * 0.15));
    float rp_near = 1.0 + 0.45 * rp_k * (-rp_ey / rp_er);
    float rp_d1 = (rp_er - 0.21) / 0.022;
    float rp_d2 = (rp_er - 0.4) / 0.085;
    float rp_ring = exp(-rp_d1 * rp_d1) * (0.4 + 0.9 * rp_wn) * 0.8;
    float rp_torus = exp(-rp_d2 * rp_d2) * (0.3 + 0.9 * rp_wn) * 0.6;
    float rp_ay = abs(rp_qy);
    float rp_jet = exp(-rp_qx * rp_qx / (0.0012 + 0.008 * rp_ay)) * smoothstep(0.08, 0.2, rp_ay);
    rp_jet = rp_jet * exp(-rp_ay / (0.1 + 0.45 * rp_k)) * (0.6 + 0.4 * rp_wn) * 0.7;
    float rp_ne = length(vec2(rp_qx / 0.72, rp_qy / 0.6));
    float rp_fm = rpNoise(vec3(rp_qx * 2.4 + 3.0, rp_qy * 2.4, rp_t * 0.01));
    float rp_fa = rpNoise(vec3(rp_qx * 5.0 + rp_fm * 1.5, rp_qy * 5.0 - rp_fm * 1.2, 2.0 + rp_t * 0.012));
    float rp_fb = rpNoise(vec3(rp_qx * 13.0, rp_qy * 13.0, 5.0));
    float rp_ra = 1.0 - abs(rp_fa * 2.0 - 1.0);
    float rp_rb = 1.0 - abs(rp_fb * 2.0 - 1.0);
    float rp_fil = pow(rp_ra, 5.0) * (0.6 + 0.6 * rp_rb);
    float rp_env = exp(-rp_ne * rp_ne * 2.2) * (0.5 + 0.9 * rp_fm);
    vec3 rp_syn = mix(vec3(0.32, 0.42, 1.0), vec3(0.55, 0.75, 1.0), rp_fm) * (rp_env * 0.46);
    vec3 rp_warm = vec3(1.0, 0.5, 0.32) * (rp_fil * rp_env * 0.4);
    vec3 rp_wind = vec3(0.62, 0.78, 1.0) * ((rp_ring + rp_torus) * rp_near + rp_jet);
    rp_col = rp_col + (rp_wind + rp_syn + rp_warm) * (0.92 + 0.12 * rp_b);
    rp_col = rp_col * clamp((1.0 - rp_r) / 0.3, 0.0, 1.0);
    return rp_col;
}
vec3 pulsarBeam(float rp_qx, float rp_qy, float rp_m, float rp_off) {
    float rp_t = rpClock * rpMotion;
    float rp_face = rp_m;
    float rp_ay = abs(rp_qy);
    float rp_wd = 0.1 + 0.34 * rp_ay * (1.0 + 0.5 * rp_face);
    float rp_ac = rp_qx / rp_wd;
    float rp_prof = exp(-rp_ac * rp_ac * 2.5);
    float rp_spine = exp(-rp_ac * rp_ac * 28.0);
    float rp_fade = smoothstep(0.05, 0.14, rp_ay) * pow(max(1.0 - rp_ay, 0.0), 1.6);
    float rp_st = rpNoise(vec3(rp_ac * 2.5, rp_ay * 16.0 - rp_t * 7.0, step(0.0, rp_qy) * 7.0));
    float rp_flow = 0.65 + 0.6 * rp_st;
    float rp_f2 = rp_face * rp_face;
    float rp_k = (rp_prof * 0.85 + rp_spine * 0.9) * rp_fade * rp_flow * (0.6 + 1.0 * rp_f2 * rp_f2);
    rp_k = rp_k * (1.0 - 0.8 * rp_f2 * exp(-rp_ay / 0.25));
    rp_k = rp_k * smoothstep(1.0, 1.35, rp_off);
    vec3 rp_hue = mix(vec3(0.9, 0.95, 1.0), vec3(0.52, 0.45, 1.0), clamp(abs(rp_ac) * 0.7, 0.0, 1.0));
    vec3 rp_col = rp_hue * rp_k;
    return rp_col;
}
"""

    private const val PULSAR_MAIN = """
void main() {
    vec3 c = vCenter.xyz;
    float r = vCenter.w;
    float R = r * 0.3;
    vec3 rd = rpRay();
    vec3 n;
    float cover;
    rpSphere(rd, c, R, n, cover);
    vec4 res = vec4(pulsarCore(max(dot(n, -rd), 0.0)) * cover, cover);
    vec2 q = rpPlane(c, r * 2.5);
    float turn = vLight.x;
    vec2 xN = vec2(cos(turn), sin(turn));
    vec2 yN = vec2(-xN.y, xN.x);
    vec2 g = vec2(dot(q, xN), dot(q, yN));
    if (abs(g.x) <= 1.0 && abs(g.y) <= 1.0) res.rgb = res.rgb + pulsarGlow(g.x, g.y, vA.w);
    vec3 b = normalize(vA.xyz);
    vec3 x = rpAcross(b, c);
    vec2 s = rpStrip(rd, c, b, x) / vec2(r * 0.9, r * 6.0);
    float face = abs(dot(b, normalize(uEye - c)));
    float off = length(cross(rd, c - uEye)) / R;
    if (abs(s.x) <= 1.0 && abs(s.y) <= 1.0) res.rgb = res.rgb + pulsarBeam(s.x, s.y, face, off);
    fragColor = res;
}
"""

    // ---- the comet (cometNucleus, cometComa, cometTail, cometDust) ----

    private const val COMET = """
vec3 cometNucleus(vec3 rp_N, vec3 rp_Lw) {
    vec3 rp_Lv = rp_Lw;
    vec3 rp_p = rp_N;
    float rp_nn = rpNoise(rp_p * 2.6 + vec3(2.0, 7.0, 1.0));
    float rp_nf = rpNoise(rp_p * 7.0);
    float rp_ndl = dot(rp_N, rp_Lv) + (rp_nn - 0.5) * 0.7 + (rp_nf - 0.5) * 0.3;
    float rp_k = 0.02 + 0.55 * smoothstep(-0.1, 0.5, rp_ndl);
    vec3 rp_col = vec3(0.56, 0.54, 0.5) * (rp_k * (0.7 + 0.4 * rp_nf));
    return rp_col;
}
vec3 cometComa(float rp_qx, float rp_qy, vec3 rp_Lv) {
    float rp_r = length(vec2(rp_qx, rp_qy)) + 0.00001;
    vec3 rp_v0 = vec3(1.0, 0.0, 0.0);
    vec3 rp_v1 = vec3(0.0, 1.0, 0.0);
    float rp_t = rpClock * rpMotion;
    float rp_lx = dot(rp_Lv, rp_v0);
    float rp_ly = dot(rp_Lv, rp_v1);
    float rp_cx = rp_qx / 0.1875;
    float rp_cy = rp_qy / 0.1875;
    float rp_cr = sqrt(rp_cx * rp_cx + rp_cy * rp_cy) + 0.0001;
    float rp_lp = sqrt(rp_lx * rp_lx + rp_ly * rp_ly) + 0.0001;
    float rp_ca = (rp_cx * rp_lx + rp_cy * rp_ly) / (rp_cr * rp_lp);
    float rp_sw = rp_ca * min(rp_lp * 1.5, 1.0);
    float rp_re = rp_cr * (1.0 + 0.5 * max(rp_sw, 0.0)) * (1.0 + 0.3 * min(rp_sw, 0.0));
    float rp_ang = atan(rp_cy, rp_cx);
    float rp_cn = rpNoise(vec3(cos(rp_ang) * 2.5, sin(rp_ang) * 2.5, rp_cr * 1.2 - rp_t * 0.08));
    float rp_g = 0.5 / (rp_re + 0.22) * exp(-rp_re * 0.24) * (0.8 + 0.4 * rp_cn);
    float rp_cd = (rp_re - 0.85) / 0.3;
    float rp_core = exp(-rp_cd * rp_cd) * 0.45;
    float rp_clear = 0.2 + 0.8 * smoothstep(0.5, 1.05, rp_cr);
    float rp_spin = rp_ang + rp_cr * 0.18 - rp_t * 0.25;
    float rp_j1 = pow(0.5 + 0.5 * cos(rp_spin * 3.0 + 0.6), 6.0);
    float rp_j2 = pow(0.5 + 0.5 * cos(rp_spin * 5.0 + 2.1), 9.0) * 0.6;
    float rp_fan = (rp_j1 + rp_j2) * smoothstep(-0.3, 0.6, rp_sw) * smoothstep(0.5, 0.95, rp_cr);
    rp_fan = rp_fan * exp(-rp_cr * 0.5) * (0.7 + 0.6 * rp_cn) * 0.32;
    vec3 rp_hue = mix(vec3(1.0, 0.99, 0.95), vec3(0.98, 0.94, 0.78), smoothstep(0.2, 1.0, rp_cr));
    rp_hue = mix(rp_hue, vec3(0.36, 1.0, 0.66), smoothstep(0.7, 2.6, rp_cr));
    float rp_edge = clamp((1.0 - rp_r) / 0.3, 0.0, 1.0);
    vec3 rp_col = (rp_hue * (rp_g * rp_clear + rp_core) + vec3(1.0, 0.97, 0.9) * rp_fan) * rp_edge;
    return rp_col;
}
vec3 cometTail(float rp_qx, float rp_qy, float rp_m) {
    float rp_t = rpClock * rpMotion;
    float rp_ty = rp_qy * 0.5 + 0.5;
    float rp_tx = rp_qx;
    float rp_wi = 0.035 + 0.12 * rp_ty;
    float rp_in = rpNoise(vec3(rp_tx * 9.0, rp_ty * 5.0 - rp_t * 0.9, 0.0));
    float rp_kink = (rp_in - 0.5) * 0.12 * rp_ty;
    float rp_ix = (rp_tx - rp_kink) / rp_wi;
    float rp_str = 0.55 + 0.45 * sin(rp_tx * 60.0 / (0.4 + rp_ty) + rp_in * 4.0);
    float rp_ion = exp(-rp_ix * rp_ix) * pow(max(1.0 - rp_ty, 0.0), 1.1) * rp_str;
    float rp_kn = rpNoise(vec3(rp_ty * 7.0 - rp_t * 1.6, 3.0, 1.0));
    rp_ion = rp_ion * (0.7 + 0.6 * smoothstep(0.55, 0.85, rp_kn));
    float rp_head = exp(-rp_ty * 10.0) * exp(-rp_tx * rp_tx * 40.0);
    vec3 rp_col = vec3(0.42, 0.64, 1.0) * (rp_ion * 1.35) + vec3(0.8, 0.92, 1.0) * (rp_head * 0.5);
    rp_col = rp_col * (0.8 + 0.6 * rp_m);
    return rp_col;
}
vec3 cometDust(float rp_qx, float rp_qy, float rp_m) {
    float rp_t = rpClock * rpMotion;
    float rp_ty = rp_qy * 0.5 + 0.5;
    float rp_tx = rp_qx;
    float rp_xc = 0.38 * rp_ty * rp_ty;
    float rp_wd = 0.06 + 0.42 * rp_ty;
    float rp_dx = (rp_tx - rp_xc) / rp_wd;
    float rp_fan = exp(-rp_dx * rp_dx) * pow(max(1.0 - rp_ty, 0.0), 1.6);
    float rp_sa = atan(rp_tx - rp_xc * 0.5, rp_ty + 0.05);
    float rp_striae = 0.72 + 0.28 * sin(rp_sa * 34.0 + rp_t * 0.2);
    float rp_bq = rp_dx * 0.35 + rp_ty * 7.0 - rp_ty * rp_ty * 3.0 - rp_t * 0.05;
    float rp_bi = floor(rp_bq);
    float rp_bf = fract(rp_bq) - 0.5;
    float rp_bh = fract(sin(rp_bi * 7.31 + 1.7) * 43758.5453);
    float rp_band = exp(-rp_bf * rp_bf * 18.0) * (0.3 + 0.7 * rp_bh);
    rp_striae = rp_striae * (0.6 + 1.0 * rp_band * smoothstep(0.08, 0.3, rp_ty));
    float rp_head = exp(-rp_ty * 7.0) * exp(-rp_tx * rp_tx * 25.0);
    vec3 rp_col = vec3(1.0, 0.92, 0.74) * (rp_fan * 1.05 * rp_striae);
    rp_col = rp_col + vec3(1.0, 0.97, 0.88) * (rp_head * 0.45);
    float rp_pq = rp_ty * 9.0 - rp_t * 2.2;
    float rp_pf = fract(rp_pq) - 0.5;
    float rp_ph = fract(sin(floor(rp_pq) * 5.17) * 43758.5453);
    float rp_pd = (rp_tx - rp_xc - (rp_ph - 0.5) * rp_wd * 1.2) / (0.03 + 0.05 * rp_ty);
    float rp_puff = exp(-rp_pf * rp_pf * 60.0 - rp_pd * rp_pd) * step(0.4, rp_ph) * rp_m;
    rp_col = rp_col + vec3(1.0, 0.93, 0.78) * (rp_puff * 0.5 * (1.0 - rp_ty));
    rp_col = rp_col * (0.8 + 0.5 * rp_m);
    return rp_col;
}
"""

    private const val COMET_MAIN = """
void main() {
    vec3 c = vCenter.xyz;
    float r = vCenter.w;
    vec3 rd = rpRay();
    vec3 n;
    float cover;
    rpSphere(rd, c, r * 0.18, n, cover);
    vec4 res = vec4(cometNucleus(n, vLight.xyz) * cover, cover);
    vec2 q = rpPlane(c, r * 1.6);
    if (abs(q.x) <= 1.0 && abs(q.y) <= 1.0) res.rgb = res.rgb + cometComa(q.x, q.y, rpSeen(vLight.xyz, c));
    vec3 ion = normalize(vA.xyz);
    vec2 a = rpStrip(rd, c, ion, rpAcross(ion, c));
    vec2 ti = vec2(a.x / (r * 0.8), a.y / (r * 3.5) - 1.0);
    if (abs(ti.x) <= 1.0 && abs(ti.y) <= 1.0) res.rgb = res.rgb + cometTail(ti.x, ti.y, 0.0);
    vec3 dust = normalize(vB.xyz);
    vec3 dx = rpAcross(dust, c);
    if (dot(dx, dust - ion) < 0.0) dx = -dx;
    vec2 d = rpStrip(rd, c, dust, dx);
    vec2 td = vec2(d.x / (r * 1.5), d.y / (r * 2.975) - 1.0);
    if (abs(td.x) <= 1.0 && abs(td.y) <= 1.0) res.rgb = res.rgb + cometDust(td.x, td.y, 0.0);
    fragColor = res;
}
"""

    // ---- the link (GraphStyleShaders.link) as a glowing beam ----

    // One quad per link that touches a body, facing the eye: x runs from the A end (the higher
    // style code: suns and pulsars send, black holes swallow) to the B end, y across.
    private const val LINK_VS = """#version 300 es
precision highp float;
layout(location = 0) in vec2 aCorner;
layout(location = 1) in vec4 aA;
layout(location = 2) in vec4 aB;
layout(location = 3) in vec2 aInfo;
uniform mat4 uVP;
uniform vec3 uEye;
uniform float uUnit;
uniform float uHalf;
uniform float uFocal;
out float vAlong;
out float vS0;
flat out vec4 vInfo;
flat out float vLen;
void main() {
    vec3 d = aB.xyz - aA.xyz;
    float len = length(d);
    vec3 dir = len > 1e-6 ? d / len : vec3(1.0, 0.0, 0.0);
    vec3 p = aA.xyz + d * aCorner.x;
    vec3 side = cross(dir, uEye - p);
    float sl = length(side);
    side = sl > 1e-6 ? side / sl : vec3(0.0, 1.0, 0.0);
    float hw = max(uHalf * uUnit, 1.5 * length(uEye - p) / uFocal);
    gl_Position = uVP * vec4(p + side * (aCorner.y * hw), 1.0);
    vAlong = aCorner.x * len / uUnit;
    vLen = len / uUnit;
    vS0 = aCorner.y;
    vInfo = vec4(aA.w, aB.w, aInfo.x, aInfo.y);
}
"""

    private const val LINK_FS_BODY = """#version 300 es
precision highp float;
uniform float rpClock;
uniform float rpMotion;
uniform float rpEnergy;
uniform float rpSolid;
uniform float rpReach;
in float vAlong;
in float vS0;
flat in vec4 vInfo;
flat in float vLen;
out vec4 fragColor;
void main() {
    float rp_sA = vInfo.x;
    float rp_sB = vInfo.y;
    float rp_seed = vInfo.z;
    float rp_lit = vInfo.w;
    float rp_along = vAlong;
    float rp_len = vLen;
    float rp_s0 = vS0;
    float rp_toEnd = max(rp_len - rp_along, 0.0);
    float rp_x = rp_along + rp_seed * 1.37;
    float rp_m = rpMotion;
    float rp_t = rpClock * rp_m;
    float rp_bhA = 1.0 - step(0.5, rp_sA);
    float rp_bhB = 1.0 - step(0.5, rp_sB);
    float rp_rkB = step(0.5, rp_sB) - step(1.5, rp_sB);
    float rp_gsB = step(1.5, rp_sB) - step(2.5, rp_sB);
    float rp_cmA = step(2.5, rp_sA) - step(3.5, rp_sA);
    float rp_cmB = step(2.5, rp_sB) - step(3.5, rp_sB);
    float rp_psA = step(3.5, rp_sA) - step(4.5, rp_sA);
    float rp_psB = step(3.5, rp_sB) - step(4.5, rp_sB);
    float rp_sunA = step(4.5, rp_sA);
    float rp_sunB = step(4.5, rp_sB);
    float rp_smA = rp_cmA + rp_psA;
    float rp_smB = rp_cmB + rp_psB;
    float rp_reach = max(rpReach, 0.05);
    float rp_nA = exp(-rp_along / rp_reach);
    float rp_nB = exp(-rp_toEnd / rp_reach);
    float rp_bhW = rp_bhA * rp_nA + rp_bhB * rp_nB;
    float rp_sunW = rp_sunA * rp_nA + rp_sunB * rp_nB;
    float rp_ejW = rp_sunA * rp_nA;
    float rp_cmW = rp_cmA * rp_nA + rp_cmB * rp_nB;
    float rp_rkW = rp_rkB * rp_nB;
    float rp_gsW = rp_gsB * rp_nB;
    float rp_dS = max(rp_toEnd, 0.02);
    float rp_turn = log(rp_dS / rp_reach) * 5.0 + rp_t * 4.0;
    float rp_amp = 0.42 * rp_bhB * rp_nB;
    rp_amp = rp_amp * smoothstep(0.0, 0.5 * rp_reach, rp_toEnd);
    float rp_s = rp_s0 - rp_amp * sin(rp_turn);
    float rp_a = abs(rp_s);
    float rp_a2 = rp_a * rp_a * (1.0 + 2.5 * rp_bhW);
    float rp_tpA = smoothstep(0.0, (0.6 + 1.8 * rp_smA) * rp_reach, rp_along);
    float rp_tpB = smoothstep(0.0, (0.6 + 1.8 * rp_smB) * rp_reach, rp_toEnd);
    float rp_wlo = 0.3 - 0.14 * clamp(rp_smA + rp_smB, 0.0, 1.0);
    float rp_wf = rp_wlo + (1.0 - rp_wlo) * rp_tpA * rp_tpB;
    rp_a2 = rp_a2 / (rp_wf * rp_wf);
    float rp_e = abs(rp_s0);
    float rp_w = clamp(1.0 - rp_e * rp_e, 0.0, 1.0);
    float rp_w2 = rp_w * rp_w;
    float rp_w3 = rp_w2 * rp_w;
    float rp_qD = rp_x * 0.35 - rp_t * 0.12 + rp_seed * 7.1;
    float rp_iD = floor(rp_qD);
    float rp_fD = fract(rp_qD);
    rp_fD = rp_fD * rp_fD * (3.0 - 2.0 * rp_fD);
    float rp_aD = fract(sin(rp_iD * 12.9898 + rp_seed * 3.7) * 43758.5453);
    float rp_bD = fract(sin((rp_iD + 1.0) * 12.9898 + rp_seed * 3.7) * 43758.5453);
    float rp_nD = mix(rp_aD, rp_bD, rp_fD);
    float rp_qV = rp_x * 0.5 + rp_t * 0.05 + rp_seed * 3.3;
    float rp_iV = floor(rp_qV);
    float rp_fV = fract(rp_qV);
    rp_fV = rp_fV * rp_fV * (3.0 - 2.0 * rp_fV);
    float rp_aV = fract(sin(rp_iV * 12.9898 + rp_seed * 5.1 + 17.0) * 43758.5453);
    float rp_bV = fract(sin((rp_iV + 1.0) * 12.9898 + rp_seed * 5.1 + 17.0) * 43758.5453);
    float rp_nV = mix(rp_aV, rp_bV, rp_fV);
    float rp_qH = rp_x * 0.45 - rp_t * 0.15 + rp_seed * 5.7;
    float rp_iH = floor(rp_qH);
    float rp_fH = fract(rp_qH);
    rp_fH = rp_fH * rp_fH * (3.0 - 2.0 * rp_fH);
    float rp_aH = fract(sin(rp_iH * 12.9898 + rp_seed * 1.9 + 31.0) * 43758.5453);
    float rp_bH = fract(sin((rp_iH + 1.0) * 12.9898 + rp_seed * 1.9 + 31.0) * 43758.5453);
    float rp_nH = mix(rp_aH, rp_bH, rp_fH);
    float rp_core = exp(-rp_a2 * 300.0) * rp_w;
    rp_core = max(rp_core, exp(-rp_a2 * 40.0) * rp_w * rpSolid);
    float rp_inner = exp(-rp_a2 * 22.0) * rp_w2;
    float rp_breath = 1.0 + 0.1 * rp_m * sin(rp_t * 1.0471976 + rp_seed * 2.3);
    float rp_thick = (0.7 + 0.5 * rp_nH) * rp_breath * (1.0 + 0.8 * rp_gsW);
    float rp_haze = exp(-rp_a2 * 6.0 / (rp_thick * rp_thick)) * rp_w3;
    rp_haze = rp_haze * (0.16 + 0.22 * rp_nD);
    rp_haze = rp_haze * (1.0 + 1.5 * rp_sunW + 1.5 * rp_gsW);
    float rp_fall = 0.75 * rp_bhB * rp_reach;
    float rp_throw = 0.6 * rp_sunA * rp_reach;
    float rp_gone = exp(-rp_len / rp_reach);
    float rp_X = rp_x - rp_fall * (rp_nB - rp_gone);
    rp_X = rp_X - rp_throw * (1.0 - rp_nA);
    float rp_pp = rp_X * 0.3 - rp_t * 0.42 + rp_seed * 0.618;
    float rp_pi = floor(rp_pp);
    float rp_dw = (fract(rp_pp) - 0.5) / 0.3;
    float rp_sig = mix(0.7, 0.4, smoothstep(-0.2, 0.2, rp_dw));
    float rp_pz = rp_dw / rp_sig;
    float rp_ph = fract(sin(rp_pi * 7.13 + rp_seed) * 43758.5453);
    float rp_pulse = exp(-rp_pz * rp_pz) * (0.45 + 0.55 * rp_ph) * rp_m;
    rp_pulse = rp_pulse * (1.0 + 1.2 * rp_ejW);
    float rp_sp = rp_X * 0.13 - rp_t * 0.31 + rp_seed * 0.37;
    float rp_si = floor(rp_sp);
    float rp_sw = (fract(rp_sp) - 0.5) / 0.13;
    float rp_ssig = mix(1.0, 0.5, smoothstep(-0.3, 0.3, rp_sw));
    float rp_sz = rp_sw / rp_ssig;
    float rp_sh = fract(sin(rp_si * 3.31 + rp_seed * 1.7) * 43758.5453);
    float rp_surge = exp(-rp_sz * rp_sz) * smoothstep(0.55, 0.9, rp_sh) * rp_m;
    float rp_mid = exp(-rp_a2 * (20.0 - 14.0 * rp_ejW));
    float rp_kick = (rp_pulse * 1.2 + rp_surge * 2.2) * rp_mid;
    float rp_xEnd = rp_len + rp_seed * 1.37;
    float rp_XEnd = rp_xEnd - rp_fall * (1.0 - rp_gone);
    rp_XEnd = rp_XEnd - rp_throw * (1.0 - rp_gone);
    float rp_qe = rp_XEnd * 0.3 - rp_t * 0.42 + rp_seed * 0.618;
    float rp_de = (fract(rp_qe) - 0.5) / 0.3;
    float rp_ze = rp_de / mix(0.7, 0.4, smoothstep(-0.2, 0.2, rp_de));
    float rp_he = fract(sin(floor(rp_qe) * 7.13 + rp_seed) * 43758.5453);
    float rp_arrive = exp(-rp_ze * rp_ze) * (0.45 + 0.55 * rp_he) * rp_m;
    float rp_still = (1.0 - rp_m) * rp_lit;
    rp_arrive = rp_arrive + 0.55 * rp_still;
    vec3 rp_gold = vec3(1.0, 0.753, 0.302);
    vec3 rp_white = vec3(1.0, 0.95, 0.84);
    vec3 rp_orange = vec3(1.0, 0.416, 0.0);
    vec3 rp_amber = vec3(1.0, 0.30, 0.02);
    vec3 rp_violet = vec3(0.45, 0.28, 1.0);
    vec3 rp_ember = vec3(0.62, 0.08, 0.0);
    float rp_heat = rp_core * 0.9 + rp_inner * 0.3;
    rp_heat = clamp(rp_heat + rp_kick * 0.5 + rp_sunW * 0.5, 0.0, 1.0);
    float rp_rim = smoothstep(0.5, 1.0, rp_a) * 0.55;
    vec3 rp_base = mix(rp_orange, rp_violet, rp_rim);
    vec3 rp_hot = mix(rp_gold, rp_white, clamp(rp_heat * 2.0 - 1.0, 0.0, 1.0));
    vec3 rp_hue = mix(rp_base, rp_hot, rp_heat);
    rp_hue = mix(rp_hue, rp_white, clamp(rp_sunW * 0.7, 0.0, 1.0));
    rp_hue = mix(rp_hue, rp_ember, clamp(rp_bhW * rp_bhW * 0.8, 0.0, 1.0));
    rp_hue = mix(rp_hue, vec3(0.55, 0.95, 1.0), clamp(rp_cmW * 0.55, 0.0, 1.0));
    rp_hue = mix(rp_hue, vec3(0.7, 0.85, 1.0), clamp(rp_rkW * 0.3, 0.0, 1.0));
    rp_hue = mix(rp_hue, vec3(1.0, 0.85, 0.6), clamp(rp_gsW * 0.45, 0.0, 1.0));
    float rp_glow = rp_core * 0.8 + rp_inner * 0.4 + rp_haze;
    rp_glow = rp_glow + (rp_core * 1.6 + rp_inner * 0.4) * rp_kick;
    rp_glow = rp_glow * (1.0 + 0.9 * rp_sunW) * (1.0 - 0.45 * rp_bhW);
    vec3 rp_col = rp_hue * rp_glow;
    vec3 rp_fl = vec3(0.0);
    float rp_qA = rp_s * 26.0 + rp_seed * 3.0 + 0.0;
    float rp_iA = floor(rp_qA);
    float rp_fA = fract(rp_qA) - 0.5;
    float rp_haA = fract(sin(rp_iA * 12.9898 + rp_seed * 78.233 + 0.0) * 43758.5453);
    float rp_hbA = fract(sin(rp_iA * 39.346 + rp_seed * 11.135 + 0.0) * 43758.5453);
    float rp_profA = exp(-rp_fA * rp_fA * 38.0);
    float rp_phA = rp_x * (0.35 + rp_haA * 0.9) + rp_haA * 6.2831;
    float rp_runA = rp_t * 5.0 * (0.6 + rp_hbA);
    float rp_slowA = 0.5 + 0.5 * sin(rp_phA - rp_runA * 0.6);
    float rp_fastA = 0.5 + 0.5 * sin(rp_phA - rp_runA * 1.5);
    float rp_flowA = mix(rp_slowA, rp_fastA, rp_nV);
    rp_flowA = rp_flowA * rp_flowA * rp_flowA;
    rp_flowA = rp_flowA * rp_flowA;
    float rp_glA = (0.12 + 1.1 * rp_flowA) * (0.3 + 0.7 * rp_hbA);
    rp_glA = rp_glA * (0.3 + rp_nD);
    vec3 rp_warmA = mix(rp_amber, rp_orange, clamp(rp_haA * 2.0, 0.0, 1.0));
    vec3 rp_hotA = mix(rp_gold, rp_white, clamp(rp_haA * 2.0 - 1.0, 0.0, 1.0));
    vec3 rp_hueA = mix(rp_warmA, rp_hotA, rp_haA);
    rp_fl = rp_fl + rp_hueA * (rp_profA * rp_glA * 0.9);
    float rp_qB = rp_s * 11.0 + rp_seed * 3.0 + 17.0;
    float rp_iB = floor(rp_qB);
    float rp_fB = fract(rp_qB) - 0.5;
    float rp_haB = fract(sin(rp_iB * 12.9898 + rp_seed * 78.233 + 17.0) * 43758.5453);
    float rp_hbB = fract(sin(rp_iB * 39.346 + rp_seed * 11.135 + 17.0) * 43758.5453);
    float rp_profB = exp(-rp_fB * rp_fB * 38.0);
    float rp_phB = rp_x * (0.35 + rp_haB * 0.9) + rp_haB * 6.2831;
    float rp_runB = rp_t * 3.0 * (0.6 + rp_hbB);
    float rp_slowB = 0.5 + 0.5 * sin(rp_phB - rp_runB * 0.6);
    float rp_fastB = 0.5 + 0.5 * sin(rp_phB - rp_runB * 1.5);
    float rp_flowB = mix(rp_slowB, rp_fastB, rp_nV);
    rp_flowB = rp_flowB * rp_flowB * rp_flowB;
    rp_flowB = rp_flowB * rp_flowB;
    float rp_glB = (0.12 + 1.1 * rp_flowB) * (0.3 + 0.7 * rp_hbB);
    rp_glB = rp_glB * (0.3 + rp_nD);
    vec3 rp_warmB = mix(rp_amber, rp_orange, clamp(rp_haB * 2.0, 0.0, 1.0));
    vec3 rp_hotB = mix(rp_gold, rp_white, clamp(rp_haB * 2.0 - 1.0, 0.0, 1.0));
    vec3 rp_hueB = mix(rp_warmB, rp_hotB, rp_haB);
    rp_fl = rp_fl + rp_hueB * (rp_profB * rp_glB * 0.7);
    float rp_qC = rp_s * 53.0 + rp_seed * 3.0 + 31.0;
    float rp_iC = floor(rp_qC);
    float rp_fC = fract(rp_qC) - 0.5;
    float rp_haC = fract(sin(rp_iC * 12.9898 + rp_seed * 78.233 + 31.0) * 43758.5453);
    float rp_hbC = fract(sin(rp_iC * 39.346 + rp_seed * 11.135 + 31.0) * 43758.5453);
    float rp_profC = exp(-rp_fC * rp_fC * 38.0);
    float rp_phC = rp_x * (0.35 + rp_haC * 0.9) + rp_haC * 6.2831;
    float rp_runC = rp_t * 7.5 * (0.6 + rp_hbC);
    float rp_slowC = 0.5 + 0.5 * sin(rp_phC - rp_runC * 0.6);
    float rp_fastC = 0.5 + 0.5 * sin(rp_phC - rp_runC * 1.5);
    float rp_flowC = mix(rp_slowC, rp_fastC, rp_nV);
    rp_flowC = rp_flowC * rp_flowC * rp_flowC;
    rp_flowC = rp_flowC * rp_flowC;
    float rp_glC = (0.12 + 1.1 * rp_flowC) * (0.3 + 0.7 * rp_hbC);
    rp_glC = rp_glC * (0.3 + rp_nD);
    vec3 rp_warmC = mix(rp_amber, rp_orange, clamp(rp_haC * 2.0, 0.0, 1.0));
    vec3 rp_hotC = mix(rp_gold, rp_white, clamp(rp_haC * 2.0 - 1.0, 0.0, 1.0));
    vec3 rp_hueC = mix(rp_warmC, rp_hotC, rp_haC);
    rp_fl = rp_fl + rp_hueC * (rp_profC * rp_glC * 0.45);
    rp_col = rp_col + rp_fl * (rp_w2 * 0.4 * (1.0 + rp_sunW) * exp(-rp_a2 * 3.0));
    float rp_ph1 = rp_x * 3.1 - rp_t * 2.3 + rp_seed * 1.3;
    rp_ph1 = rp_ph1 + rp_nH * 2.0;
    float rp_y1 = 0.32 * (0.6 + 0.8 * rp_nH) * sin(rp_ph1);
    float rp_e1 = rp_s - rp_y1;
    float rp_h1 = exp(-rp_e1 * rp_e1 * 900.0) * (0.55 + 0.45 * cos(rp_ph1));
    float rp_ph2 = rp_x * 2.3 + rp_t * 1.4 + rp_seed * 2.9;
    rp_ph2 = rp_ph2 - rp_nH * 1.5;
    float rp_y2 = 0.26 * (1.3 - 0.6 * rp_nH) * sin(rp_ph2);
    float rp_e2 = rp_s - rp_y2;
    float rp_h2 = exp(-rp_e2 * rp_e2 * 900.0) * (0.55 + 0.45 * cos(rp_ph2));
    float rp_helix = (rp_h1 + rp_h2) * rp_w * 0.5 * rp_m;
    rp_col = rp_col + mix(rp_gold, rp_white, 0.5) * rp_helix;
    float rp_mq = rp_x * 5.0 - rp_t * 1.15 + rp_seed * 0.71;
    float rp_mi = floor(rp_mq);
    float rp_mh = fract(sin(rp_mi * 17.31 + rp_seed * 5.13) * 43758.5453);
    float rp_my = (fract(rp_mh * 13.7) - 0.5) * 1.1;
    float rp_md = (fract(rp_mq) - 0.5) * 5.7;
    float rp_mc = (rp_s - rp_my) / 0.09;
    float rp_mote = exp(-rp_md * rp_md - rp_mc * rp_mc) * step(0.5, rp_mh);
    float rp_oq = rp_x * 3.0 + rp_t * 0.55 + rp_seed * 1.9;
    float rp_oi = floor(rp_oq);
    float rp_oh = fract(sin(rp_oi * 29.17 + rp_seed * 3.71) * 43758.5453);
    float rp_oy = (fract(rp_oh * 7.3) - 0.5) * 1.3;
    float rp_od = (fract(rp_oq) - 0.5) * 4.2;
    float rp_oc = (rp_s - rp_oy) / 0.07;
    rp_mote = rp_mote + 0.6 * exp(-rp_od * rp_od - rp_oc * rp_oc) * step(0.62, rp_oh);
    float rp_mtw = 0.55 + 0.45 * sin(rp_t * 5.0 + rp_mh * 40.0);
    rp_col = rp_col + mix(rp_gold, rp_white, 0.6) * (rp_mote * rp_mtw * 0.55 * rp_w * rp_m);
    float rp_dP = rp_psA * rp_along + rp_psB * rp_toEnd;
    float rp_isP = clamp(rp_psA + rp_psB, 0.0, 1.0);
    float rp_beat = rp_t * 1.3333333 - rp_dP * 0.8;
    float rp_tick = 0.5 + 0.5 * cos(rp_beat * 6.2831853);
    rp_tick = rp_tick * rp_tick;
    rp_tick = rp_tick * rp_tick;
    rp_tick = rp_tick * rp_tick;
    float rp_sync = (rp_tick + 0.15) * rp_isP;
    rp_sync = rp_sync * exp(-rp_dP / (6.0 * rp_reach));
    float rp_syncGlow = rp_core * 1.4 + rp_inner * 0.5;
    rp_col = rp_col + vec3(0.72, 0.8, 1.0) * (rp_syncGlow * rp_sync);
    float rp_drag = rp_lit * rp_sunA * rp_m;
    float rp_jq = rp_x * 1.4 - rp_t * 2.6 + rp_seed * 0.9;
    float rp_jf = fract(rp_jq) - 0.5;
    float rp_jh = fract(sin(floor(rp_jq) * 11.3 + rp_seed) * 43758.5453);
    float rp_jet = exp(-rp_jf * rp_jf * 70.0) * exp(-rp_a2 * 9.0) * (0.5 + 0.5 * rp_jh);
    rp_jet = rp_jet * (0.35 + 0.65 * exp(-rp_along / (3.0 * rp_reach)));
    rp_col = rp_col + vec3(1.0, 0.9, 0.66) * (rp_jet * rp_drag * 1.3);
    float rp_cx = floor(rp_x * 16.0);
    float rp_cy = floor(rp_s0 * 4.0);
    float rp_ch = fract(sin(rp_cx * 17.13 + rp_cy * 5.71 + rp_seed) * 43758.5453);
    float rp_cf = fract(rp_x * 16.0) - 0.5;
    float rp_cg = fract(rp_s0 * 4.0) - 0.5;
    float rp_speck = exp(-(rp_cf * rp_cf + rp_cg * rp_cg) * 60.0);
    rp_speck = rp_speck * step(0.72, rp_ch);
    float rp_twk = 0.5 + 0.5 * sin(rp_t * 5.0 + rp_ch * 40.0);
    rp_col = rp_col + vec3(0.8, 1.0, 1.0) * (rp_speck * rp_twk * rp_cmW * 0.9 * rp_w);
    rp_col = rp_col + mix(rp_gold, rp_white, 0.5) * (rp_still * (rp_core * 1.1 + rp_inner * 0.3));
    float rp_f = sin(rp_t * 4.1 + rp_seed * 3.1);
    rp_f = rp_f * sin(rp_t * 2.3 + rp_seed * 7.7);
    float rp_flicker = 1.0 - 0.08 * rp_m * (0.5 + 0.5 * rp_f);
    float rp_boost = 1.0 + 0.5 * rp_lit;
    float rp_fadeA = 0.05 + rp_bhA * 0.5 * rp_reach;
    float rp_fadeB = 0.05 + rp_bhB * 0.5 * rp_reach;
    float rp_ends = smoothstep(0.0, rp_fadeA, rp_along);
    rp_ends = rp_ends * smoothstep(0.0, rp_fadeB, rp_toEnd);
    rp_col = rp_col * (rp_flicker * rp_boost * rp_ends);
    float rp_gd = (rp_toEnd - 0.12) / (0.2 * rp_reach);
    float rp_gs = rp_s0 * 1.3;
    float rp_star = exp(-(rp_gd * rp_gd + rp_gs * rp_gs) * 3.0);
    float rp_arms = exp(-rp_gd * rp_gd * 40.0) * exp(-rp_gs * rp_gs * 0.8);
    float rp_arm2 = exp(-rp_gs * rp_gs * 60.0);
    rp_arms = rp_arms + rp_arm2 * exp(-rp_gd * rp_gd * 0.6);
    float rp_glint = (rp_star + rp_arms * 0.6) * rp_arrive * rp_rkB * rp_w;
    rp_col = rp_col + vec3(0.8, 0.92, 1.0) * (rp_glint * 1.5);
    float rp_gsA = step(1.5, rp_sA) - step(2.5, rp_sA);
    float rp_gbA = (rp_along - 1.2 * rp_reach) / (0.1 * rp_reach);
    float rp_gbB = (rp_toEnd - 1.2 * rp_reach) / (0.1 * rp_reach);
    float rp_bar = exp(-rp_gbA * rp_gbA) * rp_gsA + exp(-rp_gbB * rp_gbB) * rp_gsB;
    rp_bar = rp_bar * rp_w * (0.45 + 0.4 * rp_lit + 0.9 * rp_arrive);
    rp_col = rp_col + vec3(1.0, 0.9, 0.7) * (rp_bar * 0.7);
    float rp_lA = rp_along / 0.07;
    float rp_lB = rp_toEnd / 0.07;
    float rp_touch = exp(-rp_lA * rp_lA) * (1.0 - rp_bhA);
    rp_touch = rp_touch + 0.6 * exp(-rp_lB * rp_lB) * (1.0 - rp_bhB);
    rp_touch = rp_touch * exp(-rp_s0 * rp_s0 * 5.0) * (0.9 + 0.6 * rp_lit + 0.5 * rp_arrive);
    rp_col = rp_col + mix(rp_gold, rp_white, 0.6) * rp_touch;
    float rp_capL = 0.12 * rp_reach;
    float rp_cA = 1.0 - clamp(rp_along / rp_capL, 0.0, 1.0);
    float rp_cB = 1.0 - clamp(rp_toEnd / rp_capL, 0.0, 1.0);
    float rp_cw = sqrt(max(1.0 - max(rp_cA * rp_cA, rp_cB * rp_cB), 0.0));
    float rp_cap = 1.0 - smoothstep(0.55, 1.0, rp_e / max(rp_cw, 0.001));
    float rp_dimA = smoothstep(0.1 * rp_reach, (0.9 + 1.3 * rp_smA) * rp_reach, rp_along);
    float rp_dimB = smoothstep(0.1 * rp_reach, (0.9 + 1.3 * rp_smB) * rp_reach, rp_toEnd);
    float rp_dim = mix(0.25 - 0.21 * rp_smA, 1.0, mix(rp_dimA, rp_dimA * rp_dimA, rp_smA));
    rp_dim = rp_dim * mix(0.25 - 0.21 * rp_smB, 1.0, mix(rp_dimB, rp_dimB * rp_dimB, rp_smB));
    rp_col = rp_col * rp_cap * rp_dim * rpEnergy;
    rp_col = (vec3(1.0) - exp(-rp_col * 1.3)) * 0.92;
    fragColor = vec4(rp_col, 0.0);
}
"""

    val bodyVertex: String get() = BODY_VS
    val linkVertex: String get() = LINK_VS
    val link: String get() = LINK_FS_BODY

    // The pieces, for the tests that read the physics in them (as iOS's ShaderSource tests do).
    val bhRing: String get() = BH
    val sunBody: String get() = SUN.substringBefore("vec3 sunCorona(")
    val sunCorona: String get() = SUN.substringAfter("vec3 sunCorona(")
    val rockBody: String get() = ROCK.substringBefore("vec3 moonBody(")
    val gasBody: String get() = GAS.substringBefore("vec3 gasRing(")
    val gasRing: String get() = GAS.substringAfter("vec3 gasRing(")
    val pulsarCore: String get() = PULSAR.substringBefore("vec3 pulsarGlow(")
    val pulsarGlow: String get() = PULSAR.substringAfter("vec3 pulsarGlow(").substringBefore("vec3 pulsarBeam(")
    val pulsarBeam: String get() = PULSAR.substringAfter("vec3 pulsarBeam(")
    val cometTail: String get() = COMET.substringAfter("vec3 cometTail(").substringBefore("vec3 cometDust(")

    /** Each style's fragment shader, by style code. */
    fun fragment(style: SpaceStyle): String = when (style) {
        SpaceStyle.BLACK_HOLE -> BODY_FS_HEAD + KIT + BH + BH_MAIN
        SpaceStyle.SUN -> BODY_FS_HEAD + KIT + SUN + SUN_MAIN
        SpaceStyle.ROCKY -> BODY_FS_HEAD + KIT + ROCK + HALO + ROCKY_MAIN
        SpaceStyle.GAS_GIANT -> BODY_FS_HEAD + KIT + GAS + HALO + GAS_MAIN
        SpaceStyle.PULSAR -> BODY_FS_HEAD + KIT + PULSAR + PULSAR_MAIN
        SpaceStyle.COMET -> BODY_FS_HEAD + KIT + COMET + COMET_MAIN
    }
}
