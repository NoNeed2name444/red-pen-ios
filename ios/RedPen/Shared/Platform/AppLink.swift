import Foundation

// MARK: - Where the system asks the app to go
//
// One vocabulary for every way in from outside the app: a `redpen://` link,
// a Siri or Shortcuts request, a Spotlight tap, a widget, the Control Centre
// button and the iPad's keyboard commands. Each of them becomes an AppLink,
// and AppRouter (AppIntentsRouting.swift) is the one place that acts on it.
//
// Foundation only, so the parsing is tested on Linux (PlatformTests).

enum AppLink: Equatable {
    /// Every card due today, across the library.
    case reviewDue
    /// One set, opened in the library.
    case openSet(UUID)
    /// A quick quiz on one subject ("Quiz me on cardiology").
    case quiz(subject: String)
    /// The library's search, with this text in it.
    case search(String)
    /// New set.
    case newSet
    /// The exam plan (the countdown widget's tap).
    case examPlan

    /// The schemes the app answers to. `redpen` is the one declared since the
    /// first build (Google sign-in returns to it); `stethoscore` is the name
    /// people see.
    static let schemes: Set<String> = ["redpen", "stethoscore"]

    /// Hosts that belong to something else and are never routed: the sign-in
    /// return (redpen://auth) is read by the web-authentication session.
    static let reserved: Set<String> = ["auth"]

    /// The link's destination, or nil when it is not a link for the router.
    static func parse(_ url: URL) -> AppLink? {
        guard let scheme = url.scheme?.lowercased(), schemes.contains(scheme) else { return nil }
        let host: String = (url.host ?? "").lowercased()
        if reserved.contains(host) { return nil }
        let parts: [String] = url.pathComponents.filter { $0 != "/" }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items: [URLQueryItem] = components?.queryItems ?? []
        func value(_ name: String) -> String? {
            let found: String? = items.first(where: { $0.name == name })?.value
            return found?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        switch host {
        case "due", "review":
            return .reviewDue
        case "set", "open":
            let raw: String = parts.first ?? value("id") ?? ""
            guard let id = UUID(uuidString: raw) else { return nil }
            return .openSet(id)
        case "quiz":
            let subject: String = value("subject") ?? parts.first ?? ""
            return subject.isEmpty ? nil : .quiz(subject: subject)
        case "search":
            return .search(value("q") ?? "")
        case "new":
            return .newSet
        case "exam", "countdown":
            return .examPlan
        default:
            return nil
        }
    }

    /// The link that leads here, for widgets and Spotlight.
    var url: URL {
        var components = URLComponents()
        components.scheme = "redpen"
        switch self {
        case .reviewDue:
            components.host = "due"
        case .openSet(let id):
            components.host = "set"
            components.path = "/" + id.uuidString
        case .quiz(let subject):
            components.host = "quiz"
            components.queryItems = [URLQueryItem(name: "subject", value: subject)]
        case .search(let text):
            components.host = "search"
            components.queryItems = [URLQueryItem(name: "q", value: text)]
        case .newSet:
            components.host = "new"
        case .examPlan:
            components.host = "exam"
        }
        return components.url ?? URL(string: "redpen://due")!
    }
}

// MARK: - "Quiz me on cardiology"

/// Which sets a spoken subject means. People say "cardio", "heart" or
/// "cardiology" for the same shelf, and a Siri transcript is lower case with
/// no punctuation, so both sides are folded before they are compared.
enum SubjectMatch {
    /// Short and everyday names for the usual subjects, folded.
    static let aliases: [String: String] = [
        "cardio": "cardiology", "cardiac": "cardiology", "heart": "cardiology",
        "resp": "respiratory", "respiratory medicine": "respiratory", "lungs": "respiratory",
        "pulmonology": "respiratory", "chest": "respiratory",
        "gi": "gastroenterology", "gastro": "gastroenterology", "gut": "gastroenterology",
        "neuro": "neurology", "brain": "neurology",
        "renal": "nephrology", "kidney": "nephrology", "kidneys": "nephrology",
        "endo": "endocrinology", "endocrine": "endocrinology",
        "obs": "obstetrics", "gynae": "gynaecology", "gyn": "gynaecology", "gynecology": "gynaecology",
        "peds": "paediatrics", "paeds": "paediatrics", "pediatrics": "paediatrics",
        "psych": "psychiatry", "derm": "dermatology", "skin": "dermatology",
        "haem": "haematology", "heme": "haematology", "hematology": "haematology",
        "micro": "microbiology", "pharm": "pharmacology", "pharma": "pharmacology",
        "ortho": "orthopaedics", "orthopedics": "orthopaedics",
        "id": "infectious diseases", "infectious disease": "infectious diseases",
        "anat": "anatomy", "physio": "physiology", "path": "pathology",
    ]

    /// Lower case, no accents, punctuation as spaces, single spaces.
    static func folded(_ text: String) -> String {
        let plain: String = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        var out: String = ""
        var lastSpace: Bool = true
        for scalar in plain.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                out.unicodeScalars.append(scalar)
                lastSpace = false
            } else if !lastSpace {
                out.append(" ")
                lastSpace = true
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// The folded name with any alias resolved.
    static func canonical(_ text: String) -> String {
        let key: String = folded(text)
        return aliases[key] ?? key
    }

    /// How well `candidate` answers `query`: 3 the same subject, 2 a whole
    /// word of it (or it starts the same way), 1 contained in it, 0 not at all.
    static func score(query: String, candidate: String) -> Int {
        // as written, and with aliases resolved ("renal" is a word of "Renal
        // physiology" before it is "nephrology")
        let plain: Int = rawScore(folded(query), folded(candidate))
        let resolved: Int = rawScore(canonical(query), canonical(candidate))
        return max(plain, resolved)
    }

    private static func rawScore(_ wanted: String, _ have: String) -> Int {
        guard !wanted.isEmpty, !have.isEmpty else { return 0 }
        if wanted == have { return 3 }
        let words: [String] = have.split(separator: " ").map(String.init)
        if words.contains(wanted) { return 2 }
        if have.hasPrefix(wanted) || wanted.hasPrefix(have) { return 2 }
        if wanted.count >= 3 && have.contains(wanted) { return 1 }
        return 0
    }

    static func matches(_ query: String, _ candidate: String) -> Bool {
        score(query: query, candidate: candidate) > 0
    }

    /// The best of a set's names (its subject, its own name, its tags).
    static func score(query: String, names: [String]) -> Int {
        var best: Int = 0
        for name in names {
            let one: Int = score(query: query, candidate: name)
            if one > best { best = one }
        }
        return best
    }

    /// Distinct subjects, as first written, most sets first.
    static func distinctSubjects(_ subjects: [String]) -> [String] {
        var counts: [String: Int] = [:]
        var firstSpelling: [String: String] = [:]
        for subject in subjects {
            let key: String = canonical(subject)
            if key.isEmpty { continue }
            counts[key, default: 0] += 1
            if firstSpelling[key] == nil { firstSpelling[key] = subject.trimmingCharacters(in: .whitespaces) }
        }
        let keys: [String] = counts.keys.sorted { a, b in
            let ca: Int = counts[a] ?? 0
            let cb: Int = counts[b] ?? 0
            return ca != cb ? ca > cb : a < b
        }
        return keys.compactMap { firstSpelling[$0] }
    }
}

// MARK: - What kind of file arrived

/// What a file handed to the app (Files, Mail, AirDrop, a drag onto the
/// library) is, from its name and its first bytes. Nothing is read beyond
/// that here: the import preview reads the file, and nothing is added to the
/// library until the student taps.
enum ImportKind: String, Equatable, CaseIterable {
    /// An Anki deck (.apkg).
    case ankiDeck
    /// A whole Anki collection (.colpkg).
    case ankiCollection
    /// Comma-separated values (Quizlet, a spreadsheet).
    case csv
    /// Tab-separated values (Quizlet's own export).
    case tsv
    /// One shared set (.stethoscore holding JSON, or a plain .json).
    case studySet
    /// A whole-library backup (.stethoscorebackup, or .stethoscore holding a zip).
    case backup
    /// A lecture: PDF, Word or PowerPoint.
    case lecture
    /// A picture, for picture cards.
    case image
    /// Plain text.
    case text
    case unknown

    static let setExtension = "stethoscore"
    static let backupExtension = "stethoscorebackup"

    /// From the file name alone.
    static func of(fileName: String) -> ImportKind {
        let ext: String = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "apkg": return .ankiDeck
        case "colpkg": return .ankiCollection
        case "csv": return .csv
        case "tsv", "tab": return .tsv
        case setExtension, "json": return .studySet
        case backupExtension: return .backup
        case "pdf", "docx", "pptx": return .lecture
        case "png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "tif", "tiff": return .image
        case "txt", "md": return .text
        default: return .unknown
        }
    }

    /// The backup's first entry (the app writes its manifest first).
    static let backupManifest = "manifest.json"

    /// How many first bytes `of(fileName:head:)` wants: a zip's first local
    /// header (30 bytes) and the name that follows it.
    static let headLength = 64

    /// From the name and the first bytes: a `.stethoscore` that is really a
    /// zip is a backup, and so is a `.zip` whose first entry is the backup's
    /// manifest - any other zip is not something the app reads. A `.json`
    /// that is not an object is not a set.
    static func of(fileName: String, head: Data) -> ImportKind {
        let named: ImportKind = of(fileName: fileName)
        let bytes: [UInt8] = Array(head.prefix(4))
        let isZip: Bool = bytes.count >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B
        let ext: String = (fileName as NSString).pathExtension.lowercased()
        if isZip && named == .studySet { return .backup }
        if ext == "zip" {
            return isZip && firstZipEntry(head) == backupManifest ? .backup : .unknown
        }
        if named == .studySet {
            // white space and a UTF-8 byte-order mark may come before the "{"
            let skipped: Set<UInt8> = [0x20, 0x0A, 0x0D, 0x09, 0xEF, 0xBB, 0xBF]
            let first: UInt8? = head.first(where: { !skipped.contains($0) })
            return first == 0x7B ? .studySet : .unknown
        }
        return named
    }

    /// The name in a zip's first local file header, when the bytes hold it.
    static func firstZipEntry(_ head: Data) -> String? {
        let bytes: [UInt8] = Array(head)
        guard bytes.count >= 30, bytes[0] == 0x50, bytes[1] == 0x4B, bytes[2] == 0x03, bytes[3] == 0x04 else { return nil }
        let length: Int = Int(bytes[26]) | (Int(bytes[27]) << 8)
        guard length > 0, bytes.count >= 30 + length else { return nil }
        return String(decoding: bytes[30..<(30 + length)], as: UTF8.self)
    }

    /// Whether this is study material the import preview handles.
    var isStudyData: Bool {
        switch self {
        case .ankiDeck, .ankiCollection, .csv, .tsv, .studySet, .backup: return true
        case .lecture, .image, .text, .unknown: return false
        }
    }

    /// How the preview names it.
    var label: String {
        switch self {
        case .ankiDeck: return "Anki deck"
        case .ankiCollection: return "Anki collection"
        case .csv: return "Spreadsheet (CSV)"
        case .tsv: return "Quizlet or spreadsheet (TSV)"
        case .studySet: return "Stethoscore set"
        case .backup: return "Stethoscore backup"
        case .lecture: return "Lecture"
        case .image: return "Picture"
        case .text: return "Text"
        case .unknown: return "File"
        }
    }
}
