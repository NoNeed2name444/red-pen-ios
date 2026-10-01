// Standalone feasibility probe: can Apple's on-device Speech framework get
// authorized and actually run inside a headless GitHub Actions macOS
// runner, with no logged-in user to click an Allow prompt? Nothing here is
// part of the Red Pen app — it's thrown away after the CI job reports back.
//
// It synthesizes its own test phrase with `say` (so no user audio needs to
// leave the chat session — that's a separate, much bigger cost problem),
// then asks SFSpeechRecognizer for on-device recognition on it.
import Foundation
import Speech

func log(_ s: String) {
    print(s)
    fflush(stdout)
}

log("=== Speech CI feasibility probe ===")
log("Process is interactive session? SessionInfo unavailable in CLI, continuing anyway.")

let authStatus = SFSpeechRecognizer.authorizationStatus()
log("Initial authorizationStatus(): \(authStatus.rawValue) (0=notDetermined,1=denied,2=restricted,3=authorized)")

let group = DispatchGroup()
group.enter()
var grantedStatus: SFSpeechRecognizerAuthorizationStatus = authStatus
SFSpeechRecognizer.requestAuthorization { status in
    grantedStatus = status
    log("requestAuthorization() callback fired with status: \(status.rawValue)")
    group.leave()
}
let waitResult = group.wait(timeout: .now() + 30)
if waitResult == .timedOut {
    log("RESULT: requestAuthorization() never called back within 30s (no TCC session to answer it).")
    exit(2)
}

guard grantedStatus == .authorized else {
    log("RESULT: speech recognition authorization DENIED/RESTRICTED in this headless runner (status \(grantedStatus.rawValue)).")
    exit(1)
}

log("Authorization granted — proceeding to synthesize + recognize a test phrase.")

guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else {
    log("RESULT: could not construct SFSpeechRecognizer for en-US at all.")
    exit(3)
}
log("recognizer.isAvailable: \(recognizer.isAvailable)")
log("recognizer.supportsOnDeviceRecognition: \(recognizer.supportsOnDeviceRecognition)")

let workDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let aiffURL = workDir.appendingPathComponent("speech_test.aiff")
let phrase = "The patient has systemic lupus erythematosus with a malar rash."

let sayProc = Process()
sayProc.executableURL = URL(fileURLWithPath: "/usr/bin/say")
sayProc.arguments = ["-o", aiffURL.path, phrase]
do {
    try sayProc.run()
    sayProc.waitUntilExit()
    log("say exit status: \(sayProc.terminationStatus)")
} catch {
    log("RESULT: failed to run /usr/bin/say: \(error)")
    exit(4)
}

guard FileManager.default.fileExists(atPath: aiffURL.path) else {
    log("RESULT: say did not produce an audio file.")
    exit(5)
}

let request = SFSpeechURLRecognitionRequest(url: aiffURL)
request.requiresOnDeviceRecognition = true
request.shouldReportPartialResults = false

let recGroup = DispatchGroup()
recGroup.enter()
var finalText: String?
var finalError: Error?
let task = recognizer.recognitionTask(with: request) { result, error in
    if let error {
        finalError = error
    }
    if let result, result.isFinal {
        finalText = result.bestTranscription.formattedString
    }
    if error != nil || (result?.isFinal ?? false) {
        recGroup.leave()
    }
}
_ = task
let recWait = recGroup.wait(timeout: .now() + 30)
if recWait == .timedOut {
    log("RESULT: on-device recognition task never completed within 30s.")
    exit(6)
}

if let finalError {
    log("RESULT: recognition failed with error: \(finalError.localizedDescription)")
    exit(7)
}

log("Expected phrase: \(phrase)")
log("Recognized text: \(finalText ?? "(nil)")")
log("RESULT: SUCCESS — on-device Speech recognition worked headlessly in CI.")
exit(0)
