import Foundation

// The exam screen's own tools, as the real test interfaces have them: the
// stem cut into pieces the highlighter can mark, a basic calculator, and the
// reference ranges printed with the paper.
//
// Foundation only, so the logic can be tested on Linux.

// MARK: - highlighter

/// A stem in the pieces the highlighter marks: sentences, and a long
/// sentence's clauses, so a finding can be marked without its whole sentence.
enum StemPieces {
    /// Pieces that, joined with nothing between them, give back the stem.
    static func split(_ stem: String) -> [String] {
        var out: [String] = []
        var piece: String = ""
        let chars: [Character] = Array(stem)
        var i: Int = 0
        while i < chars.count {
            let c: Character = chars[i]
            piece.append(c)
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            let ends: Bool = isBreak(c, next: next, length: piece.count)
            if ends {
                // the space after it goes with this piece
                while i + 1 < chars.count, chars[i + 1] == " " {
                    piece.append(" ")
                    i += 1
                }
                out.append(piece)
                piece = ""
            }
            i += 1
        }
        if !piece.isEmpty { out.append(piece) }
        return out
    }

    private static func isBreak(_ c: Character, next: Character?, length: Int) -> Bool {
        let spaceNext: Bool = next == nil || next == " " || next == "\n"
        if c == "\n" { return true }
        if (c == "." || c == "?" || c == "!") && spaceNext { return true }
        // a clause of a long sentence
        if (c == "," || c == ";") && next == " " && length >= 40 { return true }
        return false
    }
}

// MARK: - calculator

/// The exam's basic four-function calculator.
struct ExamCalculator: Hashable {
    enum Op: String, CaseIterable { case add = "+", subtract = "\u{2212}", multiply = "\u{00D7}", divide = "\u{00F7}" }

    private(set) var display: String = "0"
    private var stored: Double?
    private var pending: Op?
    /// True once a result or an operator is showing: the next digit starts afresh.
    private var fresh: Bool = true

    var value: Double { Double(display) ?? 0 }
    var pendingOp: Op? { pending }

    mutating func digit(_ d: Int) {
        guard (0...9).contains(d) else { return }
        if fresh || display == "0" || display == "Error" {
            display = String(d)
            fresh = false
        } else if display.count < 14 {
            display += String(d)
        }
    }

    mutating func dot() {
        if fresh || display == "Error" {
            display = "0."
            fresh = false
        } else if !display.contains(".") {
            display += "."
        }
    }

    mutating func negate() {
        guard display != "0", display != "Error" else { return }
        if display.hasPrefix("-") { display.removeFirst() } else { display = "-" + display }
    }

    mutating func percent() {
        display = Self.format(value / 100)
        fresh = true
    }

    mutating func op(_ next: Op) {
        if let pending, let stored, !fresh {
            display = Self.format(Self.apply(pending, stored, value))
        }
        stored = display == "Error" ? nil : value
        pending = display == "Error" ? nil : next
        fresh = true
    }

    mutating func equals() {
        guard let pending, let stored else { return }
        display = Self.format(Self.apply(pending, stored, value))
        self.pending = nil
        self.stored = nil
        fresh = true
    }

    mutating func clear() {
        display = "0"
        stored = nil
        pending = nil
        fresh = true
    }

    static func apply(_ op: Op, _ a: Double, _ b: Double) -> Double {
        switch op {
        case .add: return a + b
        case .subtract: return a - b
        case .multiply: return a * b
        case .divide: return b == 0 ? .nan : a / b
        }
    }

    /// Up to ten significant figures, no trailing zeros; "Error" for a
    /// division by zero.
    static func format(_ x: Double) -> String {
        guard x.isFinite else { return "Error" }
        if x == x.rounded(), abs(x) < 1e15 { return String(Int64(x)) }
        var text: String = String(format: "%.10g", x)
        if text.contains("."), !text.contains("e") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text
    }
}

// MARK: - reference ranges

/// One laboratory value's typical adult reference range, in SI units and in
/// US conventional units.
struct LabRange: Hashable, Identifiable {
    var group: String
    var name: String
    var si: String
    var us: String
    var id: String { group + "/" + name }

    func value(conventional: Bool) -> String { conventional ? us : si }
}

/// Which units a track reads its papers in.
enum LabUnits {
    /// USMLE papers use US conventional units (with SI alongside); the UK
    /// exams use SI.
    static func conventional(for track: ExamTrack) -> Bool { track == .usmle }
}

/// The reference ranges, as a paper prints them at the back. Typical adult
/// values; a laboratory's own ranges vary a little and the paper's own list
/// always wins.
enum LabRanges {
    static let caveat: String = "Typical adult reference ranges. Laboratories differ slightly; in the exam, use the ranges the paper gives."

    static func r(_ group: String, _ name: String, _ si: String, _ us: String) -> LabRange {
        LabRange(group: group, name: name, si: si, us: us)
    }

    static let all: [LabRange] = [chemistry, liver, haematology, coagulation, gases, endocrine, lipids, csf].flatMap { $0 }

    static let groups: [String] = ["Urea and electrolytes", "Liver and bone", "Haematology", "Coagulation",
                                   "Blood gases", "Endocrine", "Lipids and glucose", "CSF"]

    static let chemistry: [LabRange] = [
        r("Urea and electrolytes", "Sodium", "135\u{2013}145 mmol/L", "135\u{2013}145 mEq/L"),
        r("Urea and electrolytes", "Potassium", "3.5\u{2013}5.0 mmol/L", "3.5\u{2013}5.0 mEq/L"),
        r("Urea and electrolytes", "Chloride", "98\u{2013}106 mmol/L", "98\u{2013}106 mEq/L"),
        r("Urea and electrolytes", "Bicarbonate", "22\u{2013}28 mmol/L", "22\u{2013}28 mEq/L"),
        r("Urea and electrolytes", "Urea (BUN in the US)", "2.5\u{2013}7.8 mmol/L", "BUN 7\u{2013}20 mg/dL"),
        r("Urea and electrolytes", "Creatinine", "53\u{2013}106 \u{00B5}mol/L", "0.6\u{2013}1.2 mg/dL"),
        r("Urea and electrolytes", "Magnesium", "0.7\u{2013}1.0 mmol/L", "1.7\u{2013}2.4 mg/dL"),
        r("Urea and electrolytes", "Urate", "180\u{2013}480 \u{00B5}mol/L", "3.0\u{2013}8.0 mg/dL"),
        r("Urea and electrolytes", "Osmolality (serum)", "275\u{2013}295 mOsm/kg", "275\u{2013}295 mOsm/kg"),
        r("Urea and electrolytes", "Lactate", "0.5\u{2013}2.2 mmol/L", "4.5\u{2013}19.8 mg/dL"),
        r("Urea and electrolytes", "C-reactive protein", "<5 mg/L", "<0.5 mg/dL"),
        r("Urea and electrolytes", "Amylase", "25\u{2013}125 U/L", "25\u{2013}125 U/L")
    ]

    static let liver: [LabRange] = [
        r("Liver and bone", "Bilirubin (total)", "3\u{2013}17 \u{00B5}mol/L", "0.2\u{2013}1.0 mg/dL"),
        r("Liver and bone", "ALT", "10\u{2013}40 U/L", "10\u{2013}40 U/L"),
        r("Liver and bone", "AST", "10\u{2013}40 U/L", "10\u{2013}40 U/L"),
        r("Liver and bone", "Alkaline phosphatase", "30\u{2013}130 U/L", "25\u{2013}100 U/L"),
        r("Liver and bone", "Albumin", "35\u{2013}50 g/L", "3.5\u{2013}5.0 g/dL"),
        r("Liver and bone", "Total protein", "60\u{2013}80 g/L", "6.0\u{2013}8.0 g/dL"),
        r("Liver and bone", "Calcium (adjusted)", "2.20\u{2013}2.60 mmol/L", "8.8\u{2013}10.4 mg/dL"),
        r("Liver and bone", "Phosphate", "0.8\u{2013}1.5 mmol/L", "2.5\u{2013}4.5 mg/dL")
    ]

    static let haematology: [LabRange] = [
        r("Haematology", "Haemoglobin, men", "130\u{2013}180 g/L", "13.5\u{2013}17.5 g/dL"),
        r("Haematology", "Haemoglobin, women", "115\u{2013}160 g/L", "12.0\u{2013}16.0 g/dL"),
        r("Haematology", "White cells", "4.0\u{2013}11.0 \u{00D7}10\u{2079}/L", "4.0\u{2013}11.0 \u{00D7}10\u{00B3}/\u{00B5}L"),
        r("Haematology", "Neutrophils", "2.0\u{2013}7.5 \u{00D7}10\u{2079}/L", "2.0\u{2013}7.5 \u{00D7}10\u{00B3}/\u{00B5}L"),
        r("Haematology", "Lymphocytes", "1.0\u{2013}4.0 \u{00D7}10\u{2079}/L", "1.0\u{2013}4.0 \u{00D7}10\u{00B3}/\u{00B5}L"),
        r("Haematology", "Platelets", "150\u{2013}400 \u{00D7}10\u{2079}/L", "150\u{2013}400 \u{00D7}10\u{00B3}/\u{00B5}L"),
        r("Haematology", "MCV", "80\u{2013}100 fL", "80\u{2013}100 fL"),
        r("Haematology", "Reticulocytes", "0.5\u{2013}2.5%", "0.5\u{2013}2.5%"),
        r("Haematology", "Ferritin", "15\u{2013}300 \u{00B5}g/L", "15\u{2013}300 ng/mL"),
        r("Haematology", "Serum iron", "10\u{2013}30 \u{00B5}mol/L", "60\u{2013}170 \u{00B5}g/dL"),
        r("Haematology", "Vitamin B12", "150\u{2013}660 pmol/L", "200\u{2013}900 pg/mL"),
        r("Haematology", "ESR", "Men <15, women <20 mm/h", "Men <15, women <20 mm/h")
    ]

    static let coagulation: [LabRange] = [
        r("Coagulation", "Prothrombin time", "11\u{2013}13.5 s", "11\u{2013}13.5 s"),
        r("Coagulation", "INR", "0.8\u{2013}1.2 (2\u{2013}3 on warfarin for most indications)", "0.8\u{2013}1.2 (2\u{2013}3 on warfarin for most indications)"),
        r("Coagulation", "APTT", "25\u{2013}35 s", "25\u{2013}35 s"),
        r("Coagulation", "Fibrinogen", "2\u{2013}4 g/L", "200\u{2013}400 mg/dL"),
        r("Coagulation", "D-dimer", "<0.5 mg/L FEU", "<500 ng/mL FEU")
    ]

    static let gases: [LabRange] = [
        r("Blood gases", "pH (arterial)", "7.35\u{2013}7.45", "7.35\u{2013}7.45"),
        r("Blood gases", "PaO\u{2082} (on air)", "10\u{2013}13 kPa", "75\u{2013}100 mmHg"),
        r("Blood gases", "PaCO\u{2082}", "4.7\u{2013}6.0 kPa", "35\u{2013}45 mmHg"),
        r("Blood gases", "Bicarbonate", "22\u{2013}28 mmol/L", "22\u{2013}28 mEq/L"),
        r("Blood gases", "Base excess", "\u{2212}2 to +2 mmol/L", "\u{2212}2 to +2 mEq/L"),
        r("Blood gases", "Anion gap (Na \u{2212} [Cl + HCO\u{2083}])", "8\u{2013}12 mmol/L", "8\u{2013}12 mEq/L")
    ]

    static let endocrine: [LabRange] = [
        r("Endocrine", "TSH", "0.4\u{2013}4.0 mU/L", "0.4\u{2013}4.0 \u{00B5}U/mL"),
        r("Endocrine", "Free T4", "12\u{2013}22 pmol/L", "0.9\u{2013}1.7 ng/dL"),
        r("Endocrine", "Cortisol (9 am)", "140\u{2013}630 nmol/L", "5\u{2013}23 \u{00B5}g/dL"),
        r("Endocrine", "PTH", "1.1\u{2013}6.9 pmol/L", "10\u{2013}65 pg/mL"),
        r("Endocrine", "25-OH vitamin D", ">50 nmol/L sufficient, <25 deficient", "20\u{2013}50 ng/mL"),
        r("Endocrine", "HbA1c", "20\u{2013}41 mmol/mol; diabetes \u{2265}48", "4.0\u{2013}5.6%; diabetes \u{2265}6.5%")
    ]

    static let lipids: [LabRange] = [
        r("Lipids and glucose", "Glucose (fasting)", "3.9\u{2013}5.5 mmol/L", "70\u{2013}99 mg/dL"),
        r("Lipids and glucose", "Total cholesterol (desirable)", "<5.0 mmol/L", "<200 mg/dL"),
        r("Lipids and glucose", "LDL cholesterol (desirable)", "<3.0 mmol/L", "<130 mg/dL"),
        r("Lipids and glucose", "HDL cholesterol", ">1.0 mmol/L", ">40 mg/dL"),
        r("Lipids and glucose", "Triglycerides (fasting)", "<1.7 mmol/L", "<150 mg/dL")
    ]

    static let csf: [LabRange] = [
        r("CSF", "Opening pressure", "10\u{2013}20 cmH\u{2082}O", "10\u{2013}20 cmH\u{2082}O"),
        r("CSF", "Protein", "0.15\u{2013}0.45 g/L", "15\u{2013}45 mg/dL"),
        r("CSF", "Glucose", "2.8\u{2013}4.2 mmol/L (about 60% of blood)", "50\u{2013}75 mg/dL (about 60% of blood)"),
        r("CSF", "White cells", "<5 cells/\u{00B5}L", "<5 cells/\u{00B5}L")
    ]

    /// The ranges matching `query` in the name or group, in paper order.
    static func search(_ query: String) -> [LabRange] {
        let q: String = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { $0.name.lowercased().contains(q) || $0.group.lowercased().contains(q) }
    }
}
