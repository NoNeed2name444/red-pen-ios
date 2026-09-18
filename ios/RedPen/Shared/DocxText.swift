import Foundation

/// A Word document's words and pictures.
///
/// A .docx is a zip holding one XML file of text plus a folder of images. There
/// is no parsing to speak of - the text is between the tags - so this is pure
/// Foundation and every decision in it can be tested, the same split as
/// SourceText against SourceIngest.
///
/// What is deliberately NOT attempted: styles, numbering, tables as tables,
/// footnotes. A handout's meaning survives as paragraphs; carrying the styling
/// through would change nothing about the cards made from it.
enum DocxText {

    /// Where Word keeps the text, and where it keeps the pictures.
    static let documentPath = "word/document.xml"
    static let mediaPrefix = "word/media/"

    /// One entry per paragraph, blank ones dropped.
    static func paragraphs(fromXML xml: String) -> [String] {
        var marked = xml
        // the breaks Word writes inside a paragraph mean a line break, and the
        // end of a paragraph means a new line: without these every page of the
        // handout arrives as one unbroken sentence
        for (tag, replacement) in [("</w:p>", "\n"), ("<w:br/>", "\n"),
                                   ("<w:br />", "\n"), ("<w:cr/>", "\n"),
                                   ("<w:tab/>", "\t"), ("<w:tab />", "\t")] {
            marked = marked.replacingOccurrences(of: tag, with: replacement)
        }
        return decodeEntities(stripTags(marked))
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The whole document as plain text, one paragraph per line.
    static func text(fromXML xml: String) -> String {
        paragraphs(fromXML: xml).joined(separator: "\n")
    }

    /// Everything worth having from an opened archive.
    ///
    /// The pictures come back in filename order, which is the order Word wrote
    /// them and usually - not always - the order they appear in the document.
    /// Nothing downstream depends on that order meaning anything, so a document
    /// that shuffles them still produces the right cards for each picture.
    static func read(_ archive: [String: Data]) -> (text: String, images: [Data]) {
        let xml = archive[documentPath].map { String(decoding: $0, as: UTF8.self) } ?? ""
        let images = archive.keys
            .filter { $0.hasPrefix(mediaPrefix) && isPicture($0) }
            .sorted { natural($0) < natural($1) }
            .compactMap { archive[$0] }
        return (text(fromXML: xml), images)
    }

    /// image2.png before image10.png, which plain sorting gets backwards.
    static func natural(_ name: String) -> String {
        let digits = name.filter(\.isNumber)
        guard !digits.isEmpty, digits.count < 12 else { return name }
        return name.replacingOccurrences(of: digits,
                                         with: String(repeating: "0", count: 12 - digits.count) + digits)
    }

    static func isPicture(_ name: String) -> Bool {
        let lower = name.lowercased()
        return [".png", ".jpg", ".jpeg", ".gif", ".tiff", ".bmp"]
            .contains { lower.hasSuffix($0) }
    }

    // MARK: the XML itself

    /// Everything between angle brackets goes; everything else stays.
    static func stripTags(_ xml: String) -> String {
        var out = ""
        var inside = false
        for character in xml {
            if character == "<" { inside = true }
            else if character == ">" { inside = false }
            else if !inside { out.append(character) }
        }
        return out
    }

    /// After the tags are gone, not before: a `&lt;` in the text is a less-than
    /// sign the student typed, and decoding it first would turn the rest of the
    /// sentence into a tag and delete it.
    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = text
        for (entity, character) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
                                    ("&apos;", "'"), ("&#39;", "'"), ("&nbsp;", " ")] {
            out = out.replacingOccurrences(of: entity, with: character)
        }
        // last, or an escaped entity would be decoded twice
        return out.replacingOccurrences(of: "&amp;", with: "&")
    }
}
