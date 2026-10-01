#!/usr/bin/env python3
"""Check the 3D map's SceneKit shader modifiers on Linux, before a device ever
compiles them.

SceneKit compiles a shader modifier (Metal source in a Swift string) only at
run time, on the device; one that fails draws nothing, and the probes
(GraphStyleProbe, NeuronProbe, CircuitProbe) quietly fall back to plain
looks. So a typo in a shader shows up only as a duller map. This catches it
here:

    tools/shader_check.py            every shader in GraphShaderCatalog
    tools/shader_check.py --keep     and leave the wrapped sources in build/shaders

It builds a tiny Swift program from the Foundation-only shader files that
prints every shader modifier (GraphShaderCatalog.all), wraps each body in a
stand-in for SceneKit's entry point (`_surface`, `_geometry`, `scn_node`,
`scn_frame`) over a header of Metal's vector types and functions (clang's
ext_vector types: swizzles, vector-scalar arithmetic), and compiles it with
clang++ -fsyntax-only. Metal spellings are rewritten on the way: float3(...)
constructors become calls, and decimal literals are floats as they are in
Metal. Only Metal's own functions are declared, with Metal's argument types,
so a GLSL or HLSL name (mod, lerp, vec3, inversesqrt) or a scalar where
Metal wants a vector fails here as it would on the device.

Needs swiftc and clang++ (both ship with the Swift toolchain, e.g.
/opt/swift/usr/bin). Exit status: 0 all compile, 1 something failed.
"""
import os, re, shutil, subprocess, sys, tempfile

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
NOTES = os.path.join(ROOT, "ios/RedPen/Features/Notes")
# the Foundation-only files that hold shader sources, and the catalog
SOURCES = ["GraphSpaceShaders.swift", "GraphNeuronShaders.swift", "GraphCircuitShaders.swift",
           "GraphShaderCatalog.swift"]

HEADER = r"""
#include <cmath>
typedef unsigned int uint;
typedef float float2 __attribute__((ext_vector_type(2)));
typedef float float3 __attribute__((ext_vector_type(3)));
typedef float float4 __attribute__((ext_vector_type(4)));
typedef int int2 __attribute__((ext_vector_type(2)));
typedef int int3 __attribute__((ext_vector_type(3)));
typedef int int4 __attribute__((ext_vector_type(4)));
typedef uint uint2 __attribute__((ext_vector_type(2)));
typedef uint uint3 __attribute__((ext_vector_type(3)));

inline float2 mk_float2(float a) { float2 v; v.x = a; v.y = a; return v; }
inline float2 mk_float2(float a, float b) { float2 v; v.x = a; v.y = b; return v; }
inline float2 mk_float2(int2 a) { float2 v; v.x = a.x; v.y = a.y; return v; }
inline float3 mk_float3(float a) { float3 v; v.x = a; v.y = a; v.z = a; return v; }
inline float3 mk_float3(float a, float b, float c) { float3 v; v.x = a; v.y = b; v.z = c; return v; }
inline float3 mk_float3(float2 a, float b) { float3 v; v.x = a.x; v.y = a.y; v.z = b; return v; }
inline float3 mk_float3(float a, float2 b) { float3 v; v.x = a; v.y = b.x; v.z = b.y; return v; }
inline float3 mk_float3(int3 a) { float3 v; v.x = a.x; v.y = a.y; v.z = a.z; return v; }
inline float3 mk_float3(float4 a) = delete;
inline float4 mk_float4(float a) { float4 v; v.x = a; v.y = a; v.z = a; v.w = a; return v; }
inline float4 mk_float4(float a, float b, float c, float d) { float4 v; v.x = a; v.y = b; v.z = c; v.w = d; return v; }
inline float4 mk_float4(float3 a, float b) { float4 v; v.x = a.x; v.y = a.y; v.z = a.z; v.w = b; return v; }
inline float4 mk_float4(float2 a, float2 b) { float4 v; v.x = a.x; v.y = a.y; v.z = b.x; v.w = b.y; return v; }
inline int2 mk_int2(int a, int b) { int2 v; v.x = a; v.y = b; return v; }
inline int2 mk_int2(float2 a) { int2 v; v.x = (int)a.x; v.y = (int)a.y; return v; }
inline int3 mk_int3(int a, int b, int c) { int3 v; v.x = a; v.y = b; v.z = c; return v; }
inline int3 mk_int3(float3 a) { int3 v; v.x = (int)a.x; v.y = (int)a.y; v.z = (int)a.z; return v; }
inline uint2 mk_uint2(uint a, uint b) { uint2 v; v.x = a; v.y = b; return v; }
inline uint3 mk_uint3(uint a, uint b, uint c) { uint3 v; v.x = a; v.y = b; v.z = c; return v; }
inline uint3 mk_uint3(int3 a) { uint3 v; v.x = (uint)a.x; v.y = (uint)a.y; v.z = (uint)a.z; return v; }

struct float4x4 {
    float4 c[4];
    float4 &operator[](int i) { return c[i]; }
    const float4 &operator[](int i) const { return c[i]; }
};
inline float4 operator*(const float4x4 &m, float4 v) { return m.c[0] * v.x + m.c[1] * v.y + m.c[2] * v.z + m.c[3] * v.w; }
struct float3x3 {
    float3 c[3];
    float3 &operator[](int i) { return c[i]; }
    const float3 &operator[](int i) const { return c[i]; }
};
inline float3 operator*(const float3x3 &m, float3 v) { return m.c[0] * v.x + m.c[1] * v.y + m.c[2] * v.z; }

#define RP_UNARY(name, fn) \
    inline float name(float a) { return fn(a); } \
    inline float2 name(float2 a) { return mk_float2(fn(a.x), fn(a.y)); } \
    inline float3 name(float3 a) { return mk_float3(fn(a.x), fn(a.y), fn(a.z)); } \
    inline float4 name(float4 a) { return mk_float4(fn(a.x), fn(a.y), fn(a.z), fn(a.w)); }
inline float rp_fract1(float a) { return a - std::floor(a); }
inline float rp_rsqrt1(float a) { return 1.0f / std::sqrt(a); }
inline float rp_sign1(float a) { return a > 0 ? 1.0f : (a < 0 ? -1.0f : 0.0f); }
inline float rp_sat1(float a) { return a < 0 ? 0.0f : (a > 1 ? 1.0f : a); }
RP_UNARY(sin, std::sin) RP_UNARY(cos, std::cos) RP_UNARY(tan, std::tan)
RP_UNARY(asin, std::asin) RP_UNARY(acos, std::acos) RP_UNARY(atan, std::atan)
RP_UNARY(sinh, std::sinh) RP_UNARY(cosh, std::cosh) RP_UNARY(tanh, std::tanh)
RP_UNARY(exp, std::exp) RP_UNARY(exp2, std::exp2) RP_UNARY(log, std::log) RP_UNARY(log2, std::log2)
RP_UNARY(sqrt, std::sqrt) RP_UNARY(rsqrt, rp_rsqrt1) RP_UNARY(floor, std::floor) RP_UNARY(ceil, std::ceil)
RP_UNARY(fract, rp_fract1) RP_UNARY(round, std::round) RP_UNARY(trunc, std::trunc) RP_UNARY(fabs, std::fabs)
RP_UNARY(sign, rp_sign1) RP_UNARY(saturate, rp_sat1)
inline float abs(float a) { return std::fabs(a); }
inline float2 abs(float2 a) { return mk_float2(std::fabs(a.x), std::fabs(a.y)); }
inline float3 abs(float3 a) { return mk_float3(std::fabs(a.x), std::fabs(a.y), std::fabs(a.z)); }
inline float4 abs(float4 a) { return mk_float4(std::fabs(a.x), std::fabs(a.y), std::fabs(a.z), std::fabs(a.w)); }
inline int abs(int a) { return a < 0 ? -a : a; }

#define RP_BINARY(name, fn) \
    inline float name(float a, float b) { return fn(a, b); } \
    inline float2 name(float2 a, float2 b) { return mk_float2(fn(a.x, b.x), fn(a.y, b.y)); } \
    inline float3 name(float3 a, float3 b) { return mk_float3(fn(a.x, b.x), fn(a.y, b.y), fn(a.z, b.z)); } \
    inline float4 name(float4 a, float4 b) { return mk_float4(fn(a.x, b.x), fn(a.y, b.y), fn(a.z, b.z), fn(a.w, b.w)); }
inline float rp_min1(float a, float b) { return a < b ? a : b; }
inline float rp_max1(float a, float b) { return a > b ? a : b; }
inline float rp_step1(float e, float x) { return x < e ? 0.0f : 1.0f; }
RP_BINARY(pow, std::pow) RP_BINARY(atan2, std::atan2) RP_BINARY(fmod, std::fmod)
RP_BINARY(min, rp_min1) RP_BINARY(max, rp_max1) RP_BINARY(step, rp_step1)
inline int min(int a, int b) { return a < b ? a : b; }
inline int max(int a, int b) { return a > b ? a : b; }
inline uint min(uint a, uint b) { return a < b ? a : b; }
inline uint max(uint a, uint b) { return a > b ? a : b; }

inline float clamp(float x, float a, float b) { return rp_min1(rp_max1(x, a), b); }
inline float2 clamp(float2 x, float2 a, float2 b) { return min(max(x, a), b); }
inline float3 clamp(float3 x, float3 a, float3 b) { return min(max(x, a), b); }
inline float4 clamp(float4 x, float4 a, float4 b) { return min(max(x, a), b); }
inline int clamp(int x, int a, int b) { return min(max(x, a), b); }
inline float mix(float a, float b, float t) { return a + (b - a) * t; }
inline float2 mix(float2 a, float2 b, float t) { return a + (b - a) * t; }
inline float3 mix(float3 a, float3 b, float t) { return a + (b - a) * t; }
inline float4 mix(float4 a, float4 b, float t) { return a + (b - a) * t; }
inline float2 mix(float2 a, float2 b, float2 t) { return a + (b - a) * t; }
inline float3 mix(float3 a, float3 b, float3 t) { return a + (b - a) * t; }
inline float4 mix(float4 a, float4 b, float4 t) { return a + (b - a) * t; }
inline float smoothstep(float a, float b, float x) { float t = clamp((x - a) / (b - a), 0.0f, 1.0f); return t * t * (3.0f - 2.0f * t); }
inline float2 smoothstep(float a, float b, float2 x) { return mk_float2(smoothstep(a, b, x.x), smoothstep(a, b, x.y)); }
inline float3 smoothstep(float a, float b, float3 x) { return mk_float3(smoothstep(a, b, x.x), smoothstep(a, b, x.y), smoothstep(a, b, x.z)); }
inline float dot(float2 a, float2 b) { return a.x * b.x + a.y * b.y; }
inline float dot(float3 a, float3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
inline float dot(float4 a, float4 b) { return a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w; }
inline float length(float2 a) { return std::sqrt(dot(a, a)); }
inline float length(float3 a) { return std::sqrt(dot(a, a)); }
inline float length(float4 a) { return std::sqrt(dot(a, a)); }
inline float length_squared(float2 a) { return dot(a, a); }
inline float length_squared(float3 a) { return dot(a, a); }
inline float distance(float2 a, float2 b) { return length(a - b); }
inline float distance(float3 a, float3 b) { return length(a - b); }
inline float2 normalize(float2 a) { return a / length(a); }
inline float3 normalize(float3 a) { return a / length(a); }
inline float4 normalize(float4 a) { return a / length(a); }
inline float3 cross(float3 a, float3 b) { return mk_float3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x); }
inline float3 reflect(float3 i, float3 n) { return i - n * (2.0f * dot(n, i)); }
inline float2 reflect(float2 i, float2 n) { return i - n * (2.0f * dot(n, i)); }

struct SCNShaderSurface {
    float3 view; float3 position; float3 normal; float3 geometryNormal; float3 tangent; float3 bitangent;
    float2 ambientTexcoord; float2 diffuseTexcoord; float2 specularTexcoord; float2 emissionTexcoord;
    float2 multiplyTexcoord; float2 transparentTexcoord; float2 normalTexcoord;
    float4 ambient; float4 diffuse; float4 specular; float4 emission; float4 multiply; float4 transparent;
    float4 reflective; float ambientOcclusion; float shininess; float fresnel; float metalness; float roughness;
};
struct SCNShaderGeometry {
    float4 position; float3 normal; float4 tangent; float4 color; float2 texcoords[8];
};
struct SCNNodeBuffer {
    float4x4 modelTransform; float4x4 inverseModelTransform; float4x4 modelViewTransform;
    float4x4 inverseModelViewTransform; float4x4 normalTransform; float4x4 modelViewProjectionTransform;
    float4x4 inverseModelViewProjectionTransform;
};
struct SCNFrameBuffer {
    float4x4 viewTransform; float4x4 inverseViewTransform; float4x4 projectionTransform;
    float4x4 viewProjectionTransform; float time; float sinTime; float cosTime; float random01;
};
"""

ENTRY = {
    "surface": "void rp_entry(SCNShaderSurface &_surface, const SCNNodeBuffer &scn_node, const SCNFrameBuffer &scn_frame) {\n",
    "geometry": "void rp_entry(SCNShaderGeometry &_geometry, const SCNNodeBuffer &scn_node, const SCNFrameBuffer &scn_frame) {\n",
    "fragment": "void rp_entry(float4 &_output_color, const SCNNodeBuffer &scn_node, const SCNFrameBuffer &scn_frame) {\n",
}

GLSL = re.compile(r"\b(vec[234]|mat[234]|mod|lerp|frac|inversesqrt|texture2D|atan\s*\([^,()]*,)\b")
SPLAT = re.compile(r"\b(?:float|int|uint)[234]\s+\w+\s*=\s*-?[\d.]+f?\s*;")


def dump(work):
    """Every catalogued shader: (name, entry point, source)."""
    main = os.path.join(work, "main.swift")
    open(main, "w").write(
        "import Foundation\n"
        "for item in GraphShaderCatalog.all {\n"
        "    print(\"@@@SHADER \\(item.name) \\(item.entry)\")\n"
        "    print(item.source)\n"
        "}\n"
        "print(\"@@@END\")\n")
    exe = os.path.join(work, "dump")
    swiftc = shutil.which("swiftc") or "/opt/swift/usr/bin/swiftc"
    files = [os.path.join(NOTES, f) for f in SOURCES]
    built = subprocess.run([swiftc, "-Onone", *files, main, "-o", exe], capture_output=True, text=True)
    if built.returncode != 0:
        print(built.stdout + built.stderr)
        sys.exit("the shader files did not build")
    out = subprocess.run([exe], capture_output=True, text=True, check=True).stdout
    shaders, name, entry, body = [], None, None, []
    for line in out.split("\n"):
        if line.startswith("@@@SHADER ") or line.startswith("@@@END"):
            if name:
                shaders.append((name, entry, "\n".join(body)))
            if line.startswith("@@@END"):
                break
            _, name, entry = line.split(" ", 2)
            body = []
        else:
            body.append(line)
    return shaders


def wrap(entry, source):
    """The shader as one C++ function over the header: its arguments as
    globals, its body as the entry point's. Returns (text, body's first line
    in the text, body's first line in the source)."""
    args, body, mode = [], [], "body"
    lines = source.split("\n")
    first_body = 0
    for k, line in enumerate(lines):
        s = line.strip()
        if s.startswith("#pragma arguments"):
            mode = "args"
            continue
        if s.startswith("#pragma body"):
            mode = "body"
            first_body = k + 1
            body = []
            continue
        if s.startswith("#pragma"):
            continue
        (args if mode == "args" else body).append(line)
    def metal(text):
        text = re.sub(r"\b(float|int|uint)([234])\(", r"mk_\1\2(", text)
        return re.sub(r"(?<![\w.])(\d+\.\d*(?:[eE][+-]?\d+)?|\.\d+(?:[eE][+-]?\d+)?)(?![\w.])", r"\1f", text)
    pre = HEADER + "\n".join(metal(a) for a in args) + "\n" + ENTRY[entry]
    start = pre.count("\n") + 1
    return pre + "\n".join(metal(b) for b in body) + "\n}\n", start, first_body + 1


def main():
    keep = "--keep" in sys.argv
    clang = shutil.which("clang++") or "/opt/swift/usr/bin/clang++"
    work = tempfile.mkdtemp()
    shaders = dump(work)
    if keep:
        kept = os.path.join(ROOT, "build", "shaders")
        os.makedirs(kept, exist_ok=True)
    bad = 0
    for name, entry, source in shaders:
        problems = []
        for k, line in enumerate(source.split("\n"), 1):
            code = line.split("//")[0]
            m = GLSL.search(code)
            if m:
                problems.append(f"line {k}: not Metal: {m.group(0)}")
            # clang splats a scalar into a vector; Metal wants float3(x)
            if SPLAT.search(code):
                problems.append(f"line {k}: a vector set from a bare number: {code.strip()}")
        text, start, src_start = wrap(entry, source)
        path = os.path.join(work, name + ".cpp")
        open(path, "w").write(text)
        if keep:
            shutil.copy(path, os.path.join(kept, name + ".cpp"))
        run = subprocess.run([clang, "-fsyntax-only", "-std=c++17", "-Wno-unused-variable",
                              "-Wno-unused-but-set-variable", "-ferror-limit=8", path],
                             capture_output=True, text=True)
        for l in (run.stdout + run.stderr).split("\n"):
            m = re.match(r".*\.cpp:(\d+):(\d+): (error|warning): (.*)", l)
            if m and m.group(3) == "error":
                at = int(m.group(1)) - start + src_start
                problems.append(f"line {at}: {m.group(4)}")
        if problems:
            bad += 1
            print(f"FAIL {name} ({entry})")
            for p in problems[:8]:
                print("    " + p)
        else:
            print(f"ok   {name} ({entry})")
    shutil.rmtree(work, ignore_errors=True)
    print(f"{len(shaders) - bad}/{len(shaders)} shaders compile")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
