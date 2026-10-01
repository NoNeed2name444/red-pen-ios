import Foundation

/// A question's stem read as a patient's chart (docs/design/targets-2026-10-01.md
/// §1, "A question as a patient chart"): who the patient is, their vital
/// signs, their results with high and low marked, the story, and the
/// question asked. Only what the stem says is shown - nothing is inferred -
/// and a stem with no observations in it stays plain text.
///
/// High and low for results come from AccuracyRules' reference ranges, the
/// table the accuracy check uses, so the chart and the check never disagree
/// about what is abnormal; a result that table does not know is shown
/// without a flag rather than guessed at. Foundation only, so
/// PatientChartTests runs it on Linux.
struct PatientChart: Equatable {
    enum Flag: String, Equatable { case high = "H", low = "L" }

    struct Vital: Equatable {
        var label: String
        var value: String
        var flag: Flag?
    }

    struct Lab: Equatable {
        var name: String
        var value: String
        var unit: String
        var flag: Flag?
    }

    /// "34 y", "Male", "Pregnant", "3 wk"
    var chips: [String] = []
    var vitals: [Vital] = []
    var labs: [Lab] = []
    /// The stem without its question and without the sentences that only
    /// list what the grid and the table already show.
    var story: String = ""
    /// The question asked, set in bold under the chart; empty when the stem
    /// has no question sentence of its own.
    var question: String = ""

    /// Whether there is anything to chart.
    var hasObservations: Bool { !vitals.isEmpty || !labs.isEmpty }

    // MARK: reading a stem

    static func read(_ stem: String) -> PatientChart {
        let text: String = normalised(stem)
        var chart = PatientChart()
        chart.chips = chips(text)
        let sentences: [String] = AccuracyRules.sentences(text)
        let asked: Int? = questionIndex(sentences)
        var kept: [String] = []
        for (i, sentence) in sentences.enumerated() {
            let found = observations(in: sentence)
            chart.vitals += found.vitals
            chart.labs += found.labs
            if i == asked { continue }
            // a sentence that only lists what the chart shows is not repeated
            if found.vitals.isEmpty && found.labs.isEmpty || !onlyObservations(sentence, spans: found.spans) {
                kept.append(sentence)
            }
        }
        // one reading of each sign: the first the stem gives
        var seen: Set<String> = []
        chart.vitals = chart.vitals.filter { seen.insert($0.label).inserted }
        if let asked { chart.question = sentences[asked] }
        chart.story = kept.joined(separator: " ")
        if chart.story.isEmpty && chart.question.isEmpty { chart.story = stem }
        return chart
    }

    /// Stems arrive with every kind of degree sign and micro.
    static func normalised(_ s: String) -> String {
        s.replacingOccurrences(of: "μ", with: "µ")
            .replacingOccurrences(of: "º", with: "°")
            .replacingOccurrences(of: "˚", with: "°")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    /// The last sentence that asks something.
    static func questionIndex(_ sentences: [String]) -> Int? {
        if let i = sentences.lastIndex(where: { $0.contains("?") }) { return i }
        let lead: String = #"^(?:which|what|the most (?:likely|appropriate)|the next|the best)\b"#
        return sentences.lastIndex { AccuracyRules.matches(lead, $0.lowercased()) }
    }

    // MARK: who the patient is

    private static let numberWords: [String: String] = [
        "a": "1", "an": "1", "one": "1", "two": "2", "three": "3", "four": "4", "five": "5",
        "six": "6", "seven": "7", "eight": "8", "nine": "9", "ten": "10", "twelve": "12",
    ]

    private static let spans: [String: String] = [
        "hour": "h", "hours": "h", "day": "d", "days": "d", "week": "wk", "weeks": "wk",
        "month": "mo", "months": "mo", "year": "y", "years": "y",
    ]

    static func chips(_ text: String) -> [String] {
        let t: String = text.lowercased()
        var out: [String] = []
        if let m = AccuracyRules.find(#"\b(\d{1,3})[\s-]*(?:year|yr)s?[\s-]*old\b"#, in: t).first, let n = m.groups[1] {
            out.append(n + " y")
        } else if let m = AccuracyRules.find(#"\b(\d{1,2})[\s-]*months?[\s-]*old\b"#, in: t).first, let n = m.groups[1] {
            out.append(n + " mo")
        } else if let m = AccuracyRules.find(#"\b(\d{1,2})[\s-]*(?:day|week)s?[\s-]*old\b"#, in: t).first, let n = m.groups[1] {
            out.append(n + (t.contains("week") ? " wk" : " d") + " old")
        } else if AccuracyRules.matches(#"\b(?:newborn|neonate)\b"#, t) {
            out.append("Newborn")
        }
        if AccuracyRules.matches(#"\b(?:man|male|boy|gentleman|father|he)\b"#, t)
            && !AccuracyRules.matches(#"\b(?:woman|female|girl|lady|mother|she)\b"#, t) {
            out.append("Male")
        } else if AccuracyRules.matches(#"\b(?:woman|female|girl|lady|mother|she)\b"#, t)
            && !AccuracyRules.matches(#"\b(?:man|male|boy|gentleman|father|he)\b"#, t) {
            out.append("Female")
        }
        if AccuracyRules.matches(#"\bpregnan(?:t|cy)\b"#, t) && !AccuracyRules.matches(#"\bnot pregnant\b"#, t) {
            out.append("Pregnant")
        }
        let duration: String = #"\b(?:for|over)\s+(?:the\s+(?:last|past)\s+)?(\d+|an?|one|two|three|four|five|six|seven|eight|nine|ten|twelve)\s+(hours?|days?|weeks?|months?|years?)\b"#
        if let m = AccuracyRules.find(duration, in: t).first, let n = m.groups[1], let unit = m.groups[2],
           let short = spans[unit] {
            out.append((numberWords[n] ?? n) + " " + short)
        }
        return out
    }

    // MARK: vital signs and results

    /// The vital signs, with the thresholds an adult's chart would flag:
    /// BP 140/90 and over high, systolic under 90 low; pulse over 100 or
    /// under 60; breathing over 20 or under 12; temperature 38.0 °C and over,
    /// under 35.0; saturation under 94%.
    private static let vitalPatterns: [(label: String, pattern: String)] = [
        ("BP", #"\b(?:bp|blood pressure)\b[^0-9.;]{0,14}?(\d{2,3})\s*/\s*(\d{2,3})(?:\s*mm\s?hg)?"#),
        ("HR", #"\b(?:hr|heart rate|pulse(?: rate)?)\b[^0-9.;/]{0,14}?(\d{2,3})(?:\s*(?:/\s*min(?:ute)?|bpm|beats?(?:\s*(?:per|/|a)\s*min(?:ute)?)?|per\s+min(?:ute)?))?"#),
        ("RR", #"\b(?:rr|resp(?:iratory)?\.?\s*rate|respirations?)\b[^0-9.;/]{0,14}?(\d{1,2})(?:\s*(?:/\s*min(?:ute)?|breaths?(?:\s*(?:per|/|a)\s*min(?:ute)?)?|per\s+min(?:ute)?))?"#),
        ("Temp", #"(?:\btemp(?:erature)?\b[^0-9.;]{0,14}?)?(\d{2,3}(?:\.\d)?)\s*(?:°\s*|degrees?\s+)(c|f)(?:elsius|ahrenheit)?\b"#),
        ("SpO2", #"\b(?:spo2|sp02|sao2|o2\s*sat(?:uration)?s?|oxygen\s+sat(?:uration)?s?|sats?|saturat(?:ing|es|ion))\b[^0-9.;]{0,16}?(\d{2,3})\s*%"#),
    ]

    private static let units: String = [
        #"mmol/l"#, #"µmol/l"#, #"umol/l"#, #"nmol/l"#, #"pmol/l"#, #"g/l"#, #"g/dl"#, #"mg/dl"#, #"mg/l"#,
        #"µg/l"#, #"ug/l"#, #"ng/ml"#, #"ng/l"#, #"pg/ml"#, #"iu/l"#, #"u/l"#, #"miu/l"#, #"mu/l"#,
        #"mmol/mol"#, #"meq/l"#, #"mm/h(?:r|our)?"#, #"fl"#, #"pg"#, #"mg/mmol"#, #"kpa"#, #"mm\s?hg"#,
        #"(?:x|×)\s?10\s?(?:\^\s?)?(?:9|⁹)\s?/\s?l"#, #"(?:x|×)\s?10\s?(?:\^\s?)?(?:12|¹²)\s?/\s?l"#,
        #"%"#, #"sec(?:onds)?"#, #"s"#,
    ].joined(separator: "|")

    private static let labPattern: String =
        #"(?:^|[\s,;:(])([a-z][a-z0-9\-+]*(?:\s+[a-z][a-z0-9\-+]*){0,3}?)\s*(?:level|concentration|count)?\s*(?:of|:|=|is|was|at)?\s*(\d+(?:\.\d+)?)\s*("# + units + #")(?![a-z0-9])"#

    /// Words that lead into a result but are not its name.
    private static let leadIns: Set<String> = [
        "serum", "plasma", "blood", "his", "her", "their", "the", "a", "an", "and", "with", "shows", "showed",
        "show", "reveal", "reveals", "revealed", "results", "result", "investigations", "labs", "bloods",
        "tests", "test", "include", "including", "of", "is", "was", "were", "are", "on", "her", "level",
        "levels", "random", "fasting", "total",
    ]

    /// Names that are vital signs, not results.
    private static let vitalNames: Set<String> = [
        "bp", "hr", "rr", "pulse", "temp", "temperature", "spo2", "sp02", "sao2", "sats", "sat", "saturation",
        "saturations", "o2", "oxygen", "heart", "rate", "respiratory", "pressure",
    ]

    struct Found {
        var vitals: [Vital] = []
        var labs: [Lab] = []
        /// UTF-16 ranges of what was read, so the rest of the sentence can be judged
        var spans: [NSRange] = []
    }

    static func observations(in sentence: String) -> Found {
        var found = Found()
        let ns = sentence as NSString
        for (label, pattern) in vitalPatterns {
            for m in AccuracyRules.find(pattern, in: sentence, caseless: true) {
                guard let vital = vital(label, m.groups) else { continue }
                found.vitals.append(vital)
                found.spans.append(NSRange(location: m.start, length: m.end - m.start))
            }
        }
        for m in AccuracyRules.find(labPattern, in: sentence, caseless: true) {
            let range = NSRange(location: m.start, length: m.end - m.start)
            if found.spans.contains(where: { NSIntersectionRange($0, range).length > 0 }) { continue }
            guard let rawName = m.groups[1], let value = m.groups[2], let unit = m.groups[3] else { continue }
            var words: [String] = rawName.split(separator: " ").map(String.init)
            while let first = words.first, leadIns.contains(first.lowercased()) { words.removeFirst() }
            guard !words.isEmpty, words.count <= 3,
                  !words.contains(where: { vitalNames.contains($0.lowercased()) }) else { continue }
            let name: String = words.joined(separator: " ")
            // a bare "s" or "%" after a lone word is too easily something else
            if unit.lowercased() == "s" && name.count > 5 { continue }
            found.labs.append(Lab(name: displayName(name), value: value, unit: unit.trimmingCharacters(in: .whitespaces),
                                  flag: labFlag(name: name, value: AccuracyRules.number(value), unit: unit)))
            found.spans.append(range)
        }
        _ = ns
        return found
    }

    private static func vital(_ label: String, _ groups: [String?]) -> Vital? {
        func n(_ i: Int) -> Double? { groups.indices.contains(i) ? groups[i].flatMap { Double($0) } : nil }
        switch label {
        case "BP":
            guard let sys = n(1), let dia = n(2), (50...300).contains(sys), (20...200).contains(dia), sys > dia else { return nil }
            let flag: Flag? = sys >= 140 || dia >= 90 ? .high : (sys < 90 ? .low : nil)
            return Vital(label: "BP", value: "\(Int(sys))/\(Int(dia))", flag: flag)
        case "HR":
            guard let hr = n(1), (20...250).contains(hr) else { return nil }
            return Vital(label: "HR", value: "\(Int(hr))", flag: hr > 100 ? .high : (hr < 60 ? .low : nil))
        case "RR":
            guard let rr = n(1), (4...80).contains(rr) else { return nil }
            return Vital(label: "RR", value: "\(Int(rr))", flag: rr > 20 ? .high : (rr < 12 ? .low : nil))
        case "Temp":
            guard let t = n(1), let scale = groups.indices.contains(2) ? groups[2]?.lowercased() : nil else { return nil }
            if scale == "c" {
                guard (30...45).contains(t) else { return nil }
                return Vital(label: "Temp", value: trimmed(t) + " °C", flag: t >= 38 ? .high : (t < 35 ? .low : nil))
            }
            guard (86...113).contains(t) else { return nil }
            return Vital(label: "Temp", value: trimmed(t) + " °F", flag: t >= 100.4 ? .high : (t < 95 ? .low : nil))
        case "SpO2":
            guard let s = n(1), (40...100).contains(s) else { return nil }
            return Vital(label: "SpO2", value: "\(Int(s))%", flag: s < 94 ? .low : nil)
        default:
            return nil
        }
    }

    private static func trimmed(_ x: Double) -> String {
        x == x.rounded() ? String(Int(x)) : String(x)
    }

    /// "albumin" → "Albumin"; an abbreviation stays as written ("CRP", "HbA1c").
    private static func displayName(_ name: String) -> String {
        guard name == name.lowercased(), let first = name.first else { return name }
        return first.uppercased() + name.dropFirst()
    }

    /// High or low against AccuracyRules' reference range for the analyte in
    /// that unit; nil when the table does not know it.
    static func labFlag(name: String, value: Double, unit: String) -> Flag? {
        let key: String = name.lowercased()
        guard let analyte = AccuracyRules.labNames[key] else { return nil }
        let u: String = unit.lowercased().replacingOccurrences(of: "μ", with: "µ").replacingOccurrences(of: " ", with: "")
        guard let normal = AccuracyRules.unitAliases[u], let r = AccuracyRules.labs[analyte]?[normal], r.count == 4 else { return nil }
        if value < r[2] { return .low }
        if value > r[3] { return .high }
        return nil
    }

    /// Words a sentence of observations is padded with.
    private static let filler: Set<String> = [
        "his", "her", "their", "the", "and", "with", "was", "were", "are", "room", "air", "shows", "showed",
        "show", "reveal", "reveals", "revealed", "results", "bloods", "blood", "tests", "test", "investigations",
        "labs", "laboratory", "vital", "signs", "observations", "obs", "examination", "exam", "regular",
        "irregular", "per", "minute", "min", "bpm", "mmhg", "serum", "plasma", "level", "levels", "include",
        "including", "following", "has", "had", "him", "she", "they", "rate", "heart", "respiratory",
        "pressure", "oxygen", "temperature", "pulse", "saturation", "saturations", "sats", "on", "at", "of",
        "is", "in", "are", "breaths", "beats", "degrees", "admission", "arrival", "presentation", "today",
    ]

    /// Whether, with what was read taken out, nothing is left but padding:
    /// at most two words that say something.
    static func onlyObservations(_ sentence: String, spans: [NSRange]) -> Bool {
        let ns = NSMutableString(string: sentence)
        for range in spans.sorted(by: { $0.location > $1.location }) where NSMaxRange(range) <= ns.length {
            ns.replaceCharacters(in: range, with: " ")
        }
        let words: [String] = (ns as String).lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count >= 3 && !filler.contains($0) }
        return words.count <= 2
    }
}
