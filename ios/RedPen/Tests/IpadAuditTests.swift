import Foundation

// The iPad audit (T0140), read from the sources and the workflows:
//  - pointer: every Button and NavigationLink in the core screens shows the
//    pointer's highlight, its own (.hoverEffect) or a Ward style's that
//    draws one; the system's own buttons (menus, alerts, confirmation
//    dialogs, context menus, toolbars, swipe actions, List, Form and Section
//    rows) are the system's;
//  - keyboard: each core screen's primary action has a keyboard shortcut;
//  - sheets: every .sheet, .fullScreenCover and .popover in the core screens
//    takes the page colour (wardSheet(), or presentationBackground) - the
//    system share sheet aside;
//  - the preview's four orientations, and the workflows' iPad passes: four
//    orientations, the Stage Manager windows, the size picker, the window
//    table, the rotation-state pass.
// Run from the repository root (tools/swift_suites.py does).

var failures = 0
func check(_ name: String, _ result: Bool, _ detail: String = "") {
    print("\(result ? "PASS" : "FAIL") \(name)\(result || detail.isEmpty ? "" : ": " + detail)")
    if !result { failures += 1 }
}

func read(_ path: String) -> String {
    (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
}

let features = "ios/RedPen/Features/"
let core: [String] = [
    "Library/LibraryView.swift", "Library/LibraryChrome.swift", "Library/LibrarySheets.swift",
    "Library/WardHome.swift", "Library/StudyCategory.swift", "Library/NewSetDock.swift",
    "Library/NewSetView.swift", "MCQ/MCQQuizView.swift", "Mock/MockSittingView.swift",
    "Anki/AnkiReviewView.swift", "Book/BookReaderView.swift", "Recall/DrawRecallView.swift",
    "OSCE/OsceReviewView.swift", "Cases/CaseListView.swift", "Notes/IdeasView.swift",
    "Support/SupportCenter.swift",
].map { features + $0 }

// MARK: a small reader of Swift source: brackets, strings and comments

struct Source {
    let c: [Character]
    init(_ text: String) { c = Array(text) }

    func at(_ i: Int, _ s: String) -> Bool {
        let a = Array(s)
        guard i >= 0, i + a.count <= c.count else { return false }
        return Array(c[i..<(i + a.count)]) == a
    }

    func skipSpace(_ start: Int) -> Int {
        var i = start
        while i < c.count {
            if c[i].isWhitespace { i += 1 } else if at(i, "//") {
                while i < c.count && c[i] != "\n" { i += 1 }
            } else { break }
        }
        return i
    }

    /// The index just past the bracket that closes the one at `start`.
    func close(_ start: Int) -> Int {
        var depth = 0, i = start
        while i < c.count {
            if at(i, "\"\"\"") {
                i += 3
                while i < c.count && !at(i, "\"\"\"") { i += 1 }
                i += 3
                continue
            }
            if c[i] == "\"" {
                i += 1
                while i < c.count && c[i] != "\"" && c[i] != "\n" {
                    if c[i] == "\\" { i += 1 }
                    i += 1
                }
                i += 1
                continue
            }
            if at(i, "//") {
                while i < c.count && c[i] != "\n" { i += 1 }
                continue
            }
            if "({[".contains(c[i]) { depth += 1 }
            if ")}]".contains(c[i]) {
                depth -= 1
                if depth == 0 { return i + 1 }
            }
            i += 1
        }
        return c.count
    }

    func isName(_ ch: Character) -> Bool { ch.isLetter || ch.isNumber || ch == "_" }

    /// Each place `word` stands as a whole name (not after a dot or a letter).
    func names(_ word: String, dotted: Bool = false) -> [Int] {
        var out: [Int] = []
        let w = Array(word)
        var i = 0
        while i + w.count <= c.count {
            if Array(c[i..<(i + w.count)]) == w {
                let before: Character? = i > 0 ? c[i - 1] : nil
                let after: Character? = i + w.count < c.count ? c[i + w.count] : nil
                let startOK = dotted ? true : !(before.map { isName($0) || $0 == "." } ?? false)
                if startOK && !(after.map(isName) ?? false) { out.append(i) }
            }
            i += 1
        }
        return out
    }

    /// From just past a callee's name: its arguments, its trailing
    /// closures (`label: {` too), then every `.modifier(...)` after it.
    func statementEnd(_ from: Int) -> Int {
        var i = skipSpace(from)
        if i < c.count && c[i] == "(" { i = close(i) }
        while true {
            let j = skipSpace(i)
            if j < c.count && c[j] == "{" { i = close(j); continue }
            // `label: {`
            var k = j
            while k < c.count && isName(c[k]) { k += 1 }
            if k > j {
                let colon = skipSpace(k)
                if colon < c.count && c[colon] == ":" {
                    let brace = skipSpace(colon + 1)
                    if brace < c.count && c[brace] == "{" { i = close(brace); continue }
                }
            }
            break
        }
        while true {
            let j = skipSpace(i)
            guard j < c.count, c[j] == "." else { break }
            var k = j + 1
            while k < c.count && isName(c[k]) { k += 1 }
            guard k > j + 1 else { break }
            i = k
            let p = skipSpace(i)
            if p < c.count && c[p] == "(" { i = close(p) }
            let b = skipSpace(i)
            if b < c.count && c[b] == "{" { i = close(b) }
        }
        return i
    }

    func text(_ a: Int, _ b: Int) -> String { String(c[a..<min(b, c.count)]) }
    func line(_ i: Int) -> Int { c[0..<i].filter { $0 == "\n" }.count + 1 }
}

// MARK: pointer

/// Where buttons are the system's: what is inside one of these is skipped.
let systemHolders: [(String, Bool)] = [
    ("alert", true), ("confirmationDialog", true), ("contextMenu", true), ("toolbar", true),
    ("swipeActions", true), ("studyMoreMenu", true),
    ("Menu", false), ("ToolbarItem", false), ("ToolbarItemGroup", false),
    ("List", false), ("Form", false), ("Section", false),
]
/// Builders whose buttons only ever go into a menu or a confirmation dialog.
let menuBuilders = ["func moveChoices", "var examMenuItem"]
/// What gives the pointer's highlight: the modifier, or a Ward style that
/// draws it (WardControls.swift, Theme.swift's PressableRowStyle).
let hoverMarks = [".hoverEffect(", ".wardPrimary", ".wardSecondary", ".wardDestructive", ".wardCompact",
                  ".wardQuiet", ".wardCircle", "WardButtonStyle", "WardChipButtonStyle", "WardCircleButtonStyle",
                  ".bigPrimary", ".bigSecondary", ".bigCompanion", "BigButtonStyle", ".pressableRow",
                  "PressableRowStyle"]

var buttons = 0, uncovered: [String] = []
for path in core {
    let text = read(path)
    check("\(path) read", !text.isEmpty)
    let s = Source(text)
    var spans: [(Int, Int)] = []
    for (word, dotted) in systemHolders {
        for i in s.names(dotted ? "." + word : word, dotted: dotted) {
            var k = s.skipSpace(i + word.count + (dotted ? 1 : 0))
            while k < s.c.count && (s.c[k] == "(" || s.c[k] == "{") {
                let e = s.close(k)
                spans.append((k, e))
                k = s.skipSpace(e)
            }
        }
    }
    for builder in menuBuilders {
        for i in s.names(builder.components(separatedBy: " ")[1]) where s.text(max(0, i - 5), i).hasSuffix(builder.components(separatedBy: " ")[0] + " ") {
            var k = i
            while k < s.c.count && s.c[k] != "{" { k += 1 }
            spans.append((k, s.close(k)))
        }
    }
    for word in ["Button", "NavigationLink"] {
        for i in s.names(word) {
            let next = s.skipSpace(i + word.count)
            guard next < s.c.count, s.c[next] == "(" || s.c[next] == "{" else { continue }
            if spans.contains(where: { $0.0 < i && i < $0.1 }) { continue }
            buttons += 1
            let statement = s.text(i, s.statementEnd(i + word.count))
            if !hoverMarks.contains(where: { statement.contains($0) }) {
                uncovered.append("\(path):\(s.line(i))")
            }
        }
    }
}
check("pointer: found the core screens' buttons", buttons > 40, "\(buttons)")
check("pointer: every core button has the highlight (\(buttons) buttons)", uncovered.isEmpty,
      uncovered.joined(separator: ", "))
print("pointer coverage: \(buttons - uncovered.count) of \(buttons) buttons")

// the shared styles really draw it
let controls = read("ios/RedPen/Shared/Ward/WardControls.swift")
check("WardButtonStyle, chips and circles draw the highlight",
      controls.components(separatedBy: ".hoverEffect(.highlight)").count - 1 >= 3)
let theme = read("ios/RedPen/Shared/Theme.swift")
if let r = theme.range(of: "private struct PressableRowFace") {
    let body = String(theme[r.lowerBound...].prefix(400))
    check("PressableRowStyle draws the highlight", body.contains(".hoverEffect(.highlight)"))
} else {
    check("PressableRowStyle found", false)
}

// MARK: keyboard: each primary action has its shortcut

/// (file, text in the action's button, the shortcut it must have)
let primary: [(String, String, String)] = [
    ("Library/LibraryView.swift", "Label(\"New set\"", ".keyboardShortcut(\"n\", modifiers: .command)"),
    ("Library/StudyCategory.swift", "DockItemFace(symbol: category.symbol", ".keyboardShortcut(CategoryDock.digit(number), modifiers: .command)"),
    ("Library/NewSetView.swift", "Label(saveTitle", ".keyboardShortcut(\"s\", modifiers: .command)"),
    ("Library/NewSetDock.swift", "", ".keyboardShortcut(.defaultAction)"),
    ("MCQ/MCQQuizView.swift", "Label(title, systemImage: symbol)", ".keyboardShortcut(.return, modifiers: [])"),
    ("Mock/MockSittingView.swift", "Label(nextTitle", ".keyboardShortcut(.return, modifiers: [])"),
    ("Anki/AnkiReviewView.swift", "", ".keyboardShortcut(.return, modifiers: [])"),
    ("Book/BookReaderView.swift", "Label(\"Done\", systemImage: \"checkmark\")", ".keyboardShortcut(.return, modifiers: [])"),
    ("Recall/DrawRecallView.swift", "", ".keyboardShortcut(.return, modifiers: [])"),
    ("OSCE/OsceReviewView.swift", "Label(\"I got it\"", ".keyboardShortcut(.return, modifiers: [])"),
]
for (file, anchor, shortcut) in primary {
    let text = read(features + file)
    guard !anchor.isEmpty else {
        check("keyboard: \(file) has \(shortcut)", text.contains(shortcut))
        continue
    }
    guard let a = text.range(of: anchor) else {
        check("keyboard: \(file) has its primary action (\(anchor))", false)
        continue
    }
    // within the same button: before the next Button starts
    let after = String(text[a.upperBound...].prefix(2000))
    let nextButton = after.range(of: #"(?<![A-Za-z.])Button\s*[({]"#, options: .regularExpression)?.lowerBound
        ?? after.endIndex
    check("keyboard: \(file)'s primary action has \(shortcut)", after[..<nextButton].contains(shortcut))
}
check("keyboard: the quiz's options answer to their digits (KeyboardShortcuts.swift)",
      read("ios/RedPen/Shared/KeyboardShortcuts.swift").contains("keyboardShortcut(KeyEquivalent(digit), modifiers: [])"))
print("keyboard: \(primary.count) primary actions checked")

// MARK: sheets in the page colour

var sheets = 0, bare: [String] = []
for path in core {
    let s = Source(read(path))
    for word in ["sheet", "fullScreenCover", "popover"] {
        for i in s.names("." + word, dotted: true) {
            let open = i + word.count + 1
            guard open < s.c.count, s.c[open] == "(" else { continue }
            sheets += 1
            let args = s.close(open)
            let k = s.skipSpace(args)
            let content = k < s.c.count && s.c[k] == "{" ? s.text(k, s.close(k)) : s.text(open, args)
            let ok = content.contains("wardSheet(") || content.contains("presentationBackground(")
                || content.contains("ShareSheet(")
            if !ok { bare.append("\(path):\(s.line(i))") }
        }
    }
}
check("sheets: found the core screens' sheets", sheets >= 20, "\(sheets)")
check("sheets: every one takes the page colour (\(sheets) sheets)", bare.isEmpty, bare.joined(separator: ", "))
let surfaces = read("ios/RedPen/Shared/Ward/WardSurfaces.swift")
check("wardSheet() is the page colour", surfaces.contains("func wardSheet() -> some View {\n        presentationBackground(Color.wardBackground)"))
print("sheet coverage: \(sheets - bare.count) of \(sheets) sheets")

// MARK: the preview turns four ways

let preview = read("ios/RedPen/Shared/PreviewLaunch.swift")
check("preview: four turns", preview.contains("case portrait, portraitUpsideDown, landscapeLeft, landscapeRight"))
check("preview: upside down by its word", preview.contains("case \"portraitupsidedown\""))
check("preview: every named turn is asked for, portrait too", preview.contains("guard let target = turn, !turned"))
check("preview: the log says where it ended", preview.contains("\"ended \\(target.rawValue)\""))
check("preview: the pretend window has the window's corner",
      preview.contains("clipShape(RoundedRectangle(cornerRadius: WardPaper.windowRadius"))

// MARK: the workflows

let ipadPreview = read(".github/workflows/ipad-preview.yml")
check("ipad-preview: all four orientations",
      ipadPreview.contains("ORIENTS=\"portrait portraitUpsideDown landscapeLeft landscapeRight\""))
check("ipad-preview: light and dark", ipadPreview.contains("for scheme in light dark"))
for screen in ["library", "name-sheet", "new-make", "quiz-checked", "mock-sitting", "anki-revealed", "book",
               "draw-recall", "osce-revealed", "cases", "ideas", "settings", "import-preview"] {
    check("ipad-preview: \(screen)", ipadPreview.contains(" \(screen) ") || ipadPreview.contains(" \(screen)\"")
          || ipadPreview.contains("\"\(screen) "))
}
check("ipad-preview: upside down counts as tall", ipadPreview.contains("tall = \"-portrait\" in f"))
check("ipad-preview: every turn's log is read", ipadPreview.contains("NOT TURNED"))

let devices = read(".github/workflows/ipad-devices.yml")
check("ipad-devices: two jobs of 40 minutes", devices.contains("timeout-minutes: 40") &&
      devices.contains("- job: A") && devices.contains("- job: B"))
for kind in ["\"mini\":", "\"base\":", "\"11\":", "\"13\":"] {
    check("ipad-devices: picks \(kind) by size", devices.contains(kind))
}
check("ipad-devices: prints the chosen list", devices.contains("picked {size}: {name}"))
check("ipad-devices: four orientations full screen",
      devices.contains("ORIENTS=\"portrait portraitUpsideDown landscapeLeft landscapeRight\""))
check("ipad-devices: the expected count first", devices.contains("expected $expected shots"))
// the window table: <size> <geometry> <mode> <w> <h>
let modes = ["sv13", "sv12", "sv23", "slideover", "smmin", "smresized"]
var rows: [(size: String, geometry: String, mode: String, w: Int, h: Int)] = []
for line in devices.components(separatedBy: "\n") {
    let f = line.split(separator: " ").map(String.init)
    if f.count == 5, ["mini", "base", "11", "13"].contains(f[0]), modes.contains(f[2]),
       let w = Int(f[3]), let h = Int(f[4]) {
        rows.append((f[0], f[1], f[2], w, h))
    }
}
check("ipad-devices: the window table has 4 sizes x 2 geometries x 6 windows", rows.count == 48, "\(rows.count)")
// the breakpoints WindowSpan uses (Theme.swift)
let slimBelow = 540, broadFrom = 700
check("WindowSpan's breakpoints are 540 and 700", theme.contains("case ..<540: self = .slim") &&
      theme.contains("case ..<700: self = .middling"))
for r in rows {
    let label = "\(r.size) \(r.geometry) \(r.mode) \(r.w)x\(r.h)"
    if r.mode == "sv13" || r.mode == "slideover" {
        check("A9: \(label) lays out as the iPhone (slim)", r.w < slimBelow)
    }
    if r.mode == "sv23" && r.geometry == "landscape" {
        check("A9: \(label) has the rail (broad)", r.w >= broadFrom)
    }
    check("window \(label) is at least 320 wide", r.w >= 320)
}

let widths = read(".github/workflows/ipad-widths.yml")
check("ipad-widths: the multitasking widths and two Stage Manager windows",
      widths.contains("default: 320 507 740 1024 800x500 420x1000"))
check("ipad-widths: both orientations", widths.contains("for orient in portrait landscapeLeft"))
check("ipad-widths: passes the window's height", widths.contains("-uiPreviewHeight"))

let design = read(".github/workflows/design-preview.yml")
check("design-preview: the iPad's rotation-state pass",
      design.contains("TEST_RUNNER_ROTATION_IPAD=1 run_tests ipad-rotation.xcresult"))
check("design-preview: its bundle in the artifact", design.contains("ipad-rotation.xcresult.zip"))

let rotation = read("ios/UITests/RotationStateUITests.swift")
check("RotationStateUITests: upside down on the iPad", rotation.contains(".portraitUpsideDown"))
check("RotationStateUITests: the width change", rotation.contains("func testWidthChangeKeepsTheQuiz") &&
      rotation.contains("func testWidthChangeKeepsTheLibrary"))
check("RotationStateUITests: 44 points after each turn", rotation.contains("func targetsFit"))

// the shipping plist keeps multitasking; only the rigs ask for full screen
let project = read("ios/project.yml")
check("project.yml keeps multitasking (no UIRequiresFullScreen)", !project.contains("UIRequiresFullScreen"))
check("project.yml: UIApplicationSupportsMultipleScenes", project.contains("UIApplicationSupportsMultipleScenes: true"))

print("\(failures) IPAD AUDIT FAILURES")
exit(failures == 0 ? 0 : 1)
