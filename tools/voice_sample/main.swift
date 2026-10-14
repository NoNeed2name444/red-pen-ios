// Reads tools/voice_sample/lines.json in the phone's own voice, each line in
// its tone (VoiceTone), the way VoiceSpeaker does on the phone: the same
// voice choice, the same rate, pitch and pauses. One CAF a line, and a
// manifest of the pauses around each, for voice_sample.py to put together.
//
//   swiftc ios/RedPen/Shared/Voice/VoiceTone.swift tools/voice_sample/main.swift -o render
//   ./render tools/voice_sample/lines.json out/
import AVFoundation
import Foundation

struct Line: Decodable { let text: String; let tone: String; let role: String }

let args = CommandLine.arguments
let lines = try JSONDecoder().decode([Line].self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
let out = URL(fileURLWithPath: args[2])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

// VoiceSpeaker.voices, as on a phone set to British English
let languages = ["en-GB", "en-US"]
func usable(_ v: AVSpeechSynthesisVoice) -> Bool {
    !v.voiceTraits.contains(.isNoveltyVoice) && !v.voiceTraits.contains(.isPersonalVoice)
        && !v.identifier.lowercased().contains("eloquence")
}
func score(_ v: AVSpeechSynthesisVoice) -> Int {
    let quality: Int
    switch v.quality {
    case .premium: quality = 3
    case .enhanced: quality = 2
    default: quality = 1
    }
    let place = languages.firstIndex(of: v.language) ?? languages.count
    return quality * 10 + (languages.count - place)
}
let installed = AVSpeechSynthesisVoice.speechVoices()
    .filter { languages.contains($0.language) && usable($0) }
    .sorted { score($0) > score($1) }
guard let narrator = installed.first else { fatalError("no English voice installed") }
let others = installed.filter { $0.identifier != narrator.identifier }
let patient = others.first { $0.gender != narrator.gender && $0.gender != .unspecified } ?? others.first ?? narrator
print("narrator: \(narrator.name) (\(narrator.language), quality \(narrator.quality.rawValue))")
print("patient:  \(patient.name) (\(patient.language), quality \(patient.quality.rawValue))")

let synthesizer = AVSpeechSynthesizer()
var manifest = ""
for (index, line) in lines.enumerated() {
    let tone = VoiceTone(rawValue: line.tone) ?? .plain
    let isPatient = line.role == "patient"
    let utterance = AVSpeechUtterance(string: line.text)
    utterance.voice = isPatient ? patient : narrator
    utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate,
                         max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * tone.pace))
    var pitch = tone.pitch
    if isPatient && patient.identifier == narrator.identifier { pitch *= 0.9 }
    utterance.pitchMultiplier = pitch

    let name = String(format: "phone-%02d.caf", index)
    let url = out.appendingPathComponent(name)
    var file: AVAudioFile?
    var done = false
    var last = Date()
    synthesizer.write(utterance) { buffer in
        guard let pcm = buffer as? AVAudioPCMBuffer else { return }
        if pcm.frameLength == 0 { done = true; return }
        last = Date()
        if file == nil {
            file = try? AVAudioFile(forWriting: url, settings: pcm.format.settings,
                                    commonFormat: pcm.format.commonFormat, interleaved: pcm.format.isInterleaved)
        }
        try? file?.write(from: pcm)
    }
    // the last, empty buffer ends a line; a quiet spell ends it too, in case
    // that buffer never comes
    let started = Date()
    while !done && Date().timeIntervalSince(started) < 60
            && !(file != nil && Date().timeIntervalSince(last) > 3) {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    file = nil
    manifest += "\(name)\t\(tone.before)\t\(tone.after)\n"
    print("\(name): \(tone.rawValue)")
}
try manifest.write(to: out.appendingPathComponent("phone.tsv"), atomically: true, encoding: .utf8)
