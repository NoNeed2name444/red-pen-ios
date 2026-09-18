import SwiftUI
import UniformTypeIdentifiers

/// Writing stations from a lecture, for the new-set screen.
///
/// The result is written into the text box rather than straight into a set.
/// That is deliberate: a checklist written by a model is a draft, and the
/// person who knows whether "auscultate in four areas" was taught as one step
/// or four is the student who sat the teaching. They edit, then create.
///
/// Its own file because SwiftUI type-checks a whole view as one expression, and
/// the new-set screen is already long enough to have been split once.
struct OsceGenerateSection: View {
    @Binding var bodyText: String
    let subject: String

    @State private var picking = false
    @State private var working = false
    @State private var status: String?
    @State private var trouble: String?
    @State private var sourceText = ""
    @State private var sourceName = ""
    @State private var stationCount = 3
    @State private var task: Task<Void, Never>?

    private var readableTypes: [UTType] {
        [.pdf,
         UTType("org.openxmlformats.wordprocessingml.document"),
         UTType("org.openxmlformats.presentationml.presentation")].compactMap { $0 }
    }

    private var canGenerate: Bool {
        !working && sourceText.trimmingCharacters(in: .whitespacesAndNewlines).count > 200
    }

    var body: some View {
        Section {
            Button { picking = true } label: {
                Label(sourceName.isEmpty ? "Read a skills lecture or mark sheet"
                                         : "Read a different file",
                      systemImage: "doc.badge.plus")
            }
            .disabled(working)

            if !sourceName.isEmpty {
                Stepper("Stations: \(stationCount)", value: $stationCount,
                        in: 1...OsceGenerator.maxStationsTotal)
                    .disabled(working)
                Button {
                    working ? stop() : start()
                } label: {
                    Label(working ? "Stop" : "Write the stations",
                          systemImage: working ? "stop.circle" : "sparkles")
                }
                .disabled(!canGenerate && !working)
            }

            if let status {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            if let trouble {
                Text(trouble).font(.caption).foregroundStyle(.red)
            }
        } header: {
            Text("Write them from a lecture")
        } footer: {
            Text("Stations land in the box below to check and edit before you create the set. A skills lecture or a mark sheet works best.")
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: readableTypes,
                      allowsMultipleSelection: false) { result in
            Task { await read(result) }
        }
    }

    private func read(_ result: Result<[URL], Error>) async {
        trouble = nil
        guard let url = (try? result.get())?.first else {
            if case .failure(let error) = result { trouble = error.localizedDescription }
            return
        }
        working = true
        status = "Reading\u{2026}"
        defer { working = false }
        do {
            let isPDF = url.pathExtension.lowercased() == "pdf"
            // No figures: a station comes out of the words, and rendering every
            // page to hunt for diagrams is the slow half of reading a file.
            let read = isPDF ? try await SourceIngest.read(pdf: url, findingFigures: false)
                             : try await OfficeIngest.read(url)
            sourceText = read.document.text
            sourceName = url.deletingPathExtension().lastPathComponent
            status = "\(sourceName) \u{2014} \(read.document.pages.count) pages."
            if !canGenerate {
                trouble = "There is not much text in that file to work from."
            }
        } catch {
            status = nil
            trouble = error.localizedDescription
        }
    }

    private func start() {
        trouble = nil
        working = true
        let wanted = stationCount, subj = subject, text = sourceText
        status = "Writing 0 of \(wanted)\u{2026}"
        task = Task {
            do {
                let stations = try await OsceGenerator.generate(
                    sourceText: text, count: wanted, subject: subj,
                    onProgress: { done, total in
                        Task { @MainActor in status = "Writing \(done) of \(total)\u{2026}" }
                    })
                await MainActor.run {
                    working = false
                    let written = OsceStations.format(stations)
                    // Appended, never replacing: a student who typed a station
                    // and then generated more means both.
                    let existing = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
                    bodyText = existing.isEmpty ? written : existing + "\n\n" + written
                    status = "\(stations.count) station\(stations.count == 1 ? "" : "s") written \u{2014} check them below."
                }
            } catch is CancellationError {
                await MainActor.run { working = false; status = nil }
            } catch {
                await MainActor.run {
                    working = false
                    status = nil
                    trouble = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                }
            }
        }
    }

    private func stop() {
        task?.cancel()
        task = nil
        working = false
        status = nil
    }
}
