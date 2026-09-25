import Foundation

/// The lecture files New set is reading, so closing it stops them.
///
/// Reading a scanned 400-page PDF is minutes of OCR on three or four cores, and
/// the diagram scan after it is as long again. Both used to run in tasks that
/// nothing kept hold of: closing New set left them rendering and reading pages
/// unseen until they finished, then writing into a screen that was gone. The
/// sections that start a read live inside New set and keep no lifetime of
/// their own that SwiftUI reports reliably, so they register here and New
/// set's own onDisappear cancels the lot. The readers underneath -
/// SourceIngest and OfficeIngest - check for cancellation between pages and
/// between pictures, so a cancel really stops the work.
@MainActor
enum FileReads {
    private static var running: [UUID: Task<Void, Never>] = [:]

    /// Starts `work` on the main actor and keeps hold of it until it ends.
    /// The awaited readers are not main-actor code, so they run off it.
    @discardableResult
    static func run(_ work: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let id = UUID()
        let task = Task { @MainActor in
            await work()
            running[id] = nil
        }
        running[id] = task
        return task
    }

    /// Everything still reading - New set is closing.
    static func cancelAll() {
        let stopping = running.values
        running = [:]
        stopping.forEach { $0.cancel() }
    }
}
