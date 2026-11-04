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
// - muscle: its fibres in bundles (fascicles) a few millimetres across,
//   each a rounded cord with a dark seam (the perimysium) between it and
//   the next, running the way the fibres run and converging where the
//   muscle narrows, finer fibres within each bundle close up; where the
//   muscle turns into tendon, white and glossy, its bundles fainter. The
//   bundles come from the build (tools/anatomy_fibres.py lays them along
//   the fibres as a stripe pattern; AnatomyStripes): the texture
//   coordinates say where a point lies across them, one bundle a unit, and
//   how far it is tendon. The cords' relief tilts the normal (a bump) across
//   the bundles, the way found from how that coordinate changes between
//   pixels.
// The pattern is fixed to the body: it comes from the point's place in the
// body's own frame (scn_node's inverse model-view), not from texture
// coordinates, so it runs on unbroken where two pieces of a bone meet and
// does not swim as the body turns. Detail finer than a couple of pixels
// fades out instead of shimmering. The noise is GraphShaderKit's lattice
// noise, exact at any distance from the origin.
//
// Arguments: rpProbe (0; the shaders suite wants every surface modifier's
// diffuse to carry it), rpDetail (the Graphics budget's shaderDetail: 0
// leaves out the fine grain), and for muscle rpBundle (the bundles' width in
// metres, AnatomyStripes.bundle; under 1.5 mm reads as 1.5) and rpTendon
// (tendon's linear colour over muscle's, per channel). Muscle reads its
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
        rp_ax = rp_ax - round(rp_ax);
        rp_ay = rp_ay - round(rp_ay);
        float3 rp_cx = cross(rp_dpy, rp_n);
        float3 rp_cy = cross(rp_n, rp_dpx);
        float rp_det = dot(rp_dpx, rp_cx);
        float3 rp_g = abs(rp_det) > 1e-14 ? (rp_cx * rp_ax + rp_cy * rp_ay) / rp_det : float3(0.0);
        float3 rp_gw = rp_g * rp_w;
        float rp_gl = length(rp_gw);
        // bundles where they are over a few pixels wide and the coordinate runs; fainter in tendon
        float rp_k = rp_open * (1.0 - smoothstep(0.15 * rp_w, 0.45 * rp_w, rp_px)) * smoothstep(0.15, 0.35, rp_gl);
        rp_gw = rp_gl > 2.5 ? rp_gw * (2.5 / rp_gl) : rp_gw;
        float rp_kb = rp_k * (1.0 - 0.65 * rp_tendon);
        // how deep the seams run, in patches a few centimetres across: here the bundles stand
        // apart, there they lie close and read as one

        """ + GraphShaderKit.lattice("rp_sd", "rp_p * 28.0 + float3(5.3, 1.1, 7.9)") + """
        float rp_depth = mix(0.35, 1.35, rp_sd);
        // the bundle a rounded cord: its height across it (0 at its seams, 1 on its crown), and its slope
        float rp_x = fract(rp_tx);
        float rp_cord = sin(3.14159265 * rp_x);
        float rp_slope = 3.14159265 * cos(3.14159265 * rp_x);
        // finer fibres within each bundle, close up and at High
        float rp_fine = rpDetail * rp_k * (1.0 - smoothstep(0.04 * rp_w, 0.12 * rp_w, rp_px));
        float rp_fx = 31.415927 * rp_x;
        // the normal tilted by the cords' relief
        float3 rp_nb = normalize(rp_n - rp_gw * (0.14 * rp_kb * rp_depth * rp_slope + 0.035 * rp_fine * cos(rp_fx)));
        _surface.normal = normalize((scn_node.modelViewTransform * float4(rp_nb, 0.0)).xyz);
        // each bundle a little unlike its neighbours (the same bundle on either side of a
        // place where the pattern's pieces meet mirrored: n and -1 - n)
        int rp_b = int(floor(rp_tx));
        rp_b = rp_b < 0 ? -1 - rp_b : rp_b;
        uint rp_h = uint(rp_b + 4096) * 0x8da6b343u;
        rp_h = (rp_h ^ (rp_h >> 16)) * 0x7feb352du;
        rp_h = (rp_h ^ (rp_h >> 15)) * 0x846ca68bu;
        rp_h = rp_h ^ (rp_h >> 16);
        float rp_tint = float(rp_h >> 8) * (1.0 / 16777216.0);
        // and a broad faint variation

        """ + GraphShaderKit.latticeFbm("rp_m", "rp_p * 20.0", octaves: "2") + """
        // the seams between bundles darker
        float rp_shade = mix(1.0, mix(1.0 - 0.4 * rp_depth, 1.0, sqrt(rp_cord)) * (1.0 + 0.14 * (rp_tint - 0.5)), rp_kb);
        rp_shade = rp_shade * (1.0 + 0.06 * rp_fine * sin(rp_fx)) * (1.0 + 0.1 * (rp_m - 0.5));
        float3 rp_colour = _surface.diffuse.rgb * mix(float3(1.0), rpTendon, rp_tendon);
        _surface.diffuse = float4(rp_colour * rp_shade + float3(rpProbe), _surface.diffuse.a);
        // the fascia over the bundles' crowns, and tendon, catch the light more
        _surface.roughness = clamp(_surface.roughness - 0.1 * rp_kb * (rp_cord - 0.5) - 0.25 * rp_tendon, 0.15, 1.0);
        """
}
