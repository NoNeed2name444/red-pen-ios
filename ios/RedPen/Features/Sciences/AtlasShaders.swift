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
// - muscle: streaks along its fibres (the fascicles, a couple of
//   millimetres across and a few centimetres long), and a broad faint
//   variation.
// The pattern is fixed to the body: it comes from the point's place in the
// body's own frame (scn_node's inverse model-view), not from texture
// coordinates, so it runs on unbroken where two pieces of a bone meet and
// does not swim as the body turns. Detail finer than a couple of pixels
// fades out instead of shimmering. The noise is GraphShaderKit's lattice
// noise, exact at any distance from the origin.
//
// Arguments: rpProbe (0; the shaders suite wants every surface modifier's
// diffuse to carry it), rpDetail (the Graphics budget's shaderDetail: 0
// leaves out the fine grain), rpFibre (muscle only: its long axis, unit
// length, in the body's frame; AnatomyMesh.longAxis()). Listed in
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

    /// Muscle: fascicles in streaks along its fibres.
    static let muscle: String = """
        #pragma arguments
        float rpProbe;
        float rpDetail;
        float3 rpFibre;
        #pragma body
        float3 rp_p = (scn_node.inverseModelViewTransform * float4(_surface.position, 1.0)).xyz;
        float rp_px = max(length(dfdx(rp_p)), length(dfdy(rp_p)));
        // the point with its place along the fibres squeezed to a tenth, so
        // the noise runs in streaks ten times as long as they are wide
        float3 rp_q = rp_p - rpFibre * (dot(rp_p, rpFibre) * 0.9);

        """ + GraphShaderKit.latticeFbm("rp_s", "rp_q * 420.0", octaves: "2") + """
        float rp_sc = clamp((rp_s - 0.5) * 2.4 + 0.5, 0.0, 1.0);
        // the fascicles fade out where they would be under two pixels wide
        float rp_k = 1.0 - smoothstep(0.0005, 0.0013, rp_px);
        // finer fibres within them, close up and at High
        float rp_fine = rpDetail * (1.0 - smoothstep(0.0002, 0.0005, rp_px));

        """ + GraphShaderKit.lattice("rp_t", "rp_q * 1500.0") + GraphShaderKit.latticeFbm("rp_m", "rp_p * 20.0", octaves: "2") + """
        float rp_shade = 1.0 + 0.24 * rp_k * (rp_sc - 0.5) + 0.08 * rp_fine * (rp_t - 0.5) + 0.12 * (rp_m - 0.5);
        _surface.diffuse = float4(_surface.diffuse.rgb * rp_shade + float3(rpProbe), _surface.diffuse.a);
        // the fascia over the fascicles catches the light a little more
        _surface.roughness = clamp(_surface.roughness - 0.12 * rp_k * (rp_sc - 0.5), 0.15, 1.0);
        """
}
