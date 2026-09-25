import Combine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Files from outside the app
//
// "Open in Stethoscore" from Files, Mail, WhatsApp or AirDrop, a file
// dragged onto the library on an iPad, and a Spotlight or Shortcuts hand-off
// all arrive here. The router only takes a private copy of the file and works
// out what it is (ImportKind). It never changes the library: the import
// preview does that, and only when the student taps (plan rule 8).
//
// The data lane's import preview takes files with `register(_:)`. Until one
// is registered - or when it declines a file - the root's own small inbox
// sheet shows it (ImportInboxSheet below): a shared set can be added from
// there with one tap; anything else is named, with where to bring it in.

/// A file handed to the app, copied to a private place it can be read from.
struct IncomingFile: Identifiable, Equatable {
    let id: UUID
    /// The private copy (in the temporary directory), readable without any
    /// security-scoped access.
    let url: URL
    /// The name it had where it came from.
    let name: String
    let kind: ImportKind
    let byteCount: Int
}

@MainActor
final class ImportRouter: ObservableObject {
    static let shared = ImportRouter()

    /// Takes a file and returns true when it will show it (the preview is
    /// now up); false leaves it to the inbox sheet.
    typealias Handler = @MainActor (IncomingFile) -> Bool

    /// Files for the inbox sheet, when no preview took them. Sent, not
    /// kept, so with two main windows only the one in front shows it.
    let inbox = PassthroughSubject<IncomingFile, Never>()

    /// The preview that takes files now, with the token it registered under.
    private var handler: (token: UUID, take: Handler)?
    /// Files that arrived before anything could take them - a cold launch
    /// from Files lands before the library is on screen.
    private var waiting: [IncomingFile] = []

    /// How long a file waits for a preview to register before the inbox
    /// sheet shows it instead.
    static let graceSeconds: Double = 2.5

    // MARK: for the import preview

    /// The import preview (data lane) registers here while it can show a
    /// file; anything already waiting is handed over at once. Keep the
    /// token: only it can take the registration away again.
    @discardableResult
    func register(_ handler: @escaping Handler) -> UUID {
        let token = UUID()
        self.handler = (token, handler)
        let pending: [IncomingFile] = waiting
        waiting = []
        for file in pending { deliver(file) }
        return token
    }

    /// Takes a registration away - only if it is still the one registered,
    /// so a second window's library leaving never clears the first's.
    func unregister(_ token: UUID) {
        if handler?.token == token { handler = nil }
    }

    /// Shows a file in the inbox sheet (a preview that could not show it).
    func showInbox(_ file: IncomingFile) {
        inbox.send(file)
    }

    // MARK: for the app

    /// A file URL from `onOpenURL`, a drop or a document picker.
    func receive(_ url: URL) {
        guard url.isFileURL else { return }
        Task {
            guard let file = await ImportRouter.copy(url) else { return }
            accept(file)
        }
    }

    /// Everything a drop brought, in order.
    func receive(_ urls: [URL]) {
        for url in urls { receive(url) }
    }

    private func accept(_ file: IncomingFile) {
        if handler != nil {
            deliver(file)
            return
        }
        waiting.append(file)
        // give the library a moment to come up and its preview to register
        Task {
            try? await Task.sleep(nanoseconds: UInt64(ImportRouter.graceSeconds * 1_000_000_000))
            guard let index = waiting.firstIndex(where: { $0.id == file.id }) else { return }
            waiting.remove(at: index)
            deliver(file)
        }
    }

    private func deliver(_ file: IncomingFile) {
        if let handler, handler.take(file) { return }
        inbox.send(file)
    }

    /// The private copy, made off the main thread: the source may be a
    /// security-scoped file in another app's container, a file the system put
    /// in Documents/Inbox, or a drop's temporary file that is gone as soon
    /// as the drop returns.
    nonisolated static func copy(_ source: URL) async -> IncomingFile? {
        await Task.detached(priority: .userInitiated) { () -> IncomingFile? in
            let scoped: Bool = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            let manager = FileManager.default
            let id = UUID()
            let folder: URL = manager.temporaryDirectory
                .appendingPathComponent("incoming-" + id.uuidString, isDirectory: true)
            let name: String = source.lastPathComponent
            let target: URL = folder.appendingPathComponent(name)
            do {
                try manager.createDirectory(at: folder, withIntermediateDirectories: true)
                try manager.copyItem(at: source, to: target)
            } catch {
                return nil
            }
            // the system's own Inbox copy is ours to tidy once taken
            if source.path.contains("/Documents/Inbox/") { try? manager.removeItem(at: source) }
            let size: Int = (try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let head: Data = ImportRouter.head(of: target)
            var kind: ImportKind = ImportKind.of(fileName: name, head: head)
            if kind == .unknown && target.pathExtension.lowercased() == "zip" && ImportRouter.listsManifest(target) {
                // a backup whose manifest is not the first entry (re-zipped)
                kind = .backup
            }
            return IncomingFile(id: id, url: target, name: name, kind: kind, byteCount: size)
        }.value
    }

    /// Whether a zip's central directory lists the backup manifest - read
    /// memory-mapped, so a big archive is not loaded to look.
    nonisolated static func listsManifest(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return false }
        return Zip.directory(of: data).contains { $0.name == ImportKind.backupManifest }
    }

    nonisolated static func head(of url: URL) -> Data {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return Data() }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: ImportKind.headLength)) ?? Data()
    }

    /// Everything the app accepts from outside, for a drop.
    static var acceptedTypes: [UTType] {
        var types: [UTType] = [.json, .commaSeparatedText, .tabSeparatedText, .zip, .pdf, .image, .plainText]
        let extra: [String] = ["apkg", "colpkg", ImportKind.setExtension, ImportKind.backupExtension]
        for ext in extra {
            if let type = UTType(filenameExtension: ext) { types.append(type) }
        }
        return types
    }
}

// MARK: - A dropped file

/// One file dropped on the app, as a copy the router can keep.
struct DroppedFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .item) { received in
            // the dropped file only lives until this returns: keep a copy
            let folder: URL = FileManager.default.temporaryDirectory
                .appendingPathComponent("drop-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let target: URL = folder.appendingPathComponent(received.file.lastPathComponent)
            try FileManager.default.copyItem(at: received.file, to: target)
            return DroppedFile(url: target)
        }
    }
}

// MARK: - The inbox sheet (when no preview took the file)

struct ImportInboxSheet: View {
    let file: IncomingFile

    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var set: StudySet?
    @State private var reading = true
    @State private var problem: String?
    @State private var added = false
    /// A picture, taken to picture cards with this file already in.
    @State private var picturing = false
    /// A lecture, read and handed to New set.
    @State private var lecturePreset: NewSetPreset?
    @State private var readingLecture = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                header
                if reading {
                    ProgressView("Reading\u{2026}")
                        .frame(maxWidth: .infinity)
                } else if let set {
                    setSummary(set)
                } else {
                    Text(problem ?? elsewhere)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    takeItThere
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Received")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(added ? "Done" : "Not now") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(.ultraThinMaterial)
        .task { await read() }
        .sheet(isPresented: $picturing) {
            NavigationStack {
                PictureFromPhotoView(initialFiles: [file.url])
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { picturing = false }
                        }
                    }
            }
        }
        .sheet(item: $lecturePreset) { preset in NewSetView(preset: preset) }
        .accessibilityIdentifier("importInboxSheet")
    }

    /// A picture or a lecture, taken straight to where it becomes cards or
    /// questions - nothing is added until the student saves there.
    @ViewBuilder
    private var takeItThere: some View {
        switch file.kind {
        case .image:
            Button {
                picturing = true
            } label: {
                Label("Make picture cards from this", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.popTile)
            .accessibilityIdentifier("importInboxPicture")
        case .lecture:
            Button {
                Task { await openLecture() }
            } label: {
                Label(readingLecture ? "Reading the lecture\u{2026}" : "Make questions from this lecture",
                      systemImage: "doc.text.viewfinder")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.popTile)
            .disabled(readingLecture)
            .accessibilityIdentifier("importInboxLecture")
        default:
            EmptyView()
        }
    }

    /// The lecture read as New set's lecture step would, then New set opened
    /// on its last step with it in.
    private func openLecture() async {
        readingLecture = true
        defer { readingLecture = false }
        let url: URL = file.url
        let isPDF: Bool = url.pathExtension.lowercased() == "pdf"
        do {
            let document: SourceText.Document
            if isPDF {
                document = try await SourceIngest.read(pdf: url, findingFigures: false).document
            } else {
                document = try await OfficeIngest.read(url, findingFigures: false).document
            }
            let kind: SourceDoc.Kind = LecturePDFSection.kind(of: url)
            let blob: String? = await SourceFiles.keeping(url, kind: kind)
            let name: String = url.deletingPathExtension().lastPathComponent
            let source = ReadSource(name: name, document: document, kind: kind, fileBlob: blob)
            lecturePreset = NewSetPreset(lecture: source)
        } catch {
            ReviewPromptRules.noteTrouble()
            problem = "Couldn\u{2019}t read this lecture: " + error.localizedDescription
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .frame(width: 48, height: 48)
                .liquidGlassChip()
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name).font(.headline).lineLimit(2)
                Text(file.kind.label + " \u{00B7} " + sizeText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var symbol: String {
        switch file.kind {
        case .ankiDeck, .ankiCollection: return "rectangle.stack"
        case .csv, .tsv: return "tablecells"
        case .studySet: return "square.and.arrow.down"
        case .backup: return "externaldrive"
        case .lecture: return "doc.richtext"
        case .image: return "photo"
        case .text, .unknown: return "doc"
        }
    }

    private var sizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(file.byteCount), countStyle: .file)
    }

    /// Where the rest are brought in, when this sheet cannot.
    private var elsewhere: String {
        switch file.kind {
        case .ankiDeck, .ankiCollection, .csv, .tsv:
            return "Bring this in from Cards \u{203A} Paste or import, where you can see what it holds before anything is added."
        case .backup:
            return "Restore this from Settings \u{203A} Your data. Nothing on this phone is overwritten."
        case .lecture:
            return "Read it and make questions from it. Nothing is added until you make them."
        case .image:
            return "Its labels are read and covered, ready to become picture cards. Nothing is added until you save."
        case .studySet, .text, .unknown:
            return "Stethoscore cannot read this file."
        }
    }

    private func setSummary(_ set: StudySet) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(set.name).font(.title3.weight(.semibold))
            Text("\(set.kind.label) \u{00B7} \(set.itemCount) items \u{00B7} \(set.subject)")
                .foregroundStyle(.secondary)
            Button {
                add(set)
            } label: {
                Label(added ? "Added to library" : "Add to library",
                      systemImage: added ? "checkmark" : "plus")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.popTile)
            .disabled(added)
            .accessibilityIdentifier("importInboxAdd")
        }
    }

    private func read() async {
        defer { reading = false }
        guard file.kind == .studySet else { return }
        let url: URL = file.url
        let decoded: StudySet? = await Task.detached(priority: .userInitiated) { () -> StudySet? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder.redPen.decode(StudySet.self, from: data)
        }.value
        if decoded == nil { problem = "This file is not a set Stethoscore can read." }
        set = decoded
    }

    /// The same path as New set's "Import a file": new ids, no folder this
    /// library lacks, no picture that only exists on the sender's phone.
    private func add(_ incoming: StudySet) {
        let folders: Set<UUID> = Set(store.folders.map(\.id))
        let received = SetImport.received(incoming.withNewItemIDs(), folders: folders, isMissing: BlobRefs.isRef)
        store.addSet(received.set)
        added = true
    }
}

extension View {
    /// The root's end of the router: files opened from other apps or dropped
    /// on the window, and the inbox sheet for any the preview did not take -
    /// shown only in the main window in front (`scene`, AppRouter.isFront).
    func importRouting(scene: UUID) -> some View {
        modifier(ImportRouting(scene: scene))
    }
}

private struct ImportRouting: ViewModifier {
    let scene: UUID
    @State private var shown: IncomingFile?

    func body(content: Content) -> some View {
        content
            .dropDestination(for: DroppedFile.self) { files, _ in
                guard !files.isEmpty else { return false }
                ImportRouter.shared.receive(files.map(\.url))
                return true
            }
            .onReceive(ImportRouter.shared.inbox) { file in
                guard AppRouter.shared.isFront(scene) else { return }
                shown = file
            }
            .sheet(item: $shown) { file in
                ImportInboxSheet(file: file)
            }
    }
}

extension NewSetPreset {
    /// New set on its last step with a lecture opened from another app
    /// already read in; questions by default, the kind still changeable.
    init(lecture: ReadSource) {
        self.kind = .mcq
        self.name = lecture.name
        self.subject = "General"
        self.folderId = nil
        self.lecture = lecture
        self.notes = ""
    }
}
