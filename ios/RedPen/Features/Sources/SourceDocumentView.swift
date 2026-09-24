import SwiftUI
import PDFKit
import QuickLook
import WebKit

/// A whole lecture, any kind: the real pages when this device has the file -
/// PDFs as they are, Word and PowerPoint turned into pages on the device -
/// and the extracted text, page by page, when it does not - all scrolled down
/// one continuous column.
struct SourceDocumentView: View {
    let source: SourceDoc
    let file: URL?
    @Binding var page: Int

    @State private var pdf: URL?
    @State private var preparing = false
    /// The file, shown by Quick Look, when it could not be turned into pages.
    @State private var quickLook: URL?

    /// One continuous column, top to bottom, for every kind of file.
    private let horizontal = false

    var body: some View {
        Group {
            if let pdf {
                PDFDocumentView(url: pdf, page: $page, horizontal: horizontal)
            } else if preparing {
                ProgressView("Preparing the \(source.kind.label.lowercased())\u{2026}")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let quickLook, !horizontal {
                QuickLookView(url: quickLook)
            } else {
                // no file on this device (or paging across a file Quick Look
                // can only scroll): the text, a page at a time
                TextPagesView(source: source, page: $page, horizontal: horizontal)
            }
        }
        .task(id: file) { await prepare() }
    }

    private func prepare() async {
        pdf = nil
        quickLook = nil
        guard let file else { return }
        switch source.kind {
        case .pdf:
            pdf = file
        case .word, .powerpoint:
            preparing = true
            defer { preparing = false }
            if let made = await OfficePages.pdf(from: file, landscape: source.kind == .powerpoint) {
                pdf = made
            } else {
                quickLook = file
            }
        case .text:
            break
        }
    }
}

/// A PDF, whole: a continuous column down, or one page at a time across.
/// Reports the page on screen back, so the page list and the page reader
/// open where the reader is.
struct PDFDocumentView: UIViewRepresentable {
    let url: URL
    @Binding var page: Int
    let horizontal: Bool

    func makeCoordinator() -> Coordinator { Coordinator(page: $page) }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.backgroundColor = .secondarySystemBackground
        view.document = PDFDocument(url: url)
        arrange(view)
        context.coordinator.watch(view)
        go(view, to: page)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        context.coordinator.page = $page
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
        if context.coordinator.horizontal != horizontal {
            let here = view.currentPage.flatMap { view.document?.index(for: $0) } ?? (page - 1)
            arrange(view)
            context.coordinator.horizontal = horizontal
            go(view, to: here + 1)
        } else {
            go(view, to: page)
        }
    }

    /// Down: one continuous column. Across: a page at a time, swiped like a
    /// book - the page view controller gives it real page turns.
    private func arrange(_ view: PDFView) {
        if horizontal {
            view.displayMode = .singlePage
            view.displayDirection = .horizontal
            view.usePageViewController(true, withViewOptions: nil)
        } else {
            view.usePageViewController(false, withViewOptions: nil)
            view.displayMode = .singlePageContinuous
            view.displayDirection = .vertical
        }
        view.autoScales = true
    }

    /// Page numbers here start at one, as people read them; PDFKit's at zero.
    private func go(_ view: PDFView, to number: Int) {
        guard let document = view.document, document.pageCount > 0 else { return }
        let index = min(max(number - 1, 0), document.pageCount - 1)
        guard let target = document.page(at: index), view.currentPage != target else { return }
        view.go(to: target)
    }

    final class Coordinator: NSObject {
        var page: Binding<Int>
        var horizontal: Bool?
        private var observer: NSObjectProtocol?

        init(page: Binding<Int>) { self.page = page }

        func watch(_ view: PDFView) {
            observer = NotificationCenter.default.addObserver(
                forName: .PDFViewPageChanged, object: view, queue: .main) { [weak self, weak view] _ in
                guard let self, let view, let current = view.currentPage,
                      let index = view.document?.index(for: current) else { return }
                if self.page.wrappedValue != index + 1 { self.page.wrappedValue = index + 1 }
            }
        }

        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
}

/// The extracted text of each page, as cards: down a column, or across one
/// page at a time.
struct TextPagesView: View {
    let source: SourceDoc
    @Binding var page: Int
    let horizontal: Bool

    var body: some View {
        if horizontal {
            TabView(selection: $page) {
                ForEach(source.pages, id: \.number) { p in
                    ScrollView { card(p).padding() }
                        .tag(p.number)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color(.secondarySystemBackground))
        } else {
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(source.pages, id: \.number) { p in
                            card(p).id(p.number)
                                .onAppear { if abs(p.number - page) > 1 { page = p.number } }
                        }
                    }
                    .padding()
                }
                .background(Color(.secondarySystemBackground))
                .onAppear { reader.scrollTo(page, anchor: .top) }
            }
        }
    }

    private func card(_ p: SourceDoc.Page) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(source.kind.pageNoun) \(p.number)")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if p.isBlank {
                Label("No text on this \(source.kind.pageNoun.lowercased())", systemImage: "photo")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Text(p.text).font(.body).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(maxWidth: 720, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Apple's own viewer for any file it knows, for a Word or PowerPoint file
/// that could not be turned into pages.
struct QuickLookView: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Source { Source(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        if context.coordinator.url != url {
            context.coordinator.url = url
            controller.reloadData()
        }
    }

    final class Source: NSObject, QLPreviewControllerDataSource {
        var url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

/// Word and PowerPoint as PDF pages, made on the device: WebKit lays the file
/// out as it would show it, and the print system cuts it into pages - slide
/// shaped for a deck, A4 for a document. Kept in Caches, so a file is
/// converted once. Nil when the result has no pages or no text, and the
/// viewer falls back to Quick Look.
@MainActor
enum OfficePages {
    static func pdf(from file: URL, landscape: Bool) async -> URL? {
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("source-pages", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let out = folder.appendingPathComponent(file.deletingPathExtension().lastPathComponent + ".pdf")
        if let cached = PDFDocument(url: out), cached.pageCount > 0 { return out }

        let paper = landscape ? CGRect(x: 0, y: 0, width: 842, height: 474)   // 16:9
                              : CGRect(x: 0, y: 0, width: 595, height: 842)   // A4
        let web = WKWebView(frame: CGRect(origin: .zero, size: paper.size))
        let loading = Loading()
        web.navigationDelegate = loading
        web.loadFileURL(file, allowingReadAccessTo: file.deletingLastPathComponent())
        guard await loading.finished() else { return nil }
        // Office files are drawn a moment after the load reports done
        try? await Task.sleep(nanoseconds: 800_000_000)

        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(web.viewPrintFormatter(), startingAtPageAt: 0)
        renderer.setValue(NSValue(cgRect: paper), forKey: "paperRect")
        renderer.setValue(NSValue(cgRect: paper.insetBy(dx: 12, dy: 12)), forKey: "printableRect")
        let pages = renderer.numberOfPages
        guard pages > 0 else { return nil }
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, paper, nil)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: pages))
        for index in 0..<pages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: index, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()

        // a conversion that printed blank pages is worse than Quick Look
        guard let made = PDFDocument(data: data as Data), made.pageCount > 0,
              !(made.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (try? (data as Data).write(to: out)) != nil else { return nil }
        return out
    }

    private final class Loading: NSObject, WKNavigationDelegate {
        private var continuation: CheckedContinuation<Bool, Never>?
        private var result: Bool?

        func finished() async -> Bool {
            if let result { return result }
            return await withCheckedContinuation { continuation = $0 }
        }

        private func finish(_ ok: Bool) {
            guard result == nil else { return }
            result = ok
            continuation?.resume(returning: ok)
            continuation = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(true) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(false) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(false) }
    }
}
