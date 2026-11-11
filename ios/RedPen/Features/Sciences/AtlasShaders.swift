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
// - muscle: its fibres in fine rounded cords, each with a dark seam
//   between it and the next, running the way the fibres run and
//   converging where the muscle narrows; where the muscle turns into
//   tendon, white with a soft sheen, its cords nearly gone (a tendon shows
//   fine lines, not the ridged cords of a belly, and a sharp gloss on it
//   reads as plastic). The bundles (fascicles),
//   a few millimetres across, come from the build (tools/anatomy_fibres.py
//   lays them along the fibres as a stripe pattern; AnatomyStripes): the
//   texture coordinates say where a point lies across them, one bundle a
//   unit, and how far it is tendon. Each bundle splits in two, and in two
//   again, down to cords 0.35 to 0.7 mm across, and the finest split whose
//   cords lie a few pixels apart is drawn: close up the finest, further off
//   the coarser cords they make, so the cords stay fine at any distance;
//   the bundles' own seams (the perimysium) a faint line between them. Each
//   cord is averaged over the pixel's span across it, so its seams do not
//   shimmer where a pixel is shaded once (as on the phone and the tablet).
//   The cords' relief tilts the normal (a bump) across them, the way found
//   from how that coordinate changes between pixels.
// - iris: its stroma's fine radial fibres and the broader bands they make,
//   the collarette (a wavering crest about a third of the way out, the
//   pupillary zone inside it a little lighter and warmer), crypts (dark
//   pits just outside it), darker toward its root, as the limbal ring is
//   seen, and the pigment of the pupil's rim (the ruff) dark: drawn about
//   the iris's own middle and axis (AnatomyMesh.ringFrame), so a flat
//   brown disc reads as an iris.
// The pattern is fixed to the body: it comes from the point's place in the
// body's own frame (scn_node's inverse model-view), not from texture
// coordinates, so it runs on unbroken where two pieces of a bone meet and
// does not swim as the body turns. Detail finer than a couple of pixels
// fades out instead of shimmering. The noise is GraphShaderKit's lattice
// noise, exact at any distance from the origin.
//
// Arguments: rpProbe (0; the shaders suite wants every surface modifier's
// diffuse to carry it), rpDetail (the Graphics budget's shaderDetail: 0
// leaves out the fine grain, and a muscle's cords go no finer than
// 1.4 mm), and for muscle rpBundle (the bundles' width in
// metres, AnatomyStripes.bundle; under 1.5 mm reads as 1.5) and rpTendon
// (tendon's linear colour over muscle's, per channel); for the iris
// rpIrisCentre and rpIrisAxis (its middle and the unit axis it is turned
// about, in the body's frame) and rpIrisRadii (the pupil's rim's and the
// root's distance off that axis, in metres; the third unused). Muscle reads its
// texture coordinates (AnatomyStripes.coordinates), so its material carries
// a texture (AnatomyAtlasView's swatch), without which SceneKit passes none; where
// they do not run (a muscle without bundles), it stays plain. Listed in
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

    /// Muscle: its fibres in bundles, white tendon at its ends.
    static let muscle: String = """
        #pragma arguments
        float rpProbe;
        float rpDetail;
        float rpBundle;
        float3 rpTendon;
        #pragma body
        float3 rp_p = (scn_node.inverseModelViewTransform * float4(_surface.position, 1.0)).xyz;
        float3 rp_n = normalize((scn_node.inverseModelViewTransform * float4(_surface.normal, 0.0)).xyz);
        float3 rp_dpx = dfdx(rp_p);
        float3 rp_dpy = dfdy(rp_p);
        float rp_px = max(length(rp_dpx), length(rp_dpy));
        float rp_w = max(rpBundle, 0.0015);
        // where the point lies across the bundles (one a unit), and tendon (-1: a fork, left plain)
        float2 rp_tc = _surface.diffuseTexcoord;
        float rp_tendon = clamp(rp_tc.y, 0.0, 1.0);
        float rp_open = rp_tc.y < -0.5 ? 0.0 : 1.0;
        // the bundles waver a little sideways, over a couple of centimetres, as real ones do

        """ + GraphShaderKit.lattice("rp_wv", "rp_p * 45.0") + """
        float rp_tx = rp_tc.x + 0.4 * (rp_wv - 0.5);
        // that coordinate's gradient on the surface, from its change between pixels (a whole bundle's
        // jump, where the pattern's pieces meet, taken off)
        float rp_ax = dfdx(rp_tx);
        float rp_ay = dfdy(rp_tx);
        // (only a change larger than the place's own could be: where bundles lie closer than a couple of
        // pixels, a true change, folded, would read as a small one)
        float rp_lim = 2.5 * rp_px / rp_w + 0.5;
        rp_ax = abs(rp_ax) > rp_lim ? rp_ax - round(rp_ax) : rp_ax;
        rp_ay = abs(rp_ay) > rp_lim ? rp_ay - round(rp_ay) : rp_ay;
        float3 rp_cx = cross(rp_dpy, rp_n);
        float3 rp_cy = cross(rp_n, rp_dpx);
        float rp_det = dot(rp_dpx, rp_cx);
        float3 rp_g = abs(rp_det) > 1e-14 ? (rp_cx * rp_ax + rp_cy * rp_ay) / rp_det : float3(0.0);
        float3 rp_gw = rp_g * rp_w;
        float rp_gl = length(rp_gw);
        // the pattern where that coordinate runs (not at a fork, nor where it barely changes); in tendon a
        // twentieth
        float rp_k = rp_open * smoothstep(0.15, 0.35, rp_gl);
        rp_gw = rp_gl > 2.5 ? rp_gw * (2.5 / rp_gl) : rp_gw;
        float rp_kb = rp_k * (1.0 - 0.95 * rp_tendon);
        // how deep the seams run, in patches a few centimetres across: here the cords stand
        // apart, there they lie close and read as one

        """ + GraphShaderKit.lattice("rp_sd", "rp_p * 28.0 + float3(5.3, 1.1, 7.9)") + """
        float rp_depth = mix(0.35, 1.35, rp_sd);
        // Each bundle splits in two, each half in two again, and so on down to cords 0.35 to 0.7 mm
        // across (1.4 to 2.8 mm without the fine detail). Drawn is the finest split whose cords lie at least
        // 4 pixels apart, the next finer fading in from 2 pixels, so a muscle shows fine cords at any
        // distance: close up its fibres, further off the cords they make, and never a stripe finer
        // than the screen can show. rp_bp: a bundle's width in pixels; rp_lf, rp_lc: the finer and
        // the coarser split drawn (0 the bundle itself), rp_wf and rp_wc their shares.
        float rp_bp = 1.0 / max(length(float2(rp_ax, rp_ay)), 1e-5);
        float rp_top = max(floor(log2(rp_w / mix(0.0014, 0.00035, rpDetail))), 0.0);
        float rp_lv = log2(rp_bp / 2.0);
        float rp_kp = floor(rp_lv);
        float rp_sp = smoothstep(1.0, 2.0, exp2(rp_lv - rp_kp));
        float rp_lf = min(rp_kp, rp_top);
        float rp_lc = clamp(rp_kp - 1.0, 0.0, rp_top);
        float rp_wf = rp_kp > rp_top ? 1.0 : (rp_kp < 0.0 ? 0.0 : rp_sp);
        float rp_wc = rp_kp > rp_top ? 0.0 : (rp_kp < 1.0 ? 0.0 : 1.0 - rp_sp);
        float rp_on = rp_wf + rp_wc;
        // and once the cords show, a faint seam between each bundle and the next (the perimysium),
        // a line a pixel or two wide
        float rp_x0 = fract(rp_tx);
        float rp_s1 = smoothstep(1.0, 2.0, exp2(rp_lv - 1.0));
        float rp_seam = rp_s1 * (1.0 - smoothstep(0.5, 1.5, min(rp_x0, 1.0 - rp_x0) * rp_bp));
        // each cord rounded, an arch sin(pi x) across it (0 at its seams, 1 on its crown): its height and
        // its slope averaged over the pixel's span across it (exactly, from the arch's integral), so a
        // seam does not flicker as the one sample a pixel falls on it or beside it; and each cord a
        // little unlike the one beside it (the same cord on either side of a place where the pattern's
        // pieces meet mirrored: n and -1 - n)
        float rp_cord = 0.0;
        float rp_slope = 0.0;
        float rp_bsl = 0.0;
        float rp_tint = 0.0;
        for (int rp_i = 0; rp_i < 3; rp_i++) {
            float rp_l = rp_i == 0 ? rp_lf : (rp_i == 1 ? rp_lc : 0.0);
            float rp_s = exp2(rp_l);
            float rp_d = max(rp_s / rp_bp, 0.001);
            float rp_a = rp_tx * rp_s - 0.5 * rp_d;
            float rp_fa = fract(rp_a);
            float rp_fb = fract(rp_a + rp_d);
            float rp_wt = rp_i == 0 ? rp_wf : (rp_i == 1 ? rp_wc : 0.0);
            rp_cord += rp_wt * (2.0 * (floor(rp_a + rp_d) - floor(rp_a)) + cos(3.14159265 * rp_fa)
                                - cos(3.14159265 * rp_fb)) / (3.14159265 * rp_d);
            // (the last, the bundles' own, only for the faint seam between them, below)
            float rp_sl = (sin(3.14159265 * rp_fb) - sin(3.14159265 * rp_fa)) / rp_d;
            rp_slope += rp_wt * rp_sl;
            rp_bsl = rp_i == 2 ? rp_sl : rp_bsl;
            int rp_b = int(floor(rp_tx * rp_s));
            rp_b = rp_b < 0 ? -1 - rp_b : rp_b;
            uint rp_h = uint(rp_b + 4096 + 65536 * (rp_i == 2 ? 31 : int(rp_l))) * 0x8da6b343u;
            rp_h = (rp_h ^ (rp_h >> 16)) * 0x7feb352du;
            rp_h = (rp_h ^ (rp_h >> 15)) * 0x846ca68bu;
            rp_h = rp_h ^ (rp_h >> 16);
            // the bundles' share steady as the view comes closer, the cords' half that
            rp_tint += (rp_i == 2 ? 1.0 : 0.5 * rp_wt) * (float(rp_h >> 8) * (1.0 / 16777216.0) - 0.5);
        }
        // the normal tilted by the cords' relief, each split's cords as deep for their width
        float3 rp_nb = normalize(rp_n - rp_gw * (0.13 * rp_kb * rp_depth * rp_slope + 0.03 * rp_kb * rp_s1 * rp_bsl));
        _surface.normal = normalize((scn_node.modelViewTransform * float4(rp_nb, 0.0)).xyz);
        // and a broad faint variation

        """ + GraphShaderKit.latticeFbm("rp_m", "rp_p * 20.0", octaves: "2") + """
        // the seams between cords darker, and between bundles a little more
        float rp_crown = sqrt(max(rp_cord, 0.0) / max(rp_on, 0.001));
        float rp_shade = mix(1.0, mix(1.0 - 0.32 * rp_depth, 1.0, rp_crown) * (1.0 + 0.08 * rp_tint), rp_kb * rp_on);
        rp_shade = rp_shade * (1.0 - 0.12 * rp_kb * rp_depth * rp_seam) * (1.0 + 0.1 * (rp_m - 0.5));
        float3 rp_colour = _surface.diffuse.rgb * mix(float3(1.0), rpTendon, rp_tendon);
        _surface.diffuse = float4(rp_colour * rp_shade + float3(rpProbe), _surface.diffuse.a);
        // the fascia over the cords' crowns, and tendon, catch the light more
        _surface.roughness = clamp(_surface.roughness - 0.1 * rp_kb * (rp_cord - 0.5 * rp_on) - 0.1 * rp_tendon, 0.15, 1.0);
        """
}
