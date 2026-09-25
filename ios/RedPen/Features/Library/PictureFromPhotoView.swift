import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Cards ▸ Picture cards ▸ From a photo or scan.
///
/// Picture cards used to come only from diagrams found in a lecture file. Here
/// they come from anything: a photo of a textbook figure, a screenshot of a
/// slide, a page scanned with the document camera. The labels are read on
/// this device and covered the way the heart example covers them; the student
/// moves, stretches, draws or deletes covers, then saves them as a deck. A
/// scanned handout can also be kept as a lecture, listed under Sources.
///
/// Photos come through PhotosPicker, which needs no permission and works in
/// the Swift Playgrounds build too. The document camera is the Xcode build's
/// only (DocumentScanning).
struct PictureFromPhotoView: View {
    @EnvironmentObject private var store: Store

    /// The most pictures read at once: each is a few seconds of reading.
    static let pageLimit: Int = 10

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var choosingPhotos = false
    @State private var choosingFiles = false
    @State private var scanning = false

    @State private var pages: [PhotoPage] = []
    @State private var current: Int = 0
    @State private var selected: UUID?
    @State private var progress: String?
    @State private var readTask: Task<Void, Never>?
    @State private var problem: String?

    @State private var name: String = ""
    @State private var subject: String = ""
    /// The deck to add to; nil makes a new one.
    @State private var destination: UUID?
    @State private var keepAsLecture = false
    @State private var saving = false
    @State private var saved: Saved?
    @FocusState private var answerFocused: Bool

    /// What the last save made, to say so and open it.
    struct Saved {
        var set: StudySet
        var cards: Int
        var lecture: Bool
    }

    private let tint: Color = StudySetKind.anki.tint

    /// Pictures handed over already - one opened from another app or
    /// dropped on the window (ImportInboxSheet) - read as soon as this shows.
    private let initialFiles: [URL]
    @State private var readInitial = false

    init(initialFiles: [URL] = []) {
        self.initialFiles = initialFiles
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                content
            }
            .padding(16)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppBackdrop(tint: tint))
        .navigationTitle("From a photo or scan")
        .navigationBarTitleDisplayMode(.inline)
        // the save slab only once there is something to save
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if saved == nil && !pages.isEmpty {
                StudyActionBar { saveButton }
            }
        }
        .environment(\.modeTint, tint)
        .photosPicker(isPresented: $choosingPhotos, selection: $photoItems,
                      maxSelectionCount: Self.pageLimit, matching: .images)
        .onChange(of: photoItems) { _, items in readPhotos(items) }
        .fileImporter(isPresented: $choosingFiles, allowedContentTypes: [.image],
                      allowsMultipleSelection: true) { result in readFiles(result) }
        .fullScreenCover(isPresented: $scanning) { scannerCover }
        .onDisappear { readTask?.cancel() }
        .onAppear {
            guard !readInitial, !initialFiles.isEmpty else { return }
            readInitial = true
            readFiles(.success(initialFiles))
        }
    }

    @ViewBuilder
    private var content: some View {
        if let saved {
            savedPanel(saved)
        } else if pages.isEmpty {
            startPanel
        } else {
            editorPanel
            deckPanel
        }
        if let progress {
            HStack(spacing: 10) {
                ProgressView()
                Text(progress).font(.subheadline).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
        if let problem {
            Label(problem, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Choosing pictures

    private var startPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("A labelled diagram from a photo, a screenshot or a scanned page. The labels are read on this device and each gets a cover; move or add covers before saving.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            sourceTiles
        }
    }

    private var sourceTiles: some View {
        let columns: [GridItem] = [GridItem(.adaptive(minimum: 150), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 12) {
            sourceTile("Photos", detail: "A photo or screenshot", symbol: "photo.on.rectangle",
                       id: "photoSourcePhotos") { choosingPhotos = true }
            if DocumentScanning.isAvailable {
                sourceTile("Scan pages", detail: "With the camera", symbol: "doc.viewfinder",
                           id: "photoSourceScan") { scanning = true }
            }
            sourceTile("Files", detail: "A picture saved in Files", symbol: "folder",
                       id: "photoSourceFiles") { choosingFiles = true }
        }
        .disabled(progress != nil)
    }

    private func sourceTile(_ title: String, detail: String, symbol: String, id: String,
                            action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(height: 30)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
            .glassEffect(.regular.tint(tint.opacity(0.14)), in: shape)
            .contentShape(shape)
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.popTile)
        .accessibilityIdentifier(id)
    }

    @ViewBuilder
    private var scannerCover: some View {
        #if canImport(VisionKit) && !SWIFT_PACKAGE
        DocumentScannerSheet(onFinish: { images in
            scanning = false
            readScans(images)
        }, onCancel: {
            scanning = false
        })
        .ignoresSafeArea()
        #else
        EmptyView()
        #endif
    }

    // MARK: - Reading

    /// One way in, whatever the pictures came from.
    private enum Input {
        case photo(PhotosPickerItem)
        case file(URL)
        case scan(UIImage)
    }

    private func readPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        photoItems = []
        read(items.map { Input.photo($0) }, scanned: false)
    }

    private func readFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            problem = error.localizedDescription
        case .success(let urls):
            let kept: [URL] = Array(urls.prefix(Self.pageLimit))
            read(kept.map { Input.file($0) }, scanned: false)
        }
    }

    private func readScans(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        read(images.map { Input.scan($0) }, scanned: true)
    }

    /// Each picture read in turn, off the main thread, and shown as soon as
    /// it is ready; the pages already there stay.
    private func read(_ inputs: [Input], scanned: Bool) {
        readTask?.cancel()
        problem = nil
        let room: Int = max(0, Self.pageLimit - pages.count)
        let taken: [Input] = Array(inputs.prefix(room))
        guard !taken.isEmpty else {
            problem = "Ten pictures at a time. Save these first."
            return
        }
        let total: Int = taken.count
        readTask = Task { @MainActor in
            var failed = 0
            for (index, input) in taken.enumerated() {
                if Task.isCancelled { break }
                progress = total == 1 ? "Reading the labels\u{2026}" : "Reading labels, \(index + 1) of \(total)\u{2026}"
                let page: PhotoPage? = await readOne(input, scanned: scanned)
                if Task.isCancelled { break }
                guard let page else {
                    failed += 1
                    continue
                }
                pages.append(page)
                if pages.count == 1 { current = 0 }
            }
            progress = nil
            if scanned && pages.contains(where: { !$0.text.isEmpty }) { keepAsLecture = true }
            if failed > 0 {
                let plural: String = failed == 1 ? " was" : "s were"
                problem = "\(failed) picture\(plural) not readable."
            } else if !pages.isEmpty && pages.allSatisfy({ $0.covers.isEmpty }) {
                problem = "No labels were found. Drag across the picture to cover each label yourself."
            }
        }
    }

    private func readOne(_ input: Input, scanned: Bool) async -> PhotoPage? {
        switch input {
        case .photo(let item):
            guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
            return await Task.detached(priority: .userInitiated) { () -> PhotoPage? in
                PhotoOcclusionReader.read(data: data, scanned: scanned)
            }.value
        case .file(let url):
            return await Task.detached(priority: .userInitiated) { () -> PhotoPage? in
                PhotoOcclusionReader.read(fileAt: url)
            }.value
        case .scan(let image):
            return await Task.detached(priority: .userInitiated) { () -> PhotoPage? in
                PhotoOcclusionReader.read(image: image, scanned: true)
            }.value
        }
    }

    // MARK: - Adjusting the covers

    private var coversBinding: Binding<[PhotoOcclusion.Cover]> {
        Binding(get: {
            pages.indices.contains(current) ? pages[current].covers : []
        }, set: { value in
            guard pages.indices.contains(current) else { return }
            pages[current].covers = value
        })
    }

    @ViewBuilder
    private var editorPanel: some View {
        if pages.count > 1 { pageStrip }
        if pages.indices.contains(current) {
            let page: PhotoPage = pages[current]
            OcclusionCoverEditor(image: page.preview, aspect: page.aspect,
                                 covers: coversBinding, selected: $selected, tint: tint)
                .frame(maxHeight: 540)
                .frame(maxWidth: .infinity)
            Text("Drag a cover to move it, its corners to stretch it, or across the picture to draw a new one.")
                .font(.caption)
                .foregroundStyle(.secondary)
            coverTools(page)
            selectedPanel
            labelList
        }
    }

    private var pageStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pages.indices, id: \.self) { index in
                    pageChip(index)
                }
            }
        }
    }

    private func pageChip(_ index: Int) -> some View {
        let count: Int = PhotoOcclusion.answered(pages[index].covers).count
        let title: String = "Page \(index + 1) \u{00B7} \(count)"
        let chosen: Bool = index == current
        return Button {
            current = index
            selected = nil
        } label: {
            Text(title).font(.subheadline.weight(chosen ? .semibold : .regular))
        }
        .buttonStyle(.glass)
        .tint(chosen ? tint : nil)
        .accessibilityLabel("Page \(index + 1), \(count) labels")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func coverTools(_ page: PhotoPage) -> some View {
        HStack(spacing: 10) {
            Button {
                addCover(page)
            } label: {
                Label("Add a cover", systemImage: "plus.rectangle")
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier("photoAddCover")
            Spacer(minLength: 0)
            Menu {
                Button("Labels anywhere on the picture") { placeAgain(.wholePicture) }
                Button("Labels on the diagram only") { placeAgain(.diagramOnly) }
                Divider()
                Button("Remove every cover", role: .destructive) { coversBinding.wrappedValue = []; selected = nil }
                Button("Remove this picture", role: .destructive) { removePage() }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .buttonStyle(.glass)
            .disabled(progress != nil)
        }
    }

    private func addCover(_ page: PhotoPage) {
        let made = PhotoOcclusion.Cover(box: PhotoOcclusion.added(aspect: page.aspect), answer: "")
        coversBinding.wrappedValue.append(made)
        selected = made.id
        answerFocused = true
    }

    private func placeAgain(_ placement: PhotoOcclusionReader.Placement) {
        guard pages.indices.contains(current) else { return }
        let page: PhotoPage = pages[current]
        let id: UUID = page.id
        selected = nil
        progress = "Placing the covers again\u{2026}"
        readTask = Task { @MainActor in
            let placed: [PhotoOcclusion.Cover] = await Task.detached(priority: .userInitiated) { () -> [PhotoOcclusion.Cover] in
                PhotoOcclusionReader.replaced(page, placement)
            }.value
            progress = nil
            guard let index = pages.firstIndex(where: { $0.id == id }) else { return }
            pages[index].covers = placed
        }
    }

    private func removePage() {
        guard pages.indices.contains(current) else { return }
        pages.remove(at: current)
        current = max(0, min(current, pages.count - 1))
        selected = nil
    }

    /// The chosen cover's answer, to correct what OCR read or type one in.
    @ViewBuilder
    private var selectedPanel: some View {
        if let id = selected, let index = coversBinding.wrappedValue.firstIndex(where: { $0.id == id }) {
            HStack(spacing: 10) {
                TextField("What this cover hides", text: answerBinding(index))
                    .focused($answerFocused)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .popField()
                    .accessibilityIdentifier("photoCoverAnswer")
                Button(role: .destructive) {
                    deleteCover(id)
                } label: {
                    Image(systemName: "trash")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Delete this cover")
            }
        }
    }

    private func answerBinding(_ index: Int) -> Binding<String> {
        Binding(get: {
            let all: [PhotoOcclusion.Cover] = coversBinding.wrappedValue
            return all.indices.contains(index) ? all[index].answer : ""
        }, set: { text in
            var all: [PhotoOcclusion.Cover] = coversBinding.wrappedValue
            guard all.indices.contains(index) else { return }
            all[index].answer = text
            coversBinding.wrappedValue = all
        })
    }

    private func deleteCover(_ id: UUID) {
        coversBinding.wrappedValue.removeAll { $0.id == id }
        selected = nil
    }

    /// Every cover's answer as a row, for a quick read-through and for
    /// VoiceOver, where dragging boxes is not the way in.
    @ViewBuilder
    private var labelList: some View {
        let covers: [PhotoOcclusion.Cover] = coversBinding.wrappedValue
        if !covers.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(covers) { cover in
                        labelRow(cover)
                    }
                }
                .padding(.top, 6)
            } label: {
                Text(labelSummary(covers))
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func labelRow(_ cover: PhotoOcclusion.Cover) -> some View {
        let answer: String = PhotoOcclusion.tidied(cover.answer)
        let chosen: Bool = cover.id == selected
        return Button {
            selected = cover.id
        } label: {
            HStack {
                Image(systemName: chosen ? "largecircle.fill.circle" : "rectangle.fill")
                    .foregroundStyle(chosen ? tint : Color.orange)
                    .accessibilityHidden(true)
                Text(answer.isEmpty ? "No answer yet" : answer)
                    .foregroundStyle(answer.isEmpty ? .secondary : .primary)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func labelSummary(_ covers: [PhotoOcclusion.Cover]) -> String {
        let asked: Int = PhotoOcclusion.answered(covers).count
        let plural: String = asked == 1 ? "" : "s"
        let blank: Int = covers.count - asked
        let rest: String = blank > 0 ? ", \(blank) without an answer" : ""
        return "\(asked) card\(plural) on this picture\(rest)"
    }

    // MARK: - Where they go

    /// The decks that already hold picture cards, to add these to.
    private var pictureDecks: [StudySet] {
        CategoryFeature.pictures.shelfSets(store)
    }

    private var anyScanned: Bool { pages.contains { $0.scanned } }

    private var deckPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            CategoryHeading(title: "Save to")
            if !pictureDecks.isEmpty {
                Picker("Deck", selection: $destination) {
                    Text("A new deck").tag(UUID?.none)
                    ForEach(pictureDecks) { deck in
                        Text(deck.name).tag(UUID?.some(deck.id))
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("photoDeckPicker")
            }
            if destination == nil {
                TextField(PhotoOcclusion.defaultName(on: Date(), scanned: anyScanned), text: $name)
                    .popField()
                    .accessibilityLabel("Deck name")
                    .accessibilityIdentifier("photoDeckName")
                TextField("Subject, like Anatomy", text: $subject)
                    .popField()
                    .accessibilityLabel("Subject")
            }
            if pages.contains(where: { !$0.text.isEmpty }) {
                Toggle(isOn: $keepAsLecture) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Also keep the pages as a lecture")
                        Text("Listed under Sources, with the words read from each page.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(tint)
                .accessibilityIdentifier("photoKeepLecture")
            }
        }
    }

    private var cardTotal: Int {
        pages.reduce(0) { $0 + PhotoOcclusion.answered($1.covers).count }
    }

    private var saveButton: some View {
        let total: Int = cardTotal
        let plural: String = total == 1 ? "" : "s"
        return Button {
            Task { await save() }
        } label: {
            HStack {
                if saving { ProgressView().controlSize(.small) }
                Label("Save \(total) picture card\(plural)", systemImage: "checkmark")
            }
        }
        .buttonStyle(.bigPrimary)
        .disabled(total == 0 || saving || progress != nil)
        .accessibilityIdentifier("photoSave")
    }

    // MARK: - Saving

    @MainActor
    private func save() async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        let typed: String = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let deckName: String = typed.isEmpty ? PhotoOcclusion.defaultName(on: Date(), scanned: anyScanned) : typed
        let existing: StudySet? = destination.flatMap { id in store.library.first { $0.id == id } }
        var set: StudySet = existing ?? newDeck(deckName)
        let label: String = existing?.name ?? deckName

        var made = 0
        for (number, page) in pages.enumerated() {
            let imageIndex: Int = set.images.count
            let source: String = PhotoOcclusion.source(name: label, page: number + 1, of: pages.count)
            let cards: [AnkiCard] = PhotoOcclusion.cards(from: page.covers, imageIndex: imageIndex, source: source)
            guard !cards.isEmpty else { continue }
            set.images.append(page.jpeg.base64EncodedString())
            set.cards += cards
            made += cards.count
        }
        guard made > 0 else {
            problem = "Give at least one cover an answer first."
            return
        }

        var lecture = false
        if keepAsLecture {
            let scans: [(jpeg: Data, text: String)] = pages.map { (jpeg: $0.jpeg, text: $0.text) }
            if let doc = await SourceIngest.lecture(fromScans: scans, name: label) {
                set.sources.append(doc)
                lecture = true
            }
        }

        if existing != nil {
            store.update(set)
        } else {
            store.addSet(set)
        }
        let stored: StudySet = store.library.first { $0.id == set.id } ?? set
        saved = Saved(set: stored, cards: made, lecture: lecture)
        pages = []
        selected = nil
        problem = nil
    }

    private func newDeck(_ deckName: String) -> StudySet {
        let topic: String = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        return StudySet(name: deckName, subject: topic.isEmpty ? "General" : topic, kind: .anki)
    }

    private func savedPanel(_ result: Saved) -> some View {
        let plural: String = result.cards == 1 ? "" : "s"
        let lecture: String = result.lecture ? " The pages are under Sources too." : ""
        return VStack(alignment: .leading, spacing: 14) {
            Label("Saved \(result.cards) picture card\(plural) to \u{201C}\(result.set.name)\u{201D}.\(lecture)",
                  systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.primary)
            NavigationLink {
                StudySetScreen(set: result.set)
            } label: {
                Label("Open the deck", systemImage: "play.fill")
            }
            .buttonStyle(.bigPrimary)
            .accessibilityIdentifier("photoOpenDeck")
            Button {
                startOver()
            } label: {
                Label("Make more", systemImage: "plus")
            }
            .buttonStyle(.bigSecondary)
        }
    }

    private func startOver() {
        saved = nil
        name = ""
        keepAsLecture = false
        current = 0
    }
}
