import Foundation

// The phone and the foldable iPhone in every posture and orientation
// (T0138): the hinge band and the two panes either side of it, 44 pt
// targets kept off the band, the launch arguments the screenshot jobs
// pass, the iPhone's orientations in project.yml, the frame's corner from
// the display, and no layout decided by the kind of device.

var failures = 0
var checks = 0
func check(_ name: String, _ result: Bool) {
    checks += 1
    print("\(result ? "PASS" : "FAIL") \(name)")
    if !result { failures += 1 }
}

func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
    let i = a.intersection(b)
    return !i.isNull && i.width > 1e-9 && i.height > 1e-9
}

func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 1e-6 }

// Portrait window sizes in points; landscape swaps them. The foldable's
// inner screen is not in any SDK yet, so its size here is an assumption.
let phones: [(String, CGFloat, CGFloat)] = [
    ("iPhone SE", 375, 667),
    ("iPhone 17", 402, 874),
    ("iPhone 17 Pro", 402, 874),
    ("iPhone 17 Pro Max", 440, 956),
    ("foldable inner (assumed)", 600, 760),
]

// MARK: band and panes, every posture x orientation

for (label, w, h) in phones {
    for orientation in DevicePosture.Orientation.allCases {
        let window = orientation.isLandscape ? CGSize(width: h, height: w) : CGSize(width: w, height: h)
        let bounds = CGRect(origin: .zero, size: window)
        for posture in DevicePosture.Posture.allCases {
            let name = "\(label) \(posture.rawValue) \(orientation.rawValue)"
            let p = DevicePosture.current(window: window, orientation: orientation, preview: posture)
            check("\(name): orientation kept", p.orientation == orientation)
            if posture == .folded {
                check("\(name): no band", p.band == nil)
                check("\(name): no panes", p.panes(in: bounds) == nil)
                check("\(name): everything clear", p.clear(bounds))
                continue
            }
            guard let band = p.band, let panes = p.panes(in: bounds), let controls = panes.controls else {
                check("\(name): a band and two panes", false)
                continue
            }
            check("\(name): band inside the window", bounds.contains(band))
            check("\(name): band across the longer side",
                  window.width >= window.height ? near(band.height, window.height) : near(band.width, window.width))
            check("\(name): side by side in a wide window", panes.sideBySide == (window.width >= window.height))
            check("\(name): reading pane off the band", !overlaps(panes.reading, band))
            check("\(name): controls pane off the band", !overlaps(controls, band))
            check("\(name): panes apart", !overlaps(panes.reading, controls))
            if panes.sideBySide {
                check("\(name): reading leading", panes.reading.maxX <= band.minX + 1e-9)
                check("\(name): widths add up", near(panes.reading.width + band.width + controls.width, window.width))
            } else {
                check("\(name): reading on top", panes.reading.maxY <= band.minY + 1e-9)
                check("\(name): heights add up", near(panes.reading.height + band.height + controls.height, window.height))
            }
            for pane in [panes.reading, controls] {
                check("\(name): pane holds a 44 pt target",
                      pane.width >= DevicePosture.minPane && pane.height >= DevicePosture.minPane)
            }
            check("\(name): one-side screens take the reading side on a tie", p.clearPane(in: bounds) == panes.reading)
            // every 44 pt target laid out in either pane keeps off the band
            var targets = 0, offBand = 0
            for pane in [panes.reading, controls] {
                var y = pane.minY
                while y + 44 <= pane.maxY + 1e-9 {
                    var x = pane.minX
                    while x + 44 <= pane.maxX + 1e-9 {
                        let target = CGRect(x: x, y: y, width: 44, height: 44)
                        targets += 1
                        if p.clear(target) && !overlaps(target, band) { offBand += 1 }
                        x += 44
                    }
                    y += 44
                }
            }
            check("\(name): \(targets) targets, all clear of the band", targets > 0 && offBand == targets)
            let straddling = CGRect(x: band.midX - 22, y: band.midY - 22, width: 44, height: 44)
            check("\(name): a target on the hinge is not clear", !p.clear(straddling))
            // a screen that stops short of the band is not split
            let short = panes.sideBySide
                ? CGRect(x: 0, y: 0, width: band.minX, height: window.height)
                : CGRect(x: 0, y: 0, width: window.width, height: band.minY)
            check("\(name): a screen short of the band is left whole", p.panes(in: short) == nil)
            // one cut off just past the band keeps only its wide side
            let past = panes.sideBySide
                ? CGRect(x: 0, y: 0, width: band.maxX + 10, height: window.height)
                : CGRect(x: 0, y: 0, width: window.width, height: band.maxY + 10)
            let one = p.panes(in: past)
            check("\(name): a sliver past the band is no pane", one != nil && one?.controls == nil)
        }
    }
}

// MARK: a phone that does not fold

let still = DevicePosture.current(window: CGSize(width: 402, height: 874), orientation: .landscapeLeft, preview: nil)
check("no preview posture: folded, no band", still.posture == .folded && still.band == nil)
check("the flat posture has no band", DevicePosture.flat.band == nil && DevicePosture.flat.posture == .folded)

// MARK: the screenshot launches' arguments

let both = DevicePosture.preview(arguments: ["app", "-uiPreviewPosture", "half", "-uiPreviewOrientation", "landscapeLeft"])
check("half, landscapeLeft", both.posture == .half && both.orientation == .landscapeLeft)
check("open, landscapeRight", DevicePosture.preview(arguments: ["-uiPreviewPosture", "open", "-uiPreviewOrientation", "landscapeRight"])
    == (posture: .open, orientation: .landscapeRight))
check("folded, portrait", DevicePosture.preview(arguments: ["-uiPreviewPosture", "folded", "-uiPreviewOrientation", "portrait"])
    == (posture: .folded, orientation: .portrait))
check("the iPad job's landscape is landscapeRight",
      DevicePosture.preview(arguments: ["-uiPreviewOrientation", "landscape"]).orientation == .landscapeRight)
check("tent is half-open", DevicePosture.preview(arguments: ["-uiPreviewPosture", "tent"]).posture == .half)
check("nothing named, nothing", DevicePosture.preview(arguments: ["app"]) == (posture: nil, orientation: nil))
check("an unknown word is nothing",
      DevicePosture.preview(arguments: ["-uiPreviewPosture", "sideways", "-uiPreviewOrientation", "upsideDown"])
          == (posture: nil, orientation: nil))
check("a flag at the end is nothing", DevicePosture.preview(arguments: ["-uiPreviewPosture"]).posture == nil)

// MARK: project.yml: the iPhone turns both ways, never upside down

func orientations(_ key: String, in yml: String) -> [String] {
    var lines = yml.components(separatedBy: "\n")[...]
    guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == key + ":" }) else { return [] }
    lines = lines[(start + 1)...]
    var found: [String] = []
    for line in lines {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("- ") else { break }
        found.append(String(t.dropFirst(2)))
    }
    return found
}

let yml = (try? String(contentsOfFile: "ios/project.yml", encoding: .utf8)) ?? ""
check("project.yml read", !yml.isEmpty)
let phone = orientations("UISupportedInterfaceOrientations", in: yml)
check("iPhone: portrait", phone.contains("UIInterfaceOrientationPortrait"))
check("iPhone: landscape left", phone.contains("UIInterfaceOrientationLandscapeLeft"))
check("iPhone: landscape right", phone.contains("UIInterfaceOrientationLandscapeRight"))
check("iPhone: never upside down", !phone.contains("UIInterfaceOrientationPortraitUpsideDown"))
let pad = orientations("UISupportedInterfaceOrientations~ipad", in: yml)
check("iPad: every way", Set(pad) == ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown",
                                      "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"])

// MARK: the frame's corner from the display, not the device

for (label, w, h) in phones.filter({ !$0.0.hasPrefix("foldable") }) {
    check("\(label): a phone's corner", !WardPaper.roundsLikePad(displayWidth: Double(w), displayHeight: Double(h)))
    check("\(label) on its side: a phone's corner", !WardPaper.roundsLikePad(displayWidth: Double(h), displayHeight: Double(w)))
}
for (w, h) in [(744.0, 1133.0), (820.0, 1180.0), (1024.0, 1366.0)] {
    check("iPad \(Int(w)): the large screen's corner", WardPaper.roundsLikePad(displayWidth: w, displayHeight: h))
    check("iPad \(Int(w)) on its side: the large screen's corner", WardPaper.roundsLikePad(displayWidth: h, displayHeight: w))
}

// landscape, the island on either side: the frame clears it and its
// corners stay concentric with the display's
let half = WardPaper.edgeWidth / 2
for (label, w, h) in [("iPhone 17 Pro", 874.0, 402.0), ("iPhone 17 Pro Max", 956.0, 440.0)] {
    for (side, safe) in [("island left", WardSystemInsets(top: 0, bottom: 21, left: 62, right: 0)),
                         ("island right", WardSystemInsets(top: 0, bottom: 21, left: 0, right: 62)),
                         ("both sides", WardSystemInsets(top: 0, bottom: 21, left: 62, right: 62))] {
        let name = "\(label) \(side)"
        guard let panel = WardPaper.panel(width: w, height: h, safe: safe, device: nil) else {
            check("\(name): a panel", false)
            continue
        }
        check("\(name): clear of the island side", panel.x - half >= safe.left - 1e-9
              && panel.x + panel.width + half <= w - safe.right + 1e-9)
        check("\(name): clear of the home indicator", panel.y + panel.height + half <= h - safe.bottom + 1e-9)
        let device = WardPaper.deviceRadius(width: w, height: h)
        let sideInset = max(panel.x, w - panel.x - panel.width)
        let cap = min(panel.width, panel.height) / (2 * 1.52866483)
        check("\(name): top corners concentric", panel.radius ==
              min(cap, WardCorner.concentric(device: device, inset: max(sideInset, panel.y), floor: WardEdge.minRadius)))
        check("\(name): bottom corners concentric", panel.bottomRadius ==
              min(cap, WardCorner.concentric(device: device, inset: max(sideInset, h - panel.y - panel.height),
                                             floor: WardEdge.minRadius)))
    }
}

// MARK: layout by the window, never the kind of device

let deviceCheck = try! NSRegularExpression(
    pattern: #"userInterfaceIdiom|UIDevice\.current\.model|UIDevice\.current\.localizedModel|(==|!=|hasPrefix\(|contains\()\s*"iP(hone|ad|od)"#)
var offenders: [String] = []
let root = "ios/RedPen"
if let walker = FileManager.default.enumerator(atPath: root) {
    for case let path as String in walker where path.hasSuffix(".swift") {
        // Diagnostics only reports the device; the tests name what they ban
        if path.hasPrefix("Shared/Diagnostics/") || path.hasPrefix("Tests/") { continue }
        guard let text = try? String(contentsOfFile: root + "/" + path, encoding: .utf8) else { continue }
        for (n, line) in text.components(separatedBy: "\n").enumerated() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
            let range = NSRange(line.startIndex..., in: line)
            if deviceCheck.firstMatch(in: line, range: range) != nil { offenders.append("\(path):\(n + 1)") }
        }
    }
}
check("sources found", FileManager.default.fileExists(atPath: root + "/Shared/DevicePosture.swift"))
check("no device-type check outside Diagnostics" + (offenders.isEmpty ? "" : ": " + offenders.joined(separator: ", ")),
      offenders.isEmpty)

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
