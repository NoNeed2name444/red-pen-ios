import Foundation

// Where a note kept from studying came from, and the link that opens it again.
// It stays when the Ideas feature goes: a note carries it in the notes file
// and in the library backup (Persistence/NoteStore.swift), and AppLink routes
// the link form (Shared/Platform/AppLink.swift). Foundation only, so the
// widgets compile it too; tested in Tests/SaveToIdeasTests.swift and
// Tests/PlatformTests.swift.

/// Where a note saved from studying came from. Stored on the note (optional,
/// so notes written before it, or by hand, have none) and read by its chip.
struct NoteSource: Codable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case question, card, osce, lecture
        /// A patient case, saved from its debrief.
        case patientCase = "case"

        /// How the chip names it: "Question", "Card"...
        var label: String {
            switch self {
            case .question: return "Question"
            case .card: return "Card"
            case .osce: return "OSCE station"
            case .lecture: return "Lecture"
            case .patientCase: return "Case"
            }
        }

        /// The same word inside a sentence.
        var noun: String {
            switch self {
            case .osce: return "OSCE station"
            default: return label.lowercased()
            }
        }

        var symbol: String {
            switch self {
            case .question: return "list.bullet.rectangle"
            case .card: return "rectangle.on.rectangle"
            case .osce: return "list.clipboard"
            case .lecture: return "doc.richtext"
            case .patientCase: return "stethoscope"
            }
        }
    }

    var kind: Kind
    /// The set it was saved from.
    var setID: UUID
    /// The question, card, station or lecture; nil when only the
    /// set is known.
    var itemID: UUID? = nil
    /// The lecture page, from 1; nil for everything but a lecture.
    var page: Int? = nil
    /// The set's name when it was saved, for the chip: the set may be renamed
    /// or deleted later, and the chip should still say something.
    var setName: String = ""

    init(kind: Kind, setID: UUID, itemID: UUID? = nil, page: Int? = nil, setName: String = "") {
        self.kind = kind
        self.setID = setID
        self.itemID = itemID
        self.page = page
        self.setName = setName
    }

    private enum Keys: String, CodingKey { case kind, setID, itemID, page, setName }

    /// The kind and the set are needed; the rest may be missing. A kind this
    /// version does not know throws, and the note reads it as no source
    /// rather than losing the note.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        kind = try c.decode(Kind.self, forKey: .kind)
        setID = try c.decode(UUID.self, forKey: .setID)
        itemID = try c.decodeIfPresent(UUID.self, forKey: .itemID)
        page = try c.decodeIfPresent(Int.self, forKey: .page)
        setName = try c.decodeIfPresent(String.self, forKey: .setName) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(setID, forKey: .setID)
        try c.encodeIfPresent(itemID, forKey: .itemID)
        try c.encodeIfPresent(page, forKey: .page)
        if !setName.isEmpty { try c.encode(setName, forKey: .setName) }
    }

    /// One note per item: a question's id is the same in every set it has
    /// been copied into (a Mistakes set, a quiz put together on the spot), so
    /// the item decides, not the set. A lecture is one note however many of
    /// its pages were saved into it.
    var dedupeKey: String {
        let id: UUID = itemID ?? setID
        return kind.rawValue + ":" + id.uuidString.lowercased()
    }

    /// "Question · Cardiology"
    var chipLabel: String {
        let name: String = setName.trimmingCharacters(in: .whitespacesAndNewlines)
        var label: String = kind.label
        if let page { label += " p. \(page)" }
        return name.isEmpty ? label : label + " \u{00B7} " + name
    }

    // MARK: the link form

    /// The schemes AppLink answers to; `stethoscore` is the one people see.
    static let scheme = "stethoscore"
    static let host = "item"

    /// `stethoscore://item/question/<set>/<item>?page=3&set=Cardiology` -
    /// what AppLink routes, so a Shortcut or a link can open the same place
    /// the chip does. An item-less source writes "-" for the item.
    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        let item: String = itemID?.uuidString ?? "-"
        components.path = "/" + kind.rawValue + "/" + setID.uuidString + "/" + item
        var query: [URLQueryItem] = []
        if let page { query.append(URLQueryItem(name: "page", value: String(page))) }
        if !setName.isEmpty { query.append(URLQueryItem(name: "set", value: setName)) }
        components.queryItems = query.isEmpty ? nil : query
        return components.url ?? URL(string: "stethoscore://item")!
    }

    /// The source a link names, or nil when it is not one (any scheme; the
    /// caller has already decided the link is the app's).
    init?(url: URL) {
        guard (url.host ?? "").lowercased() == Self.host else { return nil }
        let parts: [String] = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2, let kind = Kind(rawValue: parts[0]),
              let set = UUID(uuidString: parts[1]) else { return nil }
        let item: UUID? = parts.count >= 3 ? UUID(uuidString: parts[2]) : nil
        let items: [URLQueryItem] = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let pageText: String? = items.first(where: { $0.name == "page" })?.value
        let page: Int? = pageText.flatMap { Int($0) }.flatMap { $0 > 0 ? $0 : nil }
        let name: String = items.first(where: { $0.name == "set" })?.value ?? ""
        self.init(kind: kind, setID: set, itemID: item, page: page, setName: name)
    }
}
