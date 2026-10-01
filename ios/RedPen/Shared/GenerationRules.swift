import Foundation

/// Whether a new generation may start while another is running.
///
/// Pure, and apart from GenerationCenter, because the answer decides whether
/// paid work survives. Starting a generation used to cancel the one running,
/// and a cancelled cloud job is deleted on the server along with what it had
/// written (audit #94).
///
/// The new one is refused, not queued. A queued generation would outlive the
/// screen that asked for it: one written on this device has nowhere to land
/// once New set is closed, so a queue could lose the second request without
/// a word. A refusal loses nothing. The running job carries on, the new
/// request's lecture and settings stay on its screen, and the student is told
/// what is running and how to stop it.
enum GenerationRules {

    enum Admission: Equatable {
        case start
        /// Something else is being written; the words say what, and how to stop it.
        case refuse(String)
    }

    /// `running`: the title of the generation on the card now ("Writing 40
    /// questions"), or nil when there is none.
    static func admit(running: String?) -> Admission {
        guard let running else { return .start }
        let title = running.trimmingCharacters(in: .whitespacesAndNewlines)
        let what: String
        if title.hasPrefix("Writing "), title.count > "Writing ".count {
            what = "Still writing " + title.dropFirst("Writing ".count)
        } else if title.isEmpty {
            what = "Something else is being written"
        } else {
            what = "Still busy: " + title.lowercased()
        }
        return .refuse(what + " \u{2014} wait for it to finish, or tap Cancel on its card, then try again.")
    }

    /// Whether closing a screen stops the generation running: only when
    /// that screen started it. `running`: the screen that started the
    /// running generation (nil for none, or one started outside any such
    /// screen); `closing`: the screen being closed. A New set that started
    /// nothing - its Make was refused, or it is in another window - used to
    /// stop whatever ran, and a cloud job's work with it.
    static func closingStops(running: UUID?, closing: UUID) -> Bool {
        running == closing
    }
}
