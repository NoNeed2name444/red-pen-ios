import Foundation

/// The accuracy engine's rule checks: deterministic, free, offline.
///
/// A model can miss a wrong dose; a table cannot. These catch what needs no
/// judgement - a dose far outside anything the drug is given at, a lab value
/// that cannot exist in the unit it is written in, an explanation naming a
/// different answer from the key - and they are signals for the accuracy
/// model (AccuracyModel), not verdicts: a severe hit keeps an item from
/// being Verified, and with no model to ask it can Flag an item on its own.
///
/// A port of server/accuracy-rules.js, and it must agree with it: the server
/// runs these for the training set, the phone runs them offline, and the
/// same item has to get the same hits in both places. The tables are the
/// server's, written out below as text (tests/accuracy.test.mjs compares them).
enum AccuracyRules {

    struct Hit: Codable, Hashable {
        var rule: String
        /// "severe" or "minor"
        var severity: String
        var detail: String

        var isSevere: Bool { severity == "severe" }
    }

    // MARK: the tables (the same as the server's)

    // BEGIN DRUGS
    static let drugTable: String = """
        paracetamol=325:4000;acetaminophen=325:4000;ibuprofen=200:3200;aspirin=75:4000;naproxen=220:1500;
        amoxicillin=125:6000;co-amoxiclav=250:3600;ceftriaxone=250:4000;vancomycin=125:4000;
        ciprofloxacin=100:1500;doxycycline=50:200;azithromycin=250:2000;clarithromycin=250:1000;
        metronidazole=200:4000;nitrofurantoin=50:400;trimethoprim=100:400;benzylpenicillin=300:14400;
        flucloxacillin=250:8000;metformin=250:3000;gliclazide=30:320;atorvastatin=10:80;simvastatin=5:80;
        rosuvastatin=5:40;pravastatin=10:80;lisinopril=2.5:80;ramipril=1.25:10;enalapril=2.5:40;
        losartan=12.5:150;candesartan=2:32;amlodipine=2.5:10;nifedipine=5:120;bisoprolol=1.25:20;
        metoprolol=5:400;atenolol=25:100;propranolol=10:320;furosemide=10:1000;bumetanide=0.5:10;
        spironolactone=12.5:400;bendroflumethiazide=1.25:5;hydrochlorothiazide=6.25:100;warfarin=0.5:15;
        apixaban=2.5:20;rivaroxaban=2.5:30;dabigatran=75:300;clopidogrel=75:600;ticagrelor=60:180;
        digoxin=0.0625:1.5;levothyroxine=0.0125:0.3;carbimazole=5:60;propylthiouracil=50:1200;morphine=1:200;
        oxycodone=2.5:160;codeine=15:240;tramadol=50:400;fentanyl=0.012:0.2;naloxone=0.04:10;
        adrenaline=0.01:1;epinephrine=0.01:1;atropine=0.1:5;adenosine=3:18;amiodarone=50:1200;
        prednisolone=1:100;prednisone=1:100;methylprednisolone=4:1000;dexamethasone=0.5:40;
        hydrocortisone=5:500;diazepam=1:40;lorazepam=0.25:10;midazolam=0.5:20;haloperidol=0.5:20;
        olanzapine=2.5:20;quetiapine=25:800;sertraline=25:200;fluoxetine=10:80;citalopram=10:40;
        amitriptyline=10:150;lithium=100:2400;phenytoin=50:2000;sodium valproate=100:2500;
        levetiracetam=250:3000;carbamazepine=100:1600;lamotrigine=25:500;ondansetron=2:32;
        metoclopramide=5:30;omeprazole=10:80;lansoprazole=15:60;allopurinol=50:900;colchicine=0.3:2;
        alteplase=0.5:100;tranexamic acid=250:4000;enoxaparin=20:200;salbutamol=0.1:10;albuterol=0.1:10;
        ipratropium=0.02:0.5;magnesium sulfate=1000:6000;magnesium sulphate=1000:6000;
        calcium gluconate=500:3000;acetazolamide=125:1000;mannitol=12500:100000;sildenafil=20:100;
        finasteride=1:5;tamsulosin=0.4:0.8;methotrexate=2.5:30;
        """
    // END DRUGS

    // BEGIN LABS
    static let labTable: String = """
        sodium|mmol~l=95:195:135:145;sodium|meq~l=95:195:135:145;potassium|mmol~l=1.2:10:3.5:5.3;
        potassium|meq~l=1.2:10:3.5:5.3;chloride|mmol~l=60:150:96:107;chloride|meq~l=60:150:96:107;
        bicarbonate|mmol~l=2:55:22:29;bicarbonate|meq~l=2:55:22:29;calcium|mg~dl=3:20:8.5:10.5;
        calcium|mmol~l=0.8:5:2.1:2.6;magnesium|mg~dl=0.4:12:1.7:2.4;magnesium|mmol~l=0.15:5:0.7:1.05;
        magnesium|meq~l=0.3:10:1.4:2.1;glucose|mg~dl=10:2500:70:100;glucose|mmol~l=0.5:140:3.9:5.6;
        creatinine|mg~dl=0.1:30:0.6:1.3;creatinine|µmol~l=10:2700:50:115;urea|mmol~l=0.5:120:2.5:7.8;
        urea|mg~dl=1:350:7:20;bun|mg~dl=1:350:7:20;haemoglobin|g~dl=1.5:26:12:17.5;
        haemoglobin|g~l=15:260:120:175;hemoglobin|g~dl=1.5:26:12:17.5;hemoglobin|g~l=15:260:120:175;
        albumin|g~dl=0.5:7:3.5:5;albumin|g~l=5:70:35:50;bilirubin|mg~dl=0.05:60:0.1:1.2;
        bilirubin|µmol~l=1:1000:3:21;lactate|mmol~l=0.1:35:0.5:2.2;tsh|miu~l=0.001:1000:0.4:4.5;
        tsh|mu~l=0.001:1000:0.4:4.5;hba1c|%=3:20:4:5.6;hba1c|mmol~mol=10:200:20:38;paco2|mmhg=8:160:35:45;
        paco2|kpa=1:21:4.7:6;pao2|mmhg=15:700:75:100;pao2|kpa=2:95:10:13.3;ph|=6.5:7.9:7.35:7.45;
        inr|=0.5:20:0.8:1.2;
        """
    // END LABS

    /// drug -> [lowest sensible dose, highest single dose or daily total], mg.
    static let drugs: [String: [Double]] = {
        var out: [String: [Double]] = [:]
        for entry in entries(drugTable) {
            out[entry.name] = entry.values
        }
        return out
    }()

    /// analyte -> unit -> [plausible low, plausible high, reference low, reference high].
    static let labs: [String: [String: [Double]]] = {
        var out: [String: [String: [Double]]] = [:]
        for entry in entries(labTable) {
            let parts: [String] = entry.name.components(separatedBy: "|")
            guard parts.count == 2 else { continue }
            out[parts[0], default: [:]][parts[1]] = entry.values
        }
        return out
    }()

    private static func entries(_ table: String) -> [(name: String, values: [Double])] {
        let flat: String = table.replacingOccurrences(of: "\n", with: "")
        var out: [(name: String, values: [Double])] = []
        for raw in flat.components(separatedBy: ";") {
            let entry: String = raw.trimmingCharacters(in: .whitespaces)
            guard let eq = entry.lastIndex(of: "=") else { continue }
            // the tables write "/" as "~" and separate numbers with ":"
            let name: String = String(entry[..<eq]).replacingOccurrences(of: "~", with: "/")
            let values: [Double] = entry[entry.index(after: eq)...].components(separatedBy: ":").compactMap { Double($0) }
            out.append((name: name, values: values))
        }
        return out
    }

    static let unitAliases: [String: String] = [
        "mmol/l": "mmol/l", "mmol/litre": "mmol/l", "mmol/liter": "mmol/l", "meq/l": "meq/l", "mg/dl": "mg/dl",
        "µmol/l": "µmol/l", "umol/l": "µmol/l", "micromol/l": "µmol/l", "g/dl": "g/dl", "g/l": "g/l",
        "miu/l": "miu/l", "mu/l": "mu/l", "µiu/ml": "miu/l", "uiu/ml": "miu/l", "%": "%", "mmol/mol": "mmol/mol",
        "mmhg": "mmhg", "mm hg": "mmhg", "kpa": "kpa", "mg/l": "mg/l", "ng/ml": "ng/ml", "iu/l": "iu/l", "u/l": "u/l",
    ]

    static let labNames: [String: String] = [
        "sodium": "sodium", "na": "sodium", "na+": "sodium", "potassium": "potassium", "k": "potassium", "k+": "potassium",
        "chloride": "chloride", "bicarbonate": "bicarbonate", "hco3": "bicarbonate", "calcium": "calcium",
        "magnesium": "magnesium", "glucose": "glucose", "blood glucose": "glucose", "blood sugar": "glucose",
        "creatinine": "creatinine", "urea": "urea", "bun": "bun", "blood urea nitrogen": "bun",
        "haemoglobin": "haemoglobin", "hemoglobin": "hemoglobin", "hb": "haemoglobin", "albumin": "albumin",
        "bilirubin": "bilirubin", "lactate": "lactate", "tsh": "tsh", "hba1c": "hba1c", "paco2": "paco2",
        "pco2": "paco2", "pao2": "pao2", "po2": "pao2", "ph": "ph", "inr": "inr",
    ]

    static let mass: [String: Double] = [
        "g": 1000, "mg": 1, "mcg": 0.001, "µg": 0.001, "ug": 0.001, "microgram": 0.001, "micrograms": 0.001,
        "ng": 0.000001, "gram": 1000, "grams": 1000, "milligram": 1, "milligrams": 1,
    ]

    static let nonAnswers: [String] = ["all of the above", "none of the above", "all of these", "none of these"]

    // MARK: a small regex helper (NSRegularExpression works on Linux too)

    struct Found {
        var groups: [String?]
        var start: Int
        var end: Int
    }

    /// Compiled once: a library's summary runs these on every item.
    private static var compiled: [String: NSRegularExpression] = [:]
    private static let lock = NSLock()

    private static func regex(_ pattern: String, caseless: Bool) -> NSRegularExpression? {
        let key: String = (caseless ? "i:" : "c:") + pattern
        lock.lock()
        defer { lock.unlock() }
        if let hit = compiled[key] { return hit }
        let options: NSRegularExpression.Options = caseless ? [.caseInsensitive] : []
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        if compiled.count > 600 { compiled.removeAll() }
        compiled[key] = re
        return re
    }

    static func find(_ pattern: String, in text: String, caseless: Bool = false) -> [Found] {
        guard let re = regex(pattern, caseless: caseless) else { return [] }
        let ns = text as NSString
        let all = re.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        return all.map { m in
            var groups: [String?] = []
            for g in 0..<m.numberOfRanges {
                let r: NSRange = m.range(at: g)
                groups.append(r.location == NSNotFound ? nil : ns.substring(with: r))
            }
            return Found(groups: groups, start: m.range.location, end: m.range.location + m.range.length)
        }
    }

    static func matches(_ pattern: String, _ text: String) -> Bool {
        !find(pattern, in: text).isEmpty
    }

    static func esc(_ s: String) -> String { NSRegularExpression.escapedPattern(for: s) }

    static func number(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: "")) ?? 0 }

    private static func tail(_ text: String, from utf16Offset: Int) -> String {
        let ns = text as NSString
        guard utf16Offset < ns.length else { return "" }
        return ns.substring(from: utf16Offset)
    }

    // MARK: reading doses and values

    struct Dose: Hashable { var drug: String; var mg: Double; var said: String }
    struct LabValue: Hashable { var analyte: String; var name: String; var value: Double; var unit: String; var said: String }

    static let doseUnit: String = "(g|mg|mcg|µg|ug|ng|micrograms?|milligrams?|grams?)"

    static func doses(_ text: String) -> [Dose] {
        let t: String = text.lowercased().replacingOccurrences(of: "μ", with: "µ")
        var out: [Dose] = []
        let perRate: String = "^\\s*(/|per\\s+)(kg|min|minute|h|hr|hour|m2|m²)"
        for drug in drugs.keys.sorted() where t.contains(drug) {
            let name: String = esc(drug)
            let after: String = "\\b" + name + "\\b[^.;\\n\\d]{0,25}?(\\d+(?:[.,]\\d+)?)\\s*" + doseUnit + "\\b"
            let before: String = "(\\d+(?:[.,]\\d+)?)\\s*" + doseUnit + "\\b\\s+(?:of\\s+)?(?:iv\\s+|oral\\s+|im\\s+)?" + name + "\\b"
            for (pattern, isAfter) in [(after, true), (before, false)] {
                for m in find(pattern, in: t) {
                    if isAfter && matches(perRate, tail(t, from: m.end)) { continue }
                    guard let value = m.groups[1], let unit = m.groups[2], let factor = mass[unit] else { continue }
                    let said: String = (m.groups[0] ?? "").trimmingCharacters(in: .whitespaces)
                    out.append(Dose(drug: drug, mg: number(value) * factor, said: said))
                }
            }
        }
        return out
    }

    private static func alternation(_ keys: [String]) -> String {
        keys.sorted { $0.count != $1.count ? $0.count > $1.count : $0 < $1 }.map(esc).joined(separator: "|")
    }

    static func labValues(_ text: String) -> [LabValue] {
        let t: String = text.lowercased().replacingOccurrences(of: "μ", with: "µ")
        let names: String = alternation(Array(labNames.keys))
        let units: String = alternation(Array(unitAliases.keys))
        let pattern: String = "(?:^|[^a-z0-9])(" + names + ")(?![a-z0-9])\\s*(?:level|concentration|of|is|was|:|=|\\s)*\\s*(\\d+(?:\\.\\d+)?)\\s*(" + units + ")?(?![a-z0-9/])"
        var out: [LabValue] = []
        for m in find(pattern, in: t) {
            guard let name = m.groups[1], let analyte = labNames[name], let raw = m.groups[2] else { continue }
            let unit: String = m.groups[3].flatMap { unitAliases[$0] } ?? ""
            let unitless: Bool = labs[analyte]?[""] != nil
            if unit.isEmpty && !unitless { continue }
            if unit.isEmpty && name.count <= 2 && analyte != "ph" { continue }
            let said: String = (m.groups[0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            out.append(LabValue(analyte: analyte, name: name, value: number(raw), unit: unit, said: said))
        }
        return out
    }

    private struct StatedRange { var analyte: String; var lo: Double; var hi: Double; var unit: String }

    private static func statedRanges(_ text: String) -> [StatedRange] {
        let t: String = text.lowercased().replacingOccurrences(of: "μ", with: "µ")
            .replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "—", with: "-")
        let names: String = alternation(Array(labNames.keys))
        let units: String = alternation(Array(unitAliases.keys))
        let pattern: String = "(?:normal|reference)\\s+(?:serum\\s+|plasma\\s+|blood\\s+)?(" + names + ")(?![a-z0-9])[^\\d\\n]{0,25}?(\\d+(?:\\.\\d+)?)\\s*(?:-|to)\\s*(\\d+(?:\\.\\d+)?)\\s*(" + units + ")?"
        return find(pattern, in: t).compactMap { m in
            guard let name = m.groups[1], let analyte = labNames[name], let lo = m.groups[2], let hi = m.groups[3] else { return nil }
            let unit: String = m.groups[4].flatMap { unitAliases[$0] } ?? ""
            return StatedRange(analyte: analyte, lo: number(lo), hi: number(hi), unit: unit)
        }
    }

    // MARK: questions

    /// Which option the explanation plainly says is right, if any.
    static func explainedAnswer(_ explanation: String, options: [String]) -> Int? {
        let byLetter: [Found] = find("\\b(?:correct\\s+(?:answer|option|choice)|the\\s+answer|answer)\\s*(?:is|:)\\s*(?:option\\s*)?\\(?([A-J])\\)?(?![A-Za-z0-9])", in: explanation)
            + find("\\b(?:option|choice)\\s*\\(?([A-J])\\)?\\s+is\\s+(?:the\\s+)?(?:correct|right|best)\\b", in: explanation, caseless: true)
        if let last = byLetter.last, let l = last.groups[1]?.uppercased(), let scalar = l.unicodeScalars.first {
            let i: Int = Int(scalar.value) - 65
            if i >= 0 && i < options.count { return i }
        }
        let le: String = explanation.lowercased()
        for (i, option) in options.enumerated() {
            let o: String = option.lowercased().trimmingCharacters(in: .whitespaces)
            if o.count < 4 || nonAnswers.contains(o) { continue }
            let eo: String = esc(o)
            let a: String = "(?:correct|right|best)\\s+(?:answer|option|choice)\\s+is\\s+" + eo + "(?![a-z])"
            let b: String = "(?:^|[^a-z])" + eo + "\\s+is\\s+(?:the\\s+)?(?:correct|right|best)\\s+(?:answer|option|choice)"
            if matches(a + "|" + b, le) { return i }
        }
        return nil
    }

    private static func normalised(_ s: String) -> String {
        let lower: String = s.lowercased()
        var out: String = ""
        var gap = false
        for ch in lower {
            let keep: Bool = ("a"..."z").contains(ch) || ("0"..."9").contains(ch) || ch == "%"
            if keep {
                if gap && !out.isEmpty { out.append(" ") }
                out.append(ch)
                gap = false
            } else {
                gap = true
            }
        }
        return out
    }

    private static func fmt(_ x: Double) -> String {
        if x >= 1 {
            let r: Double = (x * 100).rounded() / 100
            return r == r.rounded() ? String(Int(r)) : String(r)
        }
        return String(x)
    }

    static let negatedStem: String = "\\b(?:NOT|EXCEPT)\\b|\\bleast\\s+likely\\b|\\bis\\s+false\\b|\\bincorrect\\s+statement\\b|\\bfalse\\s+statement\\b"

    /// Every rule hit for one item.
    static func hits(_ item: AccuracyItem) -> [Hit] {
        var out: [Hit] = []
        func add(_ rule: String, _ severity: String, _ detail: String) {
            out.append(Hit(rule: rule, severity: severity, detail: String(detail.prefix(160))))
        }
        if item.kind == .mcq { questionHits(item, add: add) }
        let text: String = item.checkedText

        for d in doses(text) {
            guard let range = drugs[d.drug], range.count == 2 else { continue }
            let lo: Double = range[0], hi: Double = range[1]
            let span: String = fmt(lo) + "–" + fmt(hi) + " mg"
            if d.mg > hi * 2 || d.mg < lo / 5 {
                add("dose-range", "severe", d.said + ": outside any usual dose of " + d.drug + " (" + span + ").")
            } else if d.mg > hi || d.mg < lo {
                add("dose-range", "minor", d.said + ": unusual for " + d.drug + " (" + span + ").")
            }
        }
        for v in labValues(text) {
            guard let ranges = labs[v.analyte] else { continue }
            guard let r = ranges[v.unit] else {
                if v.unit.contains("/") && v.name.count > 2 {
                    add("lab-unit", "minor", v.said + ": " + v.analyte + " is not reported in " + v.unit + ".")
                }
                continue
            }
            if v.value < r[0] || v.value > r[1] {
                let unitName: String = v.unit.isEmpty ? "these units" : v.unit
                add("lab-implausible", "severe", v.said + ": not a possible " + v.analyte + " in " + unitName + " (wrong unit?).")
            }
        }
        for s in statedRanges(text) {
            guard let ranges = labs[s.analyte] else { continue }
            let chosen: [Double]? = ranges[s.unit] ?? (s.unit.isEmpty ? firstRange(s.analyte) : nil)
            guard let r = chosen else { continue }
            if off(s.lo, r[2]) || off(s.hi, r[3]) {
                let unit: String = s.unit.isEmpty ? "" : " " + s.unit
                let should: String = "\(fmt(r[2]))–\(fmt(r[3]))\(unit)"
                let said: String = "\(fmt(s.lo))–\(fmt(s.hi))"
                add("reference-range", "severe", "Normal \(s.analyte) is about \(should), not \(said).")
            }
        }
        let t: String = text.lowercased()
        for name in Set(labNames.values).sorted() {
            let n: String = esc(name)
            let up: Bool = matches("\\b" + n + "\\s+(?:is\\s+|are\\s+|level\\s+is\\s+)?(?:increased|elevated|raised|high)\\b", t)
            let down: Bool = matches("\\b" + n + "\\s+(?:is\\s+|are\\s+|level\\s+is\\s+)?(?:decreased|reduced|low|lowered)\\b", t)
            if up && down { add("direction-conflict", "minor", name + " is said to be both raised and lowered.") }
        }
        return out
    }

    /// A range stated with no unit is compared in the first unit the table
    /// lists for that analyte, as the server does.
    private static func firstRange(_ analyte: String) -> [Double]? {
        for line in labTable.replacingOccurrences(of: "\n", with: "").components(separatedBy: ";") {
            let entry: String = line.trimmingCharacters(in: .whitespaces)
            if entry.hasPrefix(analyte + "|"), let eq = entry.lastIndex(of: "=") {
                let head: String = String(entry[..<eq])
                let unit: String = String(head.dropFirst(analyte.count + 1)).replacingOccurrences(of: "~", with: "/")
                return labs[analyte]?[unit]
            }
        }
        return nil
    }

    private static func off(_ x: Double, _ y: Double) -> Bool {
        abs(x - y) > max(0.2 * abs(y), 1e-9)
    }

    private static func questionHits(_ item: AccuracyItem, add: (String, String, String) -> Void) {
        let options: [String] = item.options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let key: Int = item.key
        let keyed: Bool = options.indices.contains(key)
        if !keyed { add("no-key", "severe", "The keyed answer is not one of the options.") }
        var seen: [String: Int] = [:]
        for (i, o) in options.enumerated() {
            let n: String = normalised(o)
            if n.isEmpty { continue }
            if let first = seen[n] {
                let severity: String = (first == key || i == key) ? "severe" : "minor"
                add("duplicate-option", severity, "Options " + AccuracyItem.letter(first) + " and " + AccuracyItem.letter(i) + " say the same thing.")
            } else {
                seen[n] = i
            }
        }
        let kinds: [Int] = options.map { o in
            var s: String = o.lowercased()
            while let last = s.last, last == "." || last == " " { s.removeLast() }
            return nonAnswers.firstIndex(of: s) ?? -1
        }
        let nonIdx: [Int] = kinds.enumerated().filter { $0.element >= 0 }.map(\.offset)
        if nonIdx.contains(where: { $0 != options.count - 1 }) {
            add("non-answer-position", "minor", "\"All/none of the above\" is not the last option.")
        }
        let hasAll: Bool = kinds.contains { $0 == 0 || $0 == 2 }
        let hasNone: Bool = kinds.contains { $0 == 1 || $0 == 3 }
        if hasAll && hasNone { add("all-and-none", "minor", "Both \"all of the above\" and \"none of the above\" are options.") }
        guard keyed else { return }

        let keyText: String = options[key].lowercased()
        let explanation: String = item.explanation
        if let said = explainedAnswer(explanation, options: options), said != key {
            add("key-explanation-conflict", "severe", "The key is " + AccuracyItem.letter(key) + " but the explanation says " + AccuracyItem.letter(said) + ".")
        }
        let lowerExplanation: String = explanation.lowercased()
        if keyText.count >= 4 && !nonAnswers.contains(keyText) {
            let pattern: String = "(?:^|[^a-z])" + esc(keyText) + "\\s+is\\s+(?:not\\s+(?:the\\s+)?(?:correct|right|answer)|incorrect|wrong)"
            if matches(pattern, lowerExplanation) { add("key-called-wrong", "severe", "The explanation calls the keyed answer wrong.") }
        }
        let negated: Bool = matches(negatedStem, item.stem)
        if negated && keyText.count >= 4 {
            let pattern: String = esc(keyText) + "\\s+is\\s+(?:a\\s+)?(?:true|correct|recognised|recognized|typical|characteristic)\\b"
            if matches(pattern, lowerExplanation) {
                add("negation-mismatch", "minor", "The stem asks for the exception, but the explanation calls the key true.")
            }
        }
        if kinds[key] == 0 && hasNone {
            add("all-above-contradiction", "severe", "\"All of the above\" is keyed although \"none of the above\" is an option.")
        }
        let stemLabs: [LabValue] = labValues(item.stem)
        let explanationLabs: [LabValue] = labValues(explanation)
        for a in stemLabs {
            guard let b = explanationLabs.first(where: { $0.analyte == a.analyte && $0.unit == a.unit }) else { continue }
            if abs(a.value - b.value) > max(0.05 * abs(a.value), 1e-9) {
                add("numbers-disagree", "minor", "The stem gives " + a.analyte + " " + fmt(a.value) + " but the explanation says " + fmt(b.value) + ".")
                break
            }
        }
        if doses(options[key]).isEmpty,
           let keyNumber = find("^\\s*(\\d+(?:\\.\\d+)?)\\s*(mg|g|mcg|ml|units?|%)\\b", in: options[key], caseless: true).first,
           let value = keyNumber.groups[1], let unitRaw = keyNumber.groups[2] {
            let unit: String = unitRaw.lowercased()
            let inExplanation: [Double] = find("(\\d+(?:\\.\\d+)?)\\s*" + esc(unit) + "\\b", in: lowerExplanation).compactMap { $0.groups[1].map(number) }
            if let first = inExplanation.first, !inExplanation.contains(number(value)) {
                let said: String = (keyNumber.groups[0] ?? "").trimmingCharacters(in: .whitespaces)
                add("numbers-disagree", "minor", "The key says " + said + " but the explanation gives " + fmt(first) + " " + unit + ".")
            }
        }
    }

    // MARK: how much of an item its source contains

    static let stopwords: Set<String> = [
        "the", "and", "with", "for", "that", "this", "which", "what", "most", "best", "following", "patient",
        "next", "step", "from", "into", "than", "then", "there", "their", "have", "been", "were", "will", "would", "should",
        "these", "those", "also", "over", "under", "about", "after", "before", "other", "answer", "explanation", "keyed"]

    static func terms(_ text: String) -> Set<String> {
        let words: [String] = text.lowercased().split { !(("a"..."z").contains($0)) }.map(String.init)
        return Set(words.filter { $0.count >= 4 && !stopwords.contains($0) })
    }

    /// The share of the item's own vocabulary its source contains; nil with no source.
    static func sourceMatch(_ item: AccuracyItem) -> Double? {
        let source: String = item.source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return nil }
        let mine: Set<String> = terms(item.checkedText)
        guard !mine.isEmpty else { return 0 }
        let theirs: Set<String> = terms(source)
        return Double(mine.intersection(theirs).count) / Double(mine.count)
    }
}
