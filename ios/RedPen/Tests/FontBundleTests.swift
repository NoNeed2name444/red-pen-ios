// The app's type (owner D5): the fonts UIAppFonts registers are the files
// in Resources/Fonts, each with its OFL licence beside it; the family names
// WardType asks Font.custom for are the names those files carry; every face
// is relative to a text style (Dynamic Type) and names its weight; the
// observations stay in the system mono; and the fonts are credited.
// What only a Mac or device run shows: iOS registering the fonts and drawing
// them, at each weight of the variable axis and at the large text sizes.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

var root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
while !FileManager.default.fileExists(atPath: root.appendingPathComponent("ios/RedPen").path), root.path != "/" {
    root.deleteLastPathComponent()
}
func read(_ path: String) -> String {
    (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

/// The family name a font file carries: the typographic family (name 16)
/// when it has one, else name 1 - the name CoreText registers it under.
func familyName(_ url: URL) -> String {
    guard let data = try? Data(contentsOf: url) else { return "" }
    let b = [UInt8](data)
    func u16(_ at: Int) -> Int { at + 1 < b.count ? Int(b[at]) << 8 | Int(b[at + 1]) : 0 }
    func u32(_ at: Int) -> Int { u16(at) << 16 | u16(at + 2) }
    let tables = u16(4)
    guard let name = (0..<tables).map({ 12 + $0 * 16 }).first(where: {
        $0 + 4 <= b.count && String(bytes: b[$0..<$0 + 4], encoding: .ascii) == "name"
    }) else { return "" }
    let at = u32(name + 8)
    let count = u16(at + 2)
    let strings = at + u16(at + 4)
    var found: [Int: String] = [:]
    for i in 0..<count {
        let r = at + 6 + i * 12
        let id = u16(r + 6)
        guard u16(r) == 3, u16(r + 4) == 0x409, id == 1 || id == 16 else { continue }
        let start = strings + u16(r + 10), end = start + u16(r + 8)
        guard end <= b.count else { continue }
        found[id] = String(bytes: b[start..<end], encoding: .utf16BigEndian)
    }
    return found[16] ?? found[1] ?? ""
}

// MARK: UIAppFonts names the bundled files

let project = read("ios/project.yml")
let lines = project.components(separatedBy: "\n")
var appFonts: [String] = []
if let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "UIAppFonts:" }) {
    for line in lines[(start + 1)...] {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("- ") else { break }
        appFonts.append(String(t.dropFirst(2)))
    }
}
check("UIAppFonts names Nunito and Baloo Bhaijaan 2",
      appFonts == ["Fonts/Nunito-Variable.ttf", "Fonts/BalooBhaijaan2-Variable.ttf"], "\(appFonts)")
check("the Fonts folder is copied into the app as Fonts/",
      project.contains("- path: RedPen/Resources/Fonts\n        type: folder\n        buildPhase: resources"))
let fontsDir = root.appendingPathComponent("ios/RedPen/Resources")
for entry in appFonts {
    check("\(entry) is bundled", FileManager.default.fileExists(atPath: fontsDir.appendingPathComponent(entry).path))
}
let bundled = ((try? FileManager.default.contentsOfDirectory(atPath: fontsDir.appendingPathComponent("Fonts").path)) ?? [])
    .filter { $0.hasSuffix(".ttf") || $0.hasSuffix(".otf") }.sorted()
check("every bundled font is registered", bundled.map { "Fonts/" + $0 }.sorted() == appFonts.sorted(), "\(bundled)")

// MARK: the names WardType asks for are the files' own

let tokens = read("ios/RedPen/Shared/Ward/WardTokens.swift")
func literal(_ name: String) -> String {
    guard let range = tokens.range(of: "static let \(name) = \"") else { return "" }
    return String(tokens[range.upperBound...].prefix { $0 != "\"" })
}
let latin = literal("latinFamily"), arabic = literal("arabicFamily")
check("WardType's Latin family is Nunito's own name",
      !latin.isEmpty && familyName(fontsDir.appendingPathComponent("Fonts/Nunito-Variable.ttf")) == latin, latin)
check("WardType's Arabic family is Baloo Bhaijaan 2's own name",
      !arabic.isEmpty && familyName(fontsDir.appendingPathComponent("Fonts/BalooBhaijaan2-Variable.ttf")) == arabic, arabic)
check("Arabic is chosen by the app's language", tokens.contains("L10n.language.hasPrefix(\"ar\") ? arabicFamily : latinFamily"))

// MARK: every face scales and names its weight; observations stay mono

check("a face is Font.custom relative to its text style",
      tokens.contains("Font.custom(family, size: largeSize(style), relativeTo: style).weight(weight)"))
for (face, style, weight) in [("display", "largeTitle", "bold"), ("title", "title3", "semibold"),
                              ("headline", "headline", "semibold"), ("body", "body", "regular"),
                              ("caption", "caption", "regular")] {
    check("\(face) is \(style) \(weight)", tokens.contains("static let \(face) = face(.\(style), weight: .\(weight))"))
}
check("observations stay in the system mono",
      tokens.contains("static let obs = Font.system(.body, design: .monospaced)")
        && tokens.contains("static let obsLarge = Font.system(.title2, design: .monospaced).weight(.semibold)"))
let app = read("ios/RedPen/RedPenApp.swift")
check("both windows default to WardType.body", app.components(separatedBy: ".font(WardType.body)").count - 1 == 2)

// MARK: the licences ship beside the fonts, and the fonts are credited

for licence in ["Nunito-OFL.txt", "BalooBhaijaan2-OFL.txt"] {
    check("\(licence) is beside its font",
          read("ios/RedPen/Resources/Fonts/\(licence)").contains("SIL Open Font License, Version 1.1"))
}
check("the fonts are in Settings' credits under the OFL",
      ContentSources.all.contains(ContentSources.fonts) && ContentSources.fonts.licences == [ContentSources.ofl])

print(failures.isEmpty ? "\nALL FONT TESTS PASS" : "\n\(failures.count) FONT TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
