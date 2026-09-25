import Foundation

/// Which exam the student is preparing for: one primary, and optionally a
/// second (sitting PLAB after Step 1, NEET-PG and INI-CET in the same
/// season). Everything that puts an exam first reads `ExamChoice.current`.
///
/// The older setting, ExamTrack (Settings → Your exam), still decides units,
/// guidelines and OSCE style; choosing an exam here moves it to the exam's
/// family, and changing it in Settings to a different family lets go of the
/// exam here (an SMLE choice is not kept under a USMLE track), falling back
/// to the track's own exam where it has one.
///
/// Foundation only, so it can be tested on Linux with a scratch UserDefaults.
enum ExamChoice {
    static let primaryKey = "exam.primary"
    static let secondaryKey = "exam.secondary"
    /// Set once the onboarding question has been answered or skipped.
    static let askedKey = "exam.asked"
    /// What the accuracy engine reads (AccuracyModel.examStrictness), kept
    /// as plain values so the engine needs nothing from here.
    static let strictnessKey = "exam.accuracyStrictness"
    static let strictnessFamilyKey = "exam.accuracyFamily"

    /// The exam picked, whatever the track says now.
    static func picked(_ defaults: UserDefaults = .standard) -> TargetExam? {
        ExamCatalog.exam(defaults.string(forKey: primaryKey))
    }

    static func pickedSecondary(_ defaults: UserDefaults = .standard) -> TargetExam? {
        ExamCatalog.exam(defaults.string(forKey: secondaryKey))
    }

    /// The exam the app puts first under this track: the one picked, when it
    /// belongs to the track; otherwise the track's own exam, where it has
    /// exactly one; otherwise none (general revision, or a USMLE track that
    /// could be any Step).
    static func effective(for track: ExamTrack, defaults: UserDefaults = .standard) -> TargetExam? {
        if let exam = picked(defaults), exam.family == track { return exam }
        return fallback(for: track)
    }

    static func fallback(for track: ExamTrack) -> TargetExam? {
        switch track {
        case .plab: return ExamCatalog.plab1
        case .mrcp: return ExamCatalog.mrcp1
        case .mrcs: return ExamCatalog.mrcsA
        case .usmle, .general: return nil
        }
    }

    /// The second exam, only alongside a primary and never the same one.
    static func secondary(for track: ExamTrack, defaults: UserDefaults = .standard) -> TargetExam? {
        guard let primary = effective(for: track, defaults: defaults),
              let second = pickedSecondary(defaults), second.id != primary.id else { return nil }
        return second
    }

    static var current: TargetExam? {
        effective(for: currentTrack(.standard))
    }

    static var currentSecondary: TargetExam? {
        secondary(for: currentTrack(.standard))
    }

    /// ExamTrack.current, read from the given defaults.
    static func currentTrack(_ defaults: UserDefaults) -> ExamTrack {
        ExamTrack(rawValue: defaults.string(forKey: ExamTrack.storageKey) ?? "") ?? .general
    }

    /// Whether the onboarding question has been dealt with.
    static func hasAsked(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: askedKey)
    }

    static func markAsked(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: askedKey)
    }

    /// Chooses the exams: the track follows the primary, and the accuracy
    /// engine is told how strict to be. Nil clears the choice (back to
    /// general revision only if the track was the exam's own).
    static func choose(primary: TargetExam?, secondary: TargetExam?, defaults: UserDefaults = .standard) {
        markAsked(defaults)
        guard let primary else {
            defaults.removeObject(forKey: primaryKey)
            defaults.removeObject(forKey: secondaryKey)
            defaults.removeObject(forKey: strictnessKey)
            defaults.removeObject(forKey: strictnessFamilyKey)
            return
        }
        defaults.set(primary.id, forKey: primaryKey)
        if let secondary, secondary.id != primary.id {
            defaults.set(secondary.id, forKey: secondaryKey)
        } else {
            defaults.removeObject(forKey: secondaryKey)
        }
        defaults.set(primary.family.rawValue, forKey: ExamTrack.storageKey)
        defaults.set(primary.accuracyStrictness, forKey: strictnessKey)
        defaults.set(primary.family.rawValue, forKey: strictnessFamilyKey)
    }
}
