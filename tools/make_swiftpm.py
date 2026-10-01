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
# them, and the stand-ins (files or folders under tools/playgrounds_stubs) that
# take their place. A chunk is only a chunk if the rest of the app reaches it
# through the names its stand-ins provide.
#
# "core" is the build for an iPad whose Swift Playgrounds cannot compile the
# whole app: about a third of the lines, keeping the library, the study modes
# (questions, cards, textbook, cases, OSCE), sources, generation and the
# accuracy engine, sign-in and the exam; with its own small library shell
# (playgrounds_stubs/core). Everything else is left out and named in
# CoreLibrary's footer.
CORE_DROP = [
    # whole features
    "Features/Notes", "Persistence/NoteStore.swift",             # Ideas and the 3D map
    "Features/Lens", "Shared/Lens",                              # Study Lens
    "Features/Analytics",                                         # Progress analytics
    "Features/Voice", "Shared/Voice",                             # spoken OSCE, commute mode, explain-it-back
    "Features/Reasoning", "Shared/Reasoning",                     # clue cases, duels, scripts, how-to-reach
    "Features/Recall",                                            # draw from memory
    "Features/Narrate",                                           # audio lectures
    "Features/Coverage", "Shared/Coverage/CoverageCloudCheck.swift", "Shared/Coverage/CoverageExamples.swift",
    "Shared/Learn", "Features/Learn",                             # exam plan, exam-day kit, reminders
    "Features/Examples", "Features/Insight",                      # the examples hub, mistake diagnosis
    "Features/Mock", "Features/Exam/ExamDashboardCard.swift",
    "Shared/Exam/ExamFormats.swift",
    "Shared/Space", "Shared/AppBackdrop.swift",                   # the living sky
    "Shared/PopOut.swift", "Shared/PopOutMotion.swift", "Shared/HeadTracker.swift",
    "Shared/Diagnostics", "Features/Support/DiagnosticsSettingsView.swift",
    "Shared/Platform", "Shared/AppIntents.swift", "Shared/AppIntentsRouting.swift", "Shared/AppIntentsVisual.swift",
    "Persistence/SyncEngine.swift", "Persistence/SyncPush.swift", "Persistence/SyncState.swift",
    "Shared/SyncAPI.swift", "Shared/SyncRules.swift", "Shared/SyncMerge.swift",
    # the audio pipeline
    "Shared/CloudTranscriber.swift", "Shared/CloudTranscript.swift", "Shared/LectureTranscriber.swift",
    "Shared/NarratePlan.swift", "Shared/WordTiming.swift", "Shared/LecturePlayer.swift",
    "Shared/PronunciationStore.swift", "Shared/PronunciationLibrary.swift", "Shared/Corrections.swift",
    "Shared/OnDeviceLearning.swift", "Shared/SoundKey.swift",
    # imports and exports beyond lectures, text and spreadsheets
    "Shared/ApkgImport.swift", "Shared/Zstd.swift", "Shared/AnkiNoteText.swift", "Shared/AnkiFields.swift",
    "Shared/ApkgExporter.swift", "Shared/DeckPDF.swift", "Shared/DeckPDFBlocks.swift", "Shared/DeckPDFPages.swift",
    "Shared/PDFExporter.swift", "Shared/LibraryBackup.swift", "Shared/LibraryBackupRunner.swift", "Shared/MiniZip.swift",
    "Shared/OcclusionPhrases.swift", "Shared/OcclusionFilter.swift", "Shared/PhotoOcclusion.swift",
    "Shared/PhotoOcclusionReader.swift", "Shared/PDFOcclusion.swift", "Shared/FigureFinder.swift", "Shared/FigureGrid.swift",
    "Features/Library/PictureFromPhotoView.swift", "Features/Library/OcclusionCoverEditor.swift",
    "Features/Library/DeckExportIntents.swift", "Features/Library/DocumentScannerSheet.swift",
    "Features/Library/IncomingImport.swift",
    # sessions, stats, editors
    "Features/Library/StatsView.swift", "Shared/CustomSession.swift", "Features/Library/CustomSessionSheet.swift",
    "Shared/LibrarySearch.swift", "Features/Library/LibrarySearchResults.swift", "Features/Library/LibrarySearchModel.swift",
    "Features/Library/CardEditSheets.swift", "Features/Library/CardsEditorView.swift",
    "Features/Library/TagChips.swift", "Shared/CardTags.swift",
    # the full app's shell: the core has its own (playgrounds_stubs/core)
    "RedPenApp.swift", "Features/Library/LibraryView.swift", "Features/Library/StudyCategory.swift",
    "Features/Library/LibraryRows.swift", "Features/Library/CategoryShelves.swift", "Features/Library/CategoryPages.swift",
    "Features/Library/LibraryCategory.swift", "Features/Library/LibrarySheets.swift",
    "Features/Support/SupportCenter.swift", "Features/Support/ModelSettingsView.swift",
    "Features/Support/PlatformSettingsSection.swift", "Features/Support/LibraryDataSettingsSection.swift",
    "Features/Support/StudyReminderSettings.swift", "Features/Auth/LinkDeviceView.swift",
    "Shared/PreviewExtras.swift",
]
CORE_KEEP = ["QuizFromCards.swift", "TurnIntoPicker.swift", "NewSetDock.swift", "LibraryChrome.swift",
             "ImageSpoiler.swift", "LectureAudio.swift", "ModeConversion.swift", "SyncDocuments.swift", "AppLink.swift"]
# The add-back order (playgrounds_stubs/README.md): each step puts one part of
# CORE_DROP back into the core, as its own chunk, to find the iPad's ceiling
# one zip at a time. core1 = the core plus step 1: lecture audio, the spoken
# modes, draw from memory and the narrate screens.
STEP1_BACK = [
    "Features/Voice", "Shared/Voice", "Features/Recall", "Features/Narrate",
    "Shared/CloudTranscriber.swift", "Shared/CloudTranscript.swift", "Shared/LectureTranscriber.swift",
    "Shared/NarratePlan.swift", "Shared/WordTiming.swift", "Shared/LecturePlayer.swift",
    "Shared/PronunciationStore.swift", "Shared/PronunciationLibrary.swift", "Shared/Corrections.swift",
    "Shared/OnDeviceLearning.swift", "Shared/SoundKey.swift",
]
assert all(p in CORE_DROP for p in STEP1_BACK), "STEP1_BACK names a path the core does not drop"
CORE1_DROP = [p for p in CORE_DROP if p not in STEP1_BACK]
CHUNKS = {
    # the 3D Ideas map, ~20,000 lines of SceneKit; GraphLineStyle.swift stays
    # (Foundation only: the Curved/Straight setting the 2D board and Settings share)
    "graph3d": (["Features/Notes/Graph*.swift"], ["GraphLineStyle.swift"], ["graph3d.swift"]),
    "lens": (["Features/Lens", "Shared/Lens"], [], ["lens.swift"]),          # Study Lens (camera reads a question)
    "analytics": (["Features/Analytics"], [], ["analytics.swift"]),          # the Progress screen's rings and charts
    # the core shell (core/) plus the variant's own piece: stand-ins for the
    # step-1 parts (core-audio-out) or the ways into them (core-audio-in)
    "core": (CORE_DROP, CORE_KEEP, ["graph3d.swift", "core", "core-audio-out"]),
    "core1": (CORE1_DROP, CORE_KEEP, ["graph3d.swift", "core", "core-audio-in"]),
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
        patterns, keep, stand_ins = CHUNKS[chunk]
        files, lines = 0, 0
        for pattern in patterns:
            whole = os.path.join(root, pattern)
            if os.path.isdir(whole):
                for folder, _, names in os.walk(whole):
                    for n in names:
                        if n in keep: continue
                        path = os.path.join(folder, n)
                        if n.endswith(".swift"):
                            files += 1; lines += sum(1 for _ in open(path, errors="replace"))
                        os.remove(path)
                for folder, dirs, names in os.walk(whole, topdown=False):
                    if not dirs and not names: os.rmdir(folder)
                continue
            folder = os.path.join(root, os.path.dirname(pattern))
            for n in sorted(os.listdir(folder)):
                if fnmatch.fnmatch(n, os.path.basename(pattern)) and n not in keep:
                    path = os.path.join(folder, n)
                    files += 1; lines += sum(1 for _ in open(path, errors="replace"))
                    os.remove(path)
        for stand_in in stand_ins:
            source = os.path.join(stubs, stand_in)
            if os.path.isdir(source):
                for n in sorted(os.listdir(source)):
                    if n.endswith(".swift"): shutil.copy(os.path.join(source, n), stub_dir)
            else:
                shutil.copy(source, stub_dir)
        print(f"without {chunk}: {files} files, {lines} lines left out; {', '.join(stand_ins)} stand in")
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
