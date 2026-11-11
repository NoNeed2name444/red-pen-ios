import Foundation

// MARK: - The anatomy atlas's surfaces
//
// SceneKit surface modifiers (Metal source) for the atlas's physically based
// materials, so bone and muscle look like bone and muscle rather than
// painted plastic:
// - bone: a faint mottling a few centimetres across, its darker patches a
//   little warmer, and close up a fine grain a millimetre or two across,
//   in colour and in how glossy it is, kept faint so it reads as a surface
//   and not as noise;
// - muscle: flesh, not painted plastic: silky, as a fresh muscle is under
//   its fascia. Its fibres are soft streaks along the lines they truly run
//   by, of every width between 16 mm bands and quarter-millimetre lines
//   (both ends of that range fading to nothing), dense and overlapping, none with a hard edge, each paler or deeper red
//   than the next and changing slowly along its length; their relief
//   slight. The red is warm, a little paler and pinker where the belly
//   faces the eye and deeper where it turns away (a wide soft sheen in
//   place of a sharp gloss). Where the muscle turns into tendon it comes
//   in through pink to white along the fibres, further on one than on the
//   next, not across them in a line; tendon keeps the fibres as faint
//   lines. The lines come from the build (tools/anatomy_fibres.py;
//   AnatomyFibres): the texture coordinates are a point whose angle about
//   the origin is the same all along a fibre and turns once round the
//   muscle, and whose distance from it tells tendon from belly. Being a
//   point on a circle it has no seam anywhere on the muscle, and a noise
//   with a whole number of cells to a turn runs round it unbroken. The
//   fibres of a muscle that arises along a tendon slant from it (the
//   rectus femoris's leave its front tendon to both sides, as a feather's
//   barbs leave the quill). Each width is drawn by its true size on the
//   muscle, found from how the angle changes between pixels, so where the
//   fibres run together toward a tendon the fine streaks fade and coarser
//   ones take their place; nothing finer than a pixel is drawn, so it
//   does not shimmer where a pixel is shaded once (as on the phone and
//   the tablet).
// - iris: its stroma's fine radial fibres and the broader bands they make,
//   the collarette (a wavering crest about a third of the way out, the
//   pupillary zone inside it a little lighter and warmer), crypts (dark
//   pits just outside it), darker toward its root, as the limbal ring is
//   seen, and the pigment of the pupil's rim (the ruff) dark: drawn about
//   the iris's own middle and axis (AnatomyMesh.ringFrame), so a flat
//   brown disc reads as an iris.
// Bone's and the iris's patterns are fixed to the body: they come from the
// point's place in the body's own frame (scn_node's inverse model-view),
// not from texture coordinates, so they run on unbroken where two pieces of
// a bone meet and do not swim as the body turns. Muscle's fibres come from
// its texture coordinates (above), and only its slow drift along a fibre
// and its broad variation from the point's place. Detail finer than a couple of pixels
// fades out instead of shimmering. The noise is GraphShaderKit's lattice
// noise, exact at any distance from the origin.
//
// Arguments: rpProbe (0; the shaders suite wants every surface modifier's
// diffuse to carry it), rpDetail (the Graphics budget's shaderDetail: 0
// leaves out the fine grain, and a muscle's streaks go no finer than
// 1 mm), and for muscle rpTendon (tendon's linear colour over muscle's,
// per channel); for the iris
// rpIrisCentre and rpIrisAxis (its middle and the unit axis it is turned
// about, in the body's frame) and rpIrisRadii (the pupil's rim's and the
// root's distance off that axis, in metres; the third unused). Muscle reads its
// texture coordinates (AnatomyFibres.coordinates), so its material carries
// a texture (AnatomyAtlasView's swatch), without which SceneKit passes none; a
// muscle without them (both numbers 0) has no streaks, only the red and
// its sheen. Listed in
// GraphShaderCatalog, so the shaders suite and tools/shader_check.py read
// them as Metal's compiler would; tools/atlas_lab draws them on Linux.
// Foundation only.

nonisolated enum AtlasShaders {
    /// Bone: faintly mottled ivory, a fine grain close up.
    static let bone: String = """
        #pragma arguments
        float rpProbe;
        float rpDetail;
        #pragma body
        // the point in the body's own frame, in metres
        float3 rp_p = (scn_node.inverseModelViewTransform * float4(_surface.position, 1.0)).xyz;
        // how much of the body one pixel covers
        float rp_px = max(length(dfdx(rp_p)), length(dfdy(rp_p)));
        // a faint mottling a few centimetres across, its contrast a little widened

        """ + GraphShaderKit.latticeFbm("rp_m", "rp_p * 22.0", octaves: "3") + """
        float rp_mc = clamp((rp_m - 0.5) * 2.0 + 0.5, 0.0, 1.0);
        // a grain a millimetre and a half across, only where that is a few pixels
        float rp_fine = rpDetail * (1.0 - smoothstep(0.0004, 0.0009, rp_px));

        """ + GraphShaderKit.lattice("rp_g", "rp_p * 700.0") + """
        float rp_shade = 1.0 + 0.07 * (rp_mc - 0.5) + 0.035 * rp_fine * (rp_g - 0.5);
        // the darker patches a little warmer, as old ivory is
        float3 rp_tint = mix(float3(1.0, 0.965, 0.9), float3(1.0, 1.0, 1.0), rp_mc);
        _surface.diffuse = float4(_surface.diffuse.rgb * rp_tint * rp_shade + float3(rpProbe), _surface.diffuse.a);
        _surface.roughness = clamp(_surface.roughness + 0.08 * (rp_mc - 0.5) - 0.05 * rp_fine * (rp_g - 0.5), 0.2, 1.0);
        """

    /// Iris: radial fibres, the collarette and crypts, its rim and root dark.
    static let iris: String = """
        #pragma arguments
        float rpProbe;
        float rpDetail;
        float3 rpIrisCentre;
        float3 rpIrisAxis;
        float3 rpIrisRadii;
        #pragma body
        // the point in the body's own frame (metres), and its place on the iris: how far out from the pupil's
        // rim to the root (0 to 1), and its direction about the axis (as a point on a circle, so no seam)
        float3 rp_p = (scn_node.inverseModelViewTransform * float4(_surface.position, 1.0)).xyz;
        float3 rp_ax = normalize(rpIrisAxis);
        float3 rp_d = rp_p - rpIrisCentre;
        float3 rp_q = rp_d - dot(rp_d, rp_ax) * rp_ax;
        float rp_r = length(rp_q);
        float3 rp_e1 = normalize(cross(rp_ax, abs(rp_ax.y) < 0.9 ? float3(0.0, 1.0, 0.0) : float3(1.0, 0.0, 0.0)));
        float3 rp_e2 = cross(rp_ax, rp_e1);
        float2 rp_c = float2(dot(rp_q, rp_e1), dot(rp_q, rp_e2)) / max(rp_r, 0.000001);
        float rp_t = clamp((rp_r - rpIrisRadii.x) / max(rpIrisRadii.y - rpIrisRadii.x, 0.0001), 0.0, 1.0);
        // its fine fibres only where they are a few pixels across (a tenth of a millimetre or so)
        float rp_px = max(length(dfdx(rp_p)), length(dfdy(rp_p)));
        float rp_fine = 1.0 - smoothstep(0.00008, 0.0002, rp_px);
        // fibres: fast about the axis, slow along the radius, so they run outward

        """ + GraphShaderKit.latticeFbm("rp_f", "float3(rp_c * 34.0, rp_t * 3.0)", octaves: "2") + """
        float rp_fc = mix(0.5, clamp((rp_f - 0.5) * 2.2 + 0.5, 0.0, 1.0), rp_fine);
        // the broader bands the fibres gather into

        """ + GraphShaderKit.lattice("rp_b", "float3(rp_c * 9.0, rp_t * 1.5 + 4.0)") + """
        // the collarette, wavering about a third of the way out

        """ + GraphShaderKit.lattice("rp_w", "float3(rp_c * 2.5, 7.0)") + """
        float rp_col = 0.36 + 0.1 * (rp_w - 0.5);
        float rp_in = 1.0 - smoothstep(rp_col - 0.04, rp_col + 0.02, rp_t);
        float rp_crest = exp(-((rp_t - rp_col) / 0.03) * ((rp_t - rp_col) / 0.03));
        // crypts: dark pits in the ciliary zone just outside the collarette, a few, soft-edged

        """ + GraphShaderKit.latticeFbm("rp_k", "float3(rp_c * 8.0, rp_t * 5.0 + 3.0)", octaves: "2") + """
        float rp_crypt = smoothstep(0.6, 0.7, rp_k) * smoothstep(rp_col, rp_col + 0.06, rp_t)
            * (1.0 - smoothstep(0.58, 0.72, rp_t));
        // darker toward the root, and the pupil's pigmented rim
        float rp_root = smoothstep(0.82, 1.0, rp_t);
        float rp_ruff = 1.0 - smoothstep(0.0, 0.06, rp_t);
        float3 rp_tint = mix(float3(1.0), float3(1.25, 1.12, 0.85), 0.8 * rp_in)
            * mix(float3(0.93, 0.96, 1.05), float3(1.06, 1.03, 0.95), rp_fc);
        float rp_shade = (0.72 + 0.56 * rp_fc) * (1.0 + 0.25 * (rp_b - 0.5)) * (1.0 + 0.35 * rp_crest)
            * (1.0 - 0.5 * rp_crypt) * (1.0 - 0.6 * rp_root) * (1.0 - 0.7 * rp_ruff);
        _surface.diffuse = float4(_surface.diffuse.rgb * rp_tint * rp_shade + float3(rpProbe), _surface.diffuse.a);
        _surface.roughness = clamp(_surface.roughness - 0.1 * rp_crest + 0.1 * rp_crypt, 0.2, 1.0);
        """

    /// Muscle: silky flesh, its fibres soft streaks of many widths along their true lines, white tendon at its ends.
    static let muscle: String = """
        #pragma arguments
        float rpProbe;
        float rpDetail;
        float3 rpTendon;
        #pragma body
        float3 rp_p = (scn_node.inverseModelViewTransform * float4(_surface.position, 1.0)).xyz;
        float3 rp_n = normalize((scn_node.inverseModelViewTransform * float4(_surface.normal, 0.0)).xyz);
        float3 rp_dpx = dfdx(rp_p);
        float3 rp_dpy = dfdy(rp_p);
        // Where the point lies across the muscle's fibres: a point on a circle, its angle constant along a
        // fibre and turning once round the muscle (so no seam anywhere), its radius 2 less tendon's share
        // (1 all tendon, 2 all belly; nearer the middle, where the fibres run together at an end, tendon
        // too). Nothing at all (0, 0): a muscle without fibres, plain.
        float2 rp_tc = _surface.diffuseTexcoord;
        float rp_r2 = dot(rp_tc, rp_tc);
        float rp_has = rp_r2 > 0.000001 ? 1.0 : 0.0;
        float rp_tendon = rp_has * clamp(2.0 - sqrt(rp_r2), 0.0, 1.0);
        // (a muscle without fibres: the angle of (1, 0), as atan2(0, 0) is no number on some chips)
        float rp_c = fract(atan2(rp_tc.y, rp_has > 0.5 ? rp_tc.x : 1.0) / 6.2831853 + 1.0);
        // the angle's change between pixels, in turns, from the pair's own (so no jump where it wraps)
        float2 rp_tx = dfdx(rp_tc);
        float2 rp_ty = dfdy(rp_tc);
        float rp_iv = rp_has / (6.2831853 * max(rp_r2, 0.000001));
        float rp_ax = (rp_tc.x * rp_tx.y - rp_tc.y * rp_tx.x) * rp_iv;
        float rp_ay = (rp_tc.x * rp_ty.y - rp_tc.y * rp_ty.x) * rp_iv;
        // its gradient on the surface (turns a metre): across the fibres
        float3 rp_cx = cross(rp_dpy, rp_n);
        float3 rp_cy = cross(rp_n, rp_dpx);
        float rp_det = dot(rp_dpx, rp_cx);
        float3 rp_g = abs(rp_det) > 1e-14 ? (rp_cx * rp_ax + rp_cy * rp_ay) / rp_det : float3(0.0);
        float rp_gl = length(rp_g);
        float3 rp_gh = rp_g / max(rp_gl, 0.000001);
        float rp_gp = max(length(float2(rp_ax, rp_ay)), 0.0000001);
        // how a streak changes along its length: slowly, over a few centimetres

        """ + GraphShaderKit.latticeFbm("rp_tt", "rp_p * 22.0 + float3(3.1, 7.7, 1.3)", octaves: "2") + """
        // The fibres: soft streaks along them of every width between 16 mm and a quarter of a millimetre
        // (1 mm without the fine detail; the widest and the finest fade to nothing), each width's a noise across the fibres with a whole number of
        // cells to a turn (a power of two, so it runs on round the muscle unbroken), the cells' strengths
        // drifting along the fibre. A width is drawn by its true size on the muscle: as the fibres run
        // together toward a tendon the cells narrow, the fine ones fade out and coarser ones take their
        // place. A width fades out between 2.2 pixels and 1, so nothing finer than a pixel is drawn and
        // it does not shimmer.
        float rp_fine = mix(0.001, 0.00025, rpDetail);
        float rp_top = log2(0.016 / rp_fine);
        float rp_jf = log2(1.0 / (max(rp_gl, 0.01) * 0.016));
        float rp_j0 = max(ceil(rp_jf), 2.0);
        float rp_sum = 0.0;
        float rp_slope = 0.0;
        for (int rp_o = 0; rp_o < 7; rp_o++) {
            float rp_j = rp_j0 + float(rp_o);
            float rp_x = rp_j - rp_jf;
            // (the count by a shift: exp2 may come a hair short of the whole number on a chip, and the
            // mask below would lose its lowest bit)
            uint rp_n = 1u << uint(rp_j);
            float rp_cells = float(rp_n);
            float rp_wt = smoothstep(0.0, 1.0, rp_x) * (1.0 - smoothstep(rp_top - 1.0, rp_top, rp_x))
                * smoothstep(1.0, 2.2, 1.0 / (rp_cells * rp_gp));
            float rp_q = rp_c * rp_cells;
            float rp_qi = floor(rp_q);
            float rp_qf = rp_q - rp_qi;
            uint rp_mask = rp_n - 1u;
            uint rp_i0 = uint(rp_qi) & rp_mask;
            float2 rp_gv = float2(0.0);
            for (int rp_k = 0; rp_k < 2; rp_k++) {
                uint rp_h = ((rp_i0 + uint(rp_k)) & rp_mask) * 0x8da6b343u + uint(rp_j) * 0xd8163841u;
                rp_h = (rp_h ^ (rp_h >> 16)) * 0x7feb352du;
                rp_h = (rp_h ^ (rp_h >> 15)) * 0x846ca68bu;
                rp_h = rp_h ^ (rp_h >> 16);
                float rp_ph = float(rp_h & 0xffffu) * (1.0 / 65536.0);
                float rp_rt = 1.0 + float((rp_h >> 16) & 1u);
                float rp_am = 0.55 + 0.45 * float((rp_h >> 17) & 127u) * (1.0 / 127.0);
                float rp_v = rp_am * cos(6.2831853 * (rp_ph + 1.6 * rp_rt * rp_tt));
                rp_gv = rp_k == 0 ? float2(rp_v, rp_gv.y) : float2(rp_gv.x, rp_v);
            }
            float rp_s = rp_qf * rp_qf * (3.0 - 2.0 * rp_qf);
            float rp_a = rp_gv.x * rp_qf;
            float rp_b = rp_gv.y * (rp_qf - 1.0);
            // (the broad bands a little stronger than the fine lines; the slope as steep at any width,
            // so a band's relief is as deep for its width as a fine line's)
            rp_sum += rp_wt * exp2(-0.12 * rp_x) * 2.0 * (rp_a + (rp_b - rp_a) * rp_s);
            rp_slope += rp_wt * 2.0 * (rp_gv.x + (rp_gv.y - rp_gv.x) * rp_s + (rp_b - rp_a) * 6.0 * rp_qf * (1.0 - rp_qf));
        }
        // (where the angle stands still, a patch the build could give no lines, there is nothing to draw
        // streaks across: plain flesh, not the lengthwise drift alone, which would show as rings)
        float rp_live = rp_has * smoothstep(0.02, 0.1, rp_gl);
        rp_sum = rp_live * clamp(rp_sum * 0.85, -1.5, 1.5);
        rp_slope = rp_live * rp_slope;
        // tendon runs into the red along the fibres, further on one than on the next, not across them in
        // a line
        float rp_tf = smoothstep(0.12, 0.88, rp_tendon + 1.4 * rp_sum * rp_tendon * (1.0 - rp_tendon));
        // the normal tilted by the streaks' relief (slight; in tendon slighter)
        float3 rp_nb = normalize(rp_n - rp_gh * (0.016 * (1.0 - 0.6 * rp_tf) * rp_slope));
        _surface.normal = normalize((scn_node.modelViewTransform * float4(rp_nb, 0.0)).xyz);
        // and a broad faint variation, a hand's breadth of the belly a little paler or deeper

        """ + GraphShaderKit.latticeFbm("rp_m", "rp_p * 20.0", octaves: "2") + """
        // the red itself: deeper in the deep streaks, and in the pale ones part way to tendon's white
        // (pinker than it: a sheath is thin, and the red shows through)
        float3 rp_white = _surface.diffuse.rgb * rpTendon;
        float3 rp_pink = rp_white * float3(1.0, 0.6, 0.56);
        float3 rp_red = _surface.diffuse.rgb * exp(rp_sum * float3(0.3, 0.46, 0.5));
        float3 rp_lit = min(_surface.diffuse.rgb * float3(1.5, 2.2, 2.3), rp_pink);
        // the fascia's satin: where the belly faces the eye it is a little paler, and deeper where it
        // turns away, as flesh is under a lamp held by the eye (a wide soft sheen, not a gloss)
        float rp_face = clamp(dot(_surface.normal, normalize(_surface.view)), 0.0, 1.0);
        float rp_f2 = rp_face * rp_face;
        rp_red = mix(rp_red, rp_lit, 0.3 * rp_f2 * rp_f2 * rp_face) * mix(0.78, 1.0, smoothstep(0.0, 0.6, rp_face));
        // (tendon comes in through pink: its first fibres lie thin over the red; its own fibres faint lines)
        float3 rp_colour = mix(rp_red, mix(rp_pink, rp_white, rp_tf) * (1.0 + 0.07 * rp_sum), rp_tf);
        _surface.diffuse = float4(rp_colour * (1.0 + 0.12 * (rp_m - 0.5)) + float3(rpProbe), _surface.diffuse.a);
        // the sheen broken along the streaks as well (the pale sheaths glossier, the deep red duller),
        // and tendon glossier than either
        _surface.roughness = clamp(_surface.roughness - 0.07 * rp_sum - 0.12 * rp_tf, 0.2, 1.0);
        """
}
