import SwiftUI

/// What every account agrees to before it can use the app: it is a study aid
/// and nothing more - never for patient care - its AI can be wrong, no patient
/// details go in, recordings only with everyone's consent, sources only by
/// someone entitled to use them, and whoever misuses it answers for it alone.
///
/// Shown once per account, straight after signing in, and it cannot be skipped:
/// no close button, no swipe-down, and the accept button counts down for five
/// seconds before it can be pressed, so it is at least seen before it is agreed
/// to. Worded to match the terms (docs/launch/privacy-and-terms-draft.md, C3-C7,
/// C13-C14 and Part D); a change here bumps RecordingTerms.version.
struct RecordingTermsView: View {
    let onAccept: () -> Void

    /// Seconds before the button can be pressed.
    static let waitSeconds = 5

    @State private var remaining = RecordingTermsView.waitSeconds
    /// The one place the student is asked about crash and failure reports:
    /// on unless they switch it off here (or later in Settings).
    @AppStorage(Diagnostics.enabledKey) private var shareReports = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)

                Text("Read this before you start")
                    .font(.largeTitle.bold())

                warningBox

                point("person.crop.circle.badge.xmark",
                      "No patient information. Ever.",
                      "Never enter, record, upload or photograph anything that could identify a real patient: names, dates, record numbers, images or rare details.")
                point("person.2.wave.2",
                      "Record people only with their consent",
                      "Recording someone without their permission can be illegal. Only record, upload or transcribe a lecture, talk or conversation when the lecturer and everyone who can be heard have agreed, and your university's rules and the law allow it. You alone are responsible for your recordings and their transcripts.")
                point("doc.badge.ellipsis",
                      "Only add sources you have the right to use",
                      "Your own notes, material your university gave you to study from, or content whose licence allows it. Never upload other people's paid courses, question banks or copyrighted books.")
                point("hand.raised.fill",
                      "Misuse ends your account",
                      "Using \(Brand.name) for patient care, recording people without consent, uploading material you have no right to, or breaking the law can get your account suspended or closed. You are solely responsible for how you use the app; \(Brand.name) has no part in, and does not approve of, any misuse.")
                point("building.columns",
                      "No warranty, no liability",
                      "\(Brand.name) is provided as is, with no promise that anything in it is accurate or complete. To the extent the law allows, \(Brand.name) and its makers accept no liability for any decision, harm or loss that comes from relying on it.")
                point("cloud",
                      "Cloud transcription",
                      "When you choose cloud transcription, the audio is sent to Google (Gemini) to be transcribed. Choose \u{201C}This phone only\u{201D} to keep it on your device.")

                Toggle(isOn: $shareReports) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Share crash and failure reports")
                            .font(.subheadline.weight(.semibold))
                        Text("When something breaks, \(Brand.name) sends what went wrong and the phone model to be fixed \u{2014} never your notes, questions, recordings, name or email. You can change this any time in Settings.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("shareCrashReports")

                Text("By tapping \u{201C}I understand and agree\u{201D} you confirm you have read all of this and accept full responsibility for how you use \(Brand.name).")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        // the agree button under the thumb; the terms scroll up behind it
        .safeAreaInset(edge: .bottom, spacing: 0) { agreeBar }
        .background(LibraryBackdrop())
        .interactiveDismissDisabled()
        .task {
            while remaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                withAnimation { remaining -= 1 }
            }
        }
    }

    /// The part nobody may miss: what the app is not for, and that its AI
    /// can be wrong. Red, boxed, first, and read as one element by VoiceOver.
    private var warningBox: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return VStack(alignment: .leading, spacing: 10) {
            Text("\(Brand.name) is a study aid for students. It is NOT a medical tool.")
                .font(.headline)
            Text("Never use it to diagnose, treat or prescribe for anyone, or to make any decision about a real patient's care or your own health.")
                .font(.subheadline.weight(.semibold))
            Text("AI content can be wrong, out of date or dangerous, even after it has been checked. Verify everything against current guidelines, your university's teaching and qualified clinicians before you rely on it.")
                .font(.subheadline.weight(.semibold))
            Text("In an emergency, call your local emergency number.")
                .font(.subheadline)
        }
        .foregroundStyle(.primary)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.12), in: shape)
        .overlay(shape.strokeBorder(Color.red.opacity(0.55), lineWidth: 1.5))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("medicalWarning")
    }

    /// The same floating glass slab as every other bottom bar, in the terms'
    /// own 560-point column, so the terms scroll up behind glass rather than
    /// showing round a bare button.
    private var agreeBar: some View {
        StudyActionBar { agreeButton }
            .frame(maxWidth: 584)
            .frame(maxWidth: .infinity)
    }

    /// Flat on the slab and grey while it counts down; the moment it can be
    /// pressed it rises out of the slab as the one thing to do here, and sinks
    /// under the finger. (The screen's big button, like every study screen's:
    /// a glass button on the glass slab would be glass on glass.)
    private var agreeButton: some View {
        let waiting: Bool = remaining > 0
        let title: String = waiting ? "\(remaining)" : "I understand and agree"
        let spoken: String = waiting ? "Agree, available in \(remaining) seconds" : "I understand and agree"
        return Button {
            guard remaining == 0 else { return }
            onAccept()
        } label: {
            Text(title)
                .font(.headline.monospacedDigit())
                .contentTransition(.numericText(countsDown: true))
        }
        .buttonStyle(.bigPrimary)
        .animation(.snappy, value: remaining == 0)
        .keyboardShortcut(.defaultAction)
        .disabled(remaining > 0)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier("acceptRecordingTerms")
    }

    private func point(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(StudySetKind.narrate.tint)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Which accounts on this device have agreed, observed like the app's other
/// stores so the terms screen goes away the moment the button is pressed.
/// (A plain @State set on the App struct did not reliably redraw in Swift
/// Playgrounds, which left the button looking dead.)
@MainActor
final class RecordingTermsStore: ObservableObject {
    @Published private(set) var agreed: Set<String> = []

    func hasAgreed(_ accountId: String) -> Bool {
        agreed.contains(accountId) || RecordingTerms.accepted(by: accountId)
    }

    func agree(_ accountId: String) {
        RecordingTerms.accept(for: accountId)
        withAnimation { _ = agreed.insert(accountId) }
    }
}

/// Which accounts on this device have agreed to the recording terms.
///
/// Kept per account id, so a second person signing in on the same iPad sees
/// it too. The version is in the key: changing the terms means bumping it,
/// and everybody is asked again. (3: study aid only, no patient details,
/// misuse, no warranty.)
enum RecordingTerms {
    static let version = 3

    static func key(for accountId: String) -> String {
        key(for: accountId, version: version)
    }

    /// Any version's key: an earlier one tells FirstRun that the account was
    /// here before the terms changed.
    static func key(for accountId: String, version: Int) -> String {
        "recordingTerms.v\(version).\(accountId)"
    }

    static func accepted(by accountId: String, in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key(for: accountId))
    }

    static func accept(for accountId: String, in defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: key(for: accountId))
        // on disk now, not whenever the system gets round to it: if the app
        // is stopped a moment later, the terms must not come back
        defaults.synchronize()
    }
}
