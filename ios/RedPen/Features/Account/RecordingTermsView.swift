import SwiftUI

/// What every account agrees to before it can use the app: recordings are only
/// transcribed with the permission of the people in them, sources are only
/// added by someone entitled to use them, and the app has no part in anyone's
/// misuse of it.
///
/// Shown once per account, straight after signing in, and it cannot be skipped:
/// no close button, no swipe-down, and the accept button counts down for five
/// seconds before it can be pressed, so it is at least seen before it is agreed
/// to.
struct RecordingTermsView: View {
    let onAccept: () -> Void

    /// Seconds before the button can be pressed.
    static let waitSeconds = 5

    @State private var remaining = RecordingTermsView.waitSeconds

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "waveform.badge.exclamationmark")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(StudySetKind.narrate.tint)
                    .accessibilityHidden(true)

                Text("Before you start")
                    .font(.largeTitle.bold())

                point("person.2.wave.2",
                      "Only record and transcribe with permission",
                      "A recording holds other people's voices. Only record, upload or transcribe a lecture, talk or conversation when the lecturer and anyone else who can be heard have agreed, and when the rules of your university or country allow it.")
                point("doc.badge.ellipsis",
                      "Only add sources you own",
                      "Only add lectures, slides, notes, books and recordings that you own or have the right to use - your own notes, material your university gave you to study from, or content whose licence allows it. Do not upload other people's paid courses, question banks or copyrighted books you have no right to copy.")
                point("hand.raised",
                      "You are responsible for what you record",
                      "You are responsible for the recordings you add and what you do with their transcripts, including sharing them.")
                point("building.columns",
                      "\(Brand.name) is not part of any misuse",
                      "\(Brand.name) is a study tool. It is not associated with, and does not approve of, recording or transcribing anyone without their consent, or any other misuse of the app.")
                point("cloud",
                      "Cloud transcription",
                      "When you choose cloud transcription, the audio is sent to Google (Gemini) to be transcribed. Choose \u{201C}This phone only\u{201D} to keep it on your device.")
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
/// and everybody is asked again.
enum RecordingTerms {
    static let version = 2

    static func key(for accountId: String) -> String {
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
