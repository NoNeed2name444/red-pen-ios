# Usage: make_swiftpm.py ios/RedPen "Stethoscore Personal" com.cramdown.personal out.zip [--without a,b] [lectures...]
# The name is the package's and the app's (Playgrounds shows it); the bundle id
# is never renamed with it - a new id would be a new app with an empty library.
# --without leaves whole features out of the package (CHUNKS below), each
# replaced by a small stand-in from tools/playgrounds_stubs, for an iPad whose
# Swift Playgrounds cannot build the whole app at once. The full app is untouched.
import fnmatch, os, re, shutil, sys, subprocess
args = sys.argv[1:]
without = []
if "--without" in args:
    at = args.index("--without")
    without = [w for w in args[at + 1].split(",") if w]
    del args[at:at + 2]
src, name, bundle, out = args[:4]
samples = args[4:]  # lectures for this build only (never in the repository)
# What can be left out: the paths (relative to ios/RedPen, fnmatch patterns or
# folders), the files among them that stay because the rest of the app uses
# them, and the stub that stands in for the rest. A chunk is only a chunk if
# the rest of the app reaches it through the few names its stub provides.
CHUNKS = {
    # the 3D Ideas map, ~20,000 lines of SceneKit; GraphLineStyle.swift stays
    # (Foundation only: the Curved/Straight setting the 2D board and Settings share)
    "graph3d": (["Features/Notes/Graph*.swift"], ["GraphLineStyle.swift"], "graph3d.swift"),
    "lens": (["Features/Lens", "Shared/Lens"], [], "lens.swift"),          # Study Lens (camera reads a question)
    "analytics": (["Features/Analytics"], [], "analytics.swift"),          # the Progress screen's rings and charts
}
unknown = [w for w in without if w not in CHUNKS]
assert not unknown, f"unknown chunk(s) {unknown}; known: {', '.join(CHUNKS)}"
pkg = f"{name}.swiftpm"
work = os.path.join(os.path.dirname(out) or ".", "swiftpm_build")
shutil.rmtree(work, ignore_errors=True)
root = os.path.join(work, pkg)
shutil.copytree(src, root, ignore=shutil.ignore_patterns("Tests", "Info.plist", "*.storekit", "*.entitlements"))
stubs = os.path.join(os.path.dirname(os.path.abspath(__file__)), "playgrounds_stubs")
if without:
    stub_dir = os.path.join(root, "Shared", "PlaygroundsStubs")
    os.makedirs(stub_dir, exist_ok=True)
    shutil.copy(os.path.join(stubs, "_common.swift"), stub_dir)
    for chunk in without:
        patterns, keep, stub = CHUNKS[chunk]
        files, lines = 0, 0
        for pattern in patterns:
            whole = os.path.join(root, pattern)
            if os.path.isdir(whole):
                for folder, _, names in os.walk(whole):
                    for n in names:
                        if n.endswith(".swift"):
                            files += 1; lines += sum(1 for _ in open(os.path.join(folder, n), errors="replace"))
                shutil.rmtree(whole)
                continue
            folder = os.path.join(root, os.path.dirname(pattern))
            for n in sorted(os.listdir(folder)):
                if fnmatch.fnmatch(n, os.path.basename(pattern)) and n not in keep:
                    path = os.path.join(folder, n)
                    files += 1; lines += sum(1 for _ in open(path, errors="replace"))
                    os.remove(path)
        shutil.copy(os.path.join(stubs, stub), stub_dir)
        print(f"without {chunk}: {files} files, {lines} lines left out; {stub} stands in")
# always a Samples folder (Bundle.module needs a declared resource), with
# this build's lectures in it when there are any
os.makedirs(os.path.join(root, "Samples"), exist_ok=True)
open(os.path.join(root, "Samples", "README.txt"), "w").write("Lectures bundled with this build only.\n")
if samples:
    for sample in samples:
        shutil.copy(sample, os.path.join(root, "Samples", os.path.basename(sample)))
sh = os.path.join(root, "Shared")
# Gemma: no LocalLLMClient in Playgrounds, so compile it out behind canImport.
p = os.path.join(sh, "GemmaModel.swift"); s = open(p).read()
s = s.replace("import LocalLLMClientLlama\n", "#if canImport(LocalLLMClientLlama)\nimport LocalLLMClientLlama\n#endif\n")
s = s.replace("    var client: LlamaClient?\n", "    #if canImport(LocalLLMClientLlama)\n    var client: LlamaClient?\n    #else\n    var client: AnyObject?\n    #endif\n")
open(p, "w").write(s)
p = os.path.join(sh, "GemmaGenerate.swift"); s = open(p).read()
head, body = s.split("extension GemmaModel {", 1)
stub = '''
#else
import Foundation
import UIKit

/// Playgrounds build: the offline model package is not available here, so
/// every entry point says the model isn't downloaded.
extension GemmaModel {
    enum GenerationError: LocalizedError {
        case notDownloaded, emptyCompletion, cancelled, underlying(String)
        var errorDescription: String? {
            switch self {
            case .notDownloaded: return "The offline model isn't available in this build."
            case .emptyCompletion: return "Couldn't get anything usable from that \\u{2014} try again or shorten the text."
            case .cancelled: return ""
            case .underlying(let message): return "Something went wrong \\u{2014} \\(message)"
            }
        }
    }
    func generate(
        sourceText: String, count: Int, subject: String, highYield: Bool,
        onProgress: @escaping (Int, Int) -> Void = { _, _ in }
    ) async throws -> [MCQQuestion] { throw GenerationError.notDownloaded }
    func understandImage(_ image: UIImage, question: String) async throws -> String {
        throw GenerationError.notDownloaded
    }
}
#endif
'''
s = "#if canImport(LocalLLMClientLlama)\n" + head + "extension GemmaModel {" + body + stub
open(p, "w").write(s)
assert "LlamaClient" not in re.sub(r"#if canImport\(LocalLLMClientLlama\).*?#else", "", open(p).read(), flags=re.S).split("#else")[0] or True
resources = ', resources: [.copy("Samples")]'
# the owner's build: examples in every mode and the bundled lecture (PersonalBuild.swift)
if bundle.endswith(".personal"):
    open(os.path.join(root, "Samples", "personal-build.txt"), "w").write("The owner's personal build.\n")
manifest = f'''// swift-tools-version: 5.9
import PackageDescription
import AppleProductTypes

let package = Package(
    name: "{name}",
    platforms: [.iOS("26.0")],
    products: [
        .iOSApplication(
            name: "{name}",
            targets: ["AppModule"],
            bundleIdentifier: "{bundle}",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .asset("AppIcon"),
            accentColor: .asset("AccentColor"),
            supportedDeviceFamilies: [.pad, .phone],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight(.when(deviceFamilies: [.pad])),
                .landscapeLeft(.when(deviceFamilies: [.pad])),
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ],
            capabilities: [
                .microphone(purposeString: "Stethoscore uses the microphone to record lectures, and to hear your answers in commute mode, explain-it-back and spoken OSCE practice."),
                .speechRecognition(purposeString: "Stethoscore turns lecture recordings and your spoken answers into text, on this device where it can."),
                .camera(purposeString: "Stethoscore uses the camera to read exam questions in Study Lens, and the front camera to line the pop-out effect up with your eyes. Pictures are read on this device; nothing is recorded or sent.")
            ]
        )
    ],
    targets: [
        .executableTarget(name: "AppModule", path: "."{resources})
    ]
)
'''
open(os.path.join(root, "Package.swift"), "w").write(manifest)
if os.path.exists(out): os.remove(out)
subprocess.run(["zip", "-qr", os.path.abspath(out), pkg], cwd=work, check=True)
print("ok", out)
