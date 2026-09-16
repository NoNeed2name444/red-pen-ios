import Foundation

/// One OSCE station's checklist — a title plus the ordered steps an
/// examiner would tick off. Mirrors the checklist objects the web app
/// builds from a mark sheet (`state.osceChecklists`), just without the
/// PDF/vision generation step: here a set is authored as plain text.
struct OsceChecklist: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var steps: [String]
}
