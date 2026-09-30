import Foundation
import Observation

/// What a cloud request is for, so the consent sheet (P2.9) can say what
/// leaves the phone and the answer can be kept per purpose if it ever needs
/// to be.
enum CloudPurpose: String, CaseIterable, Sendable {
    /// Writing questions, cards or cases on the worker (Vignette Cloud).
    case generate
    /// Checking an answer or a generated item for accuracy on the worker.
    case check
    /// A whole generation job handed to the worker (CloudJobs).
    case jobs
    /// Lecture audio sent for transcription.
    case transcribe
    /// A line of text turned into speech.
    case voice
    /// The exam-coverage check.
    case coverage
    /// A provider the student added themselves, with their own key.
    case ownProvider
}

/// Declining the consent sheet: the caller shows it as a failed request.
enum CloudConsentError: LocalizedError, Equatable {
    case declined

    var errorDescription: String? {
        "Cloud AI is off. Turn it on in Settings, or use the on-device model."
    }
}

/// The one door every cloud request goes through first
/// (`try await CloudGate.shared.ensureConsent(for:)`).
///
/// W0 stub: it lets every request through at once and never shows anything,
/// so nothing new appears at launch or on first use. P2.9 fills it: the first
/// cloud request waits for the root consent sheet, which names the providers
/// and can be declined; the sheet never appears at launch.
@MainActor
@Observable
final class CloudGate {
    static let shared = CloudGate()
    /// Flipped by P2.9 once the consent sheet is in.
    static let isAvailable = false

    init() {}

    /// Returns when the request may go ahead; throws
    /// `CloudConsentError.declined` when the student keeps everything on the
    /// device.
    func ensureConsent(for purpose: CloudPurpose) async throws {
        // W0: nothing to ask yet
    }
}
