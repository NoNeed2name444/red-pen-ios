import SwiftUI

// Only in the Playgrounds builds that still use the small shell
// (make_swiftpm.py --without core, core1 or core2). core3 brings the real
// shell back, and these names with it, so this file is not copied there.

// MARK: - Sync (Persistence/SyncEngine): the personal build skips it

final class SyncEngine: ObservableObject {
    enum Status: Equatable {
        case idle
        case syncing
        case offline
        case failed(String)
        case needsPro
        case needsLibraryChoice
    }

    @Published private(set) var status: Status = .idle
    @Published var copiesKept = 0
    @Published var lastSyncedAt: Date? = nil

    var setsKeptHere: Int { 0 }

    func syncNow() async {}
    func chooseLibrary(addToAccount: Bool) async {}
    func addKeptSets() async {}
    func forgetEverythingSynced(libraryNowBelongsTo owner: String? = nil) {}
}

// MARK: - Screens the small shell leaves out

struct LinkDeviceView: View {
    var joinOnly: Bool = false

    var body: some View { NotInThisBuild(feature: "Linking another device") }
}

struct ModelSettingsView: View {
    var body: some View { NotInThisBuild(feature: "Model settings") }
}

extension View {
    /// Guess-first on a textbook (Features/Learn): nothing in the small shell.
    func guessFirst(_ set: StudySet) -> some View { self }
}

extension Store {
    /// The picks for these questions, in this order (Shared/Learn/LearnStore.swift).
    func picks(ids: [UUID]) -> [QuestionPick] {
        let wanted = Set(ids)
        let found = mcqPicks { wanted.contains($0.question.id) }
        let byID = Dictionary(found.map { ($0.question.id, $0) }, uniquingKeysWith: { a, _ in a })
        return ids.compactMap { byID[$0] }
    }
}

/// The words the notifications carry for the study Focus filter
/// (Shared/Learn/WardRoundClock.swift).
enum StudyFocus {
    static let criteria = "study"
    static let other = "other"
}
