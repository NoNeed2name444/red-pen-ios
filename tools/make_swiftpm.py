# Usage: make_swiftpm.py ios/RedPen "Stethoscore Personal" com.cramdown.personal out.zip [lectures...]
# The name is the package's and the app's (Playgrounds shows it); the bundle id
# is never renamed with it - a new id would be a new app with an empty library.
import os, re, shutil, sys, subprocess
src, name, bundle, out = sys.argv[1:5]
samples = sys.argv[5:]  # lectures for this build only (never in the repository)
pkg = f"{name}.swiftpm"
work = os.path.join(os.path.dirname(out) or ".", "swiftpm_build")
shutil.rmtree(work, ignore_errors=True)
root = os.path.join(work, pkg)
# the String Catalog is not copied as it is: the package gets the .lproj
# tables made from it below
shutil.copytree(src, root, ignore=shutil.ignore_patterns("Tests", "Info.plist", "*.storekit", "*.entitlements",
                                                         "*.xcstrings"))
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
# The app's strings: Swift Playgrounds cannot be counted on to compile a
# .xcstrings, so the catalog becomes Localization/<lang>.lproj/Localizable.strings
# (and .stringsdict for plurals), which every toolchain reads. They land in
# the package's resource bundle, not the app's, which is why the app reads
# them through L10n (Shared/L10n.swift) rather than Bundle.main.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import l10n_catalog
catalog_path = os.path.join(src, "Resources", "Localizable.xcstrings")
resources = ', resources: [.copy("Samples")]'
if os.path.exists(catalog_path):
    catalog = l10n_catalog.load(catalog_path)
    l10n_catalog.write_lproj(catalog, os.path.join(root, "Localization"))
    resources = ', resources: [.copy("Samples"), .process("Localization")]'
# (the catalog's folder, empty once the catalog is left out)
leftover = os.path.join(root, "Resources")
if os.path.isdir(leftover) and not os.listdir(leftover):
    os.rmdir(leftover)
# the owner's build: examples in every mode and the bundled lecture (PersonalBuild.swift)
if bundle.endswith(".personal"):
    open(os.path.join(root, "Samples", "personal-build.txt"), "w").write("The owner's personal build.\n")
manifest = f'''// swift-tools-version: 5.9
import PackageDescription
import AppleProductTypes

let package = Package(
    name: "{name}",
    defaultLocalization: "en",
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
