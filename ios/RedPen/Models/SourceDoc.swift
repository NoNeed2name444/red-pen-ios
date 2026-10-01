import Foundation

/// The lecture a set was made from, kept so it can be read again.
///
/// Until now a source was read once, turned into cards, and thrown away. What
/// survived was a citation on each card - "Immunology.pdf, p. 12" - naming a
/// page nobody could open. That is the wrong way round: the page is the thing
/// a student wants when a card does not make sense, and the card is only the
/// pointer to it.
///
/// What is kept, and what is not:
///
/// **The text of every page** lives here. It is small - a forty page lecture is
/// tens of kilobytes - so it travels with the set to every device, and the
/// preview works on a phone that has never seen the original file.
///
/// **The original file** does not. A slide deck is tens of megabytes, and
/// putting that through every sync to make a nicer-looking preview is not a
/// trade worth making. It is kept on the device it was imported on, under the
/// hash of its own bytes, and the preview shows the real pages there. Elsewhere
/// the same preview falls back to the text, which is the part that matters.
struct SourceDoc: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    /// What the student called it - the file name, without its extension.
    var name: String
    var kind: Kind = .pdf
    var addedAt: Date = Date()
    var pages: [Page] = []
    /// The hash of the original file, if this device still has it. Never a path:
    /// a path stops being true the moment the app is reinstalled.
    var fileBlob: String?

    enum Kind: String, Codable {
        case pdf, word, powerpoint, text

        var label: String {
            switch self {
            case .pdf: return "PDF"
            case .word: return "Word"
            case .powerpoint: return "Slides"
            case .text: return "Text"
            }
        }

        /// What a page of this is called. A PowerPoint has slides, and calling
        /// them pages in a deck of slides reads as a translation error.
        var pageNoun: String { self == .powerpoint ? "Slide" : "Page" }

        var symbol: String {
            switch self {
            case .pdf: return "doc.richtext"
            case .word: return "doc.text"
            case .powerpoint: return "rectangle.on.rectangle"
            case .text: return "text.alignleft"
            }
        }
    }

    struct Page: Codable, Hashable, Identifiable {
        var number: Int
        var text: String
        /// Read by OCR rather than taken from the file. Shown, because text
        /// recognised from a photograph of a slide is good enough to study from
        /// and not good enough to trust silently.
        var recognised: Bool = false
        var id: Int { number }

        /// The first line with anything on it, for a page list.
        var heading: String {
            for line in text.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { return String(trimmed.prefix(80)) }
            }
            return ""
        }

        var isBlank: Bool {
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var pageCount: Int { pages.count }
    var recognisedPages: Int { pages.filter(\.recognised).count }

    func page(_ number: Int) -> Page? {
        pages.first { $0.number == number }
    }
}
