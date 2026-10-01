import Foundation

/// Where a set's content came from, with the licence and credit line of each
/// part (the brief's "sources and attribution screen").
///
/// Stethoscore already records all of this, in four places, and until now
/// showed none of the licences:
/// - the lectures a set was made from (`StudySet.sources`, SourceDoc);
/// - the page of them each question or card was cited against (`source`,
///   written by Provenance);
/// - the public medical sources a differential was checked against
///   (`DifferentialTiers.evidence`, EvidenceRef - copied from what the lookup
///   returned, never written by a model);
/// - the exam a set was written for (`StudySet.exam`), whose openly licensed
///   style examples the question writer was shown (ExamExemplars).
///
/// This puts them together for one set, and lists every licence the app's
/// own content carries for Settings. Pure, so it can be tested: the exam is
/// passed in as its name and style bank, so nothing here needs the catalogue.
struct ContentLicence: Hashable {
    let name: String
    let url: String
}

/// Content the app itself brings - not the student's - with its credit.
struct ContentSource: Identifiable, Hashable {
    let id: String
    let name: String
    /// What the app uses it for, in the student's terms.
    let use: String
    let licences: [ContentLicence]
    /// The credit line, as the licence or the source asks for it.
    let attribution: String
    /// What was changed, which CC BY asks to be said. Nil when nothing is
    /// copied into the app at all.
    let changes: String?
    let home: String
}

enum ContentSources {

    static let mit = ContentLicence(name: "MIT licence", url: "https://opensource.org/license/mit")
    static let ccBy4 = ContentLicence(name: "CC BY 4.0",
                                      url: "https://creativecommons.org/licenses/by/4.0/legalcode.en")
    static let apache2 = ContentLicence(name: "Apache License 2.0",
                                        url: "https://www.apache.org/licenses/LICENSE-2.0")

    // MARK: style examples bundled with the app (ExamExemplarData)

    static let medqa = ContentSource(
        id: "medqa", name: "MedQA",
        use: "Example questions shown to the question writer, for the style of USMLE-type exams",
        licences: [mit, ccBy4],
        attribution: "MedQA by Jin et al. (2020), github.com/jind11/MedQA, MIT licence; US questions from the GBaker/MedQA-USMLE-4-options mirror on Hugging Face, CC BY 4.0.",
        changes: "A few whole questions per topic, from the training split, with spacing tidied. They are shown to the writer only as examples of style and are never shown to you as questions.",
        home: "https://github.com/jind11/MedQA")

    static let medmcqa = ContentSource(
        id: "medmcqa", name: "MedMCQA",
        use: "Example questions shown to the question writer, for the style of NEET-PG, INI-CET and FMGE",
        licences: [apache2],
        attribution: "MedMCQA by Pal et al. (2022), huggingface.co/datasets/openlifescienceai/medmcqa, Apache License 2.0.",
        changes: "A few whole questions per topic, from the training split, with spacing tidied. They are shown to the writer only as examples of style and are never shown to you as questions.",
        home: "https://huggingface.co/datasets/openlifescienceai/medmcqa")

    // MARK: public sources a check reads (server/evidence.js)

    /// The credit line governance/licences/allowlist.json gives MedlinePlus;
    /// a test keeps the two the same.
    static let medlinePlusCredit = "Courtesy of MedlinePlus from the National Library of Medicine"

    static let medlinePlus = ContentSource(
        id: "medlineplus", name: "MedlinePlus",
        use: "Health topic summaries an accuracy check reads",
        licences: [ContentLicence(name: "U.S. government work (MedlinePlus's public-domain health topics)",
                                  url: "https://medlineplus.gov/about/using/usingcontent/")],
        attribution: medlinePlusCredit + ".",
        changes: nil,
        home: "https://medlineplus.gov/")

    static let europePMC = ContentSource(
        id: "europepmc", name: "Europe PMC",
        use: "Articles an accuracy check reads; their titles are shown with a link",
        licences: [ContentLicence(name: "Each article under its own licence, shown on its page",
                                  url: "https://europepmc.org/")],
        attribution: "Article search by Europe PMC (europepmc.org). Each article belongs to its authors and publisher.",
        changes: nil,
        home: "https://europepmc.org/")

    static let openFDA = ContentSource(
        id: "openfda", name: "openFDA",
        use: "Drug labels an accuracy check reads",
        licences: [ContentLicence(name: "CC0 1.0 (public domain)", url: "https://open.fda.gov/license/")],
        attribution: "Drug label data from openFDA, U.S. Food and Drug Administration. No endorsement by the FDA is implied.",
        changes: nil,
        home: "https://open.fda.gov/")

    /// Every source of content the app brings, for Settings.
    static let all: [ContentSource] = [medqa, medmcqa, medlinePlus, europePMC, openFDA]

    /// The bank behind an exam's style examples (ExemplarSource's raw value).
    static func styleBank(_ raw: String) -> ContentSource? {
        if raw.hasPrefix("medqa") { return medqa }
        if raw == "medmcqa" { return medmcqa }
        return nil
    }

    /// The source an EvidenceRef came from, by the name the lookup gives it.
    static func evidence(_ name: String) -> ContentSource? {
        let n = name.lowercased()
        if n.contains("medlineplus") { return medlinePlus }
        if n.contains("europe pmc") { return europePMC }
        if n.contains("openfda") || n.contains("fda") { return openFDA }
        return nil
    }
}

/// One set's credits: what it was made from, and whose content it carries.
struct SetCredits: Hashable {

    /// One lecture the set was made from.
    struct Lecture: Hashable, Identifiable {
        var source: SourceDoc
        /// How many of the set's questions and cards cite a page of it.
        var cited: Int
        var id: UUID { source.id }

        /// "PDF · 32 pages · 4 read from pictures".
        var detail: String {
            var parts: [String] = [source.kind.label]
            let noun: String = source.kind.pageNoun.lowercased()
            parts.append("\(source.pageCount) \(noun)\(source.pageCount == 1 ? "" : "s")")
            if source.recognisedPages > 0 { parts.append("\(source.recognisedPages) read from pictures") }
            return parts.joined(separator: " \u{00B7} ")
        }
    }

    /// A public source the set's checks read, and the items that cite it.
    struct Evidence: Hashable, Identifiable {
        var source: ContentSource
        var refs: [EvidenceRef]
        var id: String { source.id }
    }

    var lectures: [Lecture] = []
    /// Lectures that questions or cards cite but that are not kept with the
    /// set ("Lupus, p. 14" from a set made before sources were kept).
    var citedElsewhere: [String] = []
    /// The exam's style bank, when the set was written for an exam.
    var style: ContentSource?
    var examName: String?
    var evidence: [Evidence] = []
    /// Evidence from a source this version does not know the licence of.
    var otherEvidence: [EvidenceRef] = []

    /// Nothing recorded at all: typed in, imported, or made before any of
    /// this was kept.
    var isEmpty: Bool {
        lectures.isEmpty && citedElsewhere.isEmpty && style == nil && evidence.isEmpty && otherEvidence.isEmpty
    }

    /// The set's credits. `exam` is the set's exam (ExamCatalog.exam(set.exam))
    /// as its name and the raw value of its style bank.
    static func make(_ set: StudySet, exam: (name: String, bank: String)?) -> SetCredits {
        var out = SetCredits()

        // the lectures, with how many questions cite each
        var citations: [String] = (set.questions.compactMap(\.source) + set.cards.compactMap(\.source))
            .filter { !$0.isEmpty }
        for source in set.sources {
            let mine: [String] = citations.filter { cites($0, source.name) }
            citations.removeAll { cites($0, source.name) }
            out.lectures.append(Lecture(source: source, cited: mine.count))
        }
        var seen = Set<String>()
        out.citedElsewhere = citations.map(lectureName).filter { !$0.isEmpty && seen.insert($0).inserted }

        if let exam, let bank = ContentSources.styleBank(exam.bank) {
            out.style = bank
            out.examName = exam.name
        }

        // every evidence item once, grouped by source in the catalogue's order
        var refs: [EvidenceRef] = []
        var keys = Set<String>()
        for question in set.questions {
            for ref in question.differential?.evidence ?? [] where keys.insert(ref.url + "|" + ref.title).inserted {
                refs.append(ref)
            }
        }
        for source in ContentSources.all {
            let theirs: [EvidenceRef] = refs.filter { ContentSources.evidence($0.source)?.id == source.id }
            if !theirs.isEmpty { out.evidence.append(Evidence(source: source, refs: theirs)) }
        }
        out.otherEvidence = refs.filter { ContentSources.evidence($0.source) == nil }
        return out
    }

    /// Whether a citation ("Lupus, p. 14") names this lecture. Provenance
    /// writes "name, p. N", or "p. N" alone for a lecture with no name.
    static func cites(_ citation: String, _ name: String) -> Bool {
        let cited: String = lectureName(citation)
        return cited.isEmpty ? name.isEmpty : cited == name
    }

    /// The lecture's name out of a citation: everything before ", p. ".
    static func lectureName(_ citation: String) -> String {
        if let range = citation.range(of: ", p. ", options: .backwards) {
            return String(citation[..<range.lowerBound])
        }
        return citation.hasPrefix("p. ") ? "" : citation
    }
}
