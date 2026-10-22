// Every Ward control in every state (WardControlStates), for each section in
// light and dark. Words and glyphs read 4.5:1 on their face in every state.
// A disabled label reads 3:1 or more and is told apart from the enabled one.
// Chosen is told apart from unchosen by more than relief (an ink, a fill or a
// solid mark), disabled too. What sits on a fill reads on it. No state is a
// blue outside Cards (the primary's indigo). Held, every control sinks. And the disabled ink
// itself reads on every tier and is apart from every colour with a meaning.
// The states gallery (WardStatesGallery) draws the real styles in these
// states.
import Foundation

var failures: [String] = []
var checks = 0

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    checks += 1
    // the passes are many (a few thousand); print the failures in full
    if !ok {
        print("FAIL " + label + "  | " + detail)
        failures.append(label)
    }
}

func f(_ x: Double) -> String { String(format: "%.3f", x) }
func h(_ x: UInt32) -> String { String(format: "#%06X", x) }

// MARK: - The owner's accepted cases

// The owner, 22 Oct 2026, about 3:44 AM Cairo, shown that the exact colours
// fail the readability checks: "STOP IMPROVISING DONT CHANGE THE COLORS I
// GAVE U". So every colour is the owner's hex as given, white words on the
// fills included, on the plain ground. A check below that falls short only
// because of that passes only as its exact case on the owner's list
// (ios/RedPen/Tests/OwnerAccepted.json, under this file's name), measured
// within 0.01 of the value recorded there. Any other case still fails, and
// so does a listed case no check here measures short.
let ownerFile = "ios/RedPen/Tests/OwnerAccepted.json"
let ownerList: [String: Double] = {
    var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    while !FileManager.default.fileExists(atPath: dir.appendingPathComponent(ownerFile).path), dir.path != "/" {
        dir.deleteLastPathComponent()
    }
    guard let data = FileManager.default.contents(atPath: dir.appendingPathComponent(ownerFile).path),
          let all = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let mine = all["WardStatesTests.swift"] as? [String: Any] else { return [:] }
    var out: [String: Double] = [:]
    for (key, value) in mine {
        if let n = value as? NSNumber { out[key] = n.doubleValue } else if let d = value as? Double { out[key] = d }
    }
    return out
}()
var ownerSeen: Set<String> = []
/// True only when `measured`, short of its check's threshold, is the
/// owner's accepted case `key` at the value recorded for it.
func owner(_ key: String, _ measured: Double) -> Bool {
    ownerSeen.insert(key)
    guard let listed = ownerList[key] else {
        print("owner-accepted miss: \"\(key)\": " + String(format: "%.3f", measured))
        return false
    }
    guard abs(measured - listed) <= 0.01 else {
        print("owner-accepted moved: \"\(key)\": " + String(format: "%.3f", measured) + ", listed " + String(format: "%.3f", listed))
        return false
    }
    return true
}

// OKLab (Ottosson), perceptual: equal distances look about equally
// different, and the hue is the one the eye sees.
func oklab(_ x: UInt32) -> (L: Double, a: Double, b: Double) {
    func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    let (r0, g0, b0) = WardPalette.rgb(x)
    let r = linear(r0), g = linear(g0), b = linear(b0)
    let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
}
func distance(_ x: UInt32, _ y: UInt32) -> Double {
    let p = oklab(x), q = oklab(y)
    return ((p.L - q.L) * (p.L - q.L) + (p.a - q.a) * (p.a - q.a) + (p.b - q.b) * (p.b - q.b)).squareRoot()
}
func chroma(_ x: UInt32) -> Double { let o = oklab(x); return (o.a * o.a + o.b * o.b).squareRoot() }
func hue(_ x: UInt32) -> Double {
    let o = oklab(x)
    let d = atan2(o.b, o.a) * 180 / .pi
    return d < 0 ? d + 360 : d
}
func hueApart(_ a: Double, _ b: Double) -> Double {
    let d = abs(a - b).truncatingRemainder(dividingBy: 360)
    return min(d, 360 - d)
}

// Told apart at a glance: the distance the sections keep from one another
// and from the colours that mean something (WardLookTests,
// tools/ward_accents.py).
let apart = 0.075
// A colour rather than one of the palette's greys, whose chroma is 0.04 at
// most (Chart Ink, Biro Grey and the tiers are all faintly blue).
let colourful = 0.06
// A blue: within this many degrees of the primary's indigo (Cards' own, the
// look outside any section) or the paper's ink outside any section
// (tests/ward/accent-blue.test.mjs).
let blueReach = 25.0

let sections = WardSection.allCases
let modes = [false, true]
func modeName(_ dark: Bool) -> String { dark ? "dark" : "light" }

// MARK: - The disabled ink

for dark in modes {
    let mode = modeName(dark)
    let ink: UInt32 = WardPalette.hex(WardControlStates.disabledInk, dark: dark)
    for tier in WardPalette.tiers {
        let r = WardPalette.contrast(ink, WardPalette.hex(tier, dark: dark))
        check("\(mode): the disabled ink reads 4.5:1 on the \(tier)", r >= 4.5, f(r))
    }
    var near = 9.0, what = ""
    for token in [WardToken.ink] + WardSection.semanticTokens {
        let d = distance(ink, WardPalette.hex(token, dark: dark))
        if d < near { near = d; what = "\(token)" }
    }
    for s in sections {
        let d = distance(ink, s.accent(dark: dark))
        if d < near { near = d; what = "\(s)'s accent" }
    }
    check("\(mode): the disabled ink is told apart from Chart Ink, the meanings and every accent",
          near >= apart, "\(what) \(f(near))")
    print("ok   \(mode): the disabled ink \(h(ink)), nearest \(what) at \(f(near))")
}
check("the disabled ink is no accent", WardControlStates.disabledInk != .primaryInk && WardControlStates.disabledInk != .primary)

// MARK: - The states, as drawn

check("ten controls", WardControl.allCases.count == 10)
for control in WardControl.allCases {
    check("\(control): \(control.isButton ? "three states, none chosen" : "six states")",
          control.states.count == (control.isButton ? 3 : 6) && control.states.allSatisfy { !$0.isChosen || !control.isButton })
}

/// How far `now` is told from `was` by colour alone, not relief: its label,
/// its face, or a solid mark it carries (`unmarked` is what was there
/// without it: a control's own edge, or a switch's knob).
func told(_ now: WardControlColours, from was: WardControlColours, unmarked: UInt32) -> Double {
    var best = distance(now.face, was.face)
    if let a = now.label, let b = was.label { best = max(best, distance(a, b)) }
    if let mark = now.mark { best = max(best, distance(mark, was.mark ?? unmarked)) }
    if let mark = was.mark, now.mark == nil { best = max(best, distance(mark, unmarked)) }
    return best
}

var worstDisabledApart = (9.0, ""), worstChosenApart = (9.0, ""), worstText = (99.0, "")

for dark in modes {
    let mode = modeName(dark)
    let blues: [UInt32] = [WardPalette.hex(.primaryInk, dark: dark), WardPalette.hex(.primary, dark: dark),
                           WardSection.outside.ink(dark: dark)]
    for s in sections {
        // a chosen state that stands on the section's fill has white words
        let white = WardPalette.contrast(WardPalette.hex(.onPrimary, dark: dark), s.fill(dark: dark))
        let onFill = "\(mode) \(s): white reads 4.5:1 on its fill"
        check(onFill, white >= 4.5 || owner(onFill, white), f(white))
        for control in WardControl.allCases {
            for state in control.states {
                let look = control.look(state)
                let c = look.colours(s, dark: dark)
                let name = "\(mode) \(s): the \(control) \(state)"
                // what was there before a mark: the control's own edge on
                // its face, or a switch's knob
                func unmarked(_ was: WardControlColours) -> UInt32 {
                    control == .toggle ? (was.knob ?? was.face)
                        : WardRelief.edgeColor(s, dark: dark, on: was.face)
                }

                // words and glyphs, 4.5:1 on their face in every state
                for (what, ink) in [("words", c.words), ("glyph", c.glyph)] {
                    guard let ink else { continue }
                    let r = WardPalette.contrast(ink, c.readOn)
                    let key = "\(name): its \(what) read 4.5:1 on its face"
                    check(key, r >= 4.5 || owner(key, r), "\(h(ink)) on \(h(c.readOn)) \(f(r))")
                    if r < worstText.0 { worstText = (r, name) }
                }
                // what sits on a fill reads on it: white words on the
                // section's fill, a switch's knob on its tint or its grey
                if look.face == .primary {
                    check("\(name): on the fill its words are white", look.words == .onPrimary && look.glyph == nil)
                }
                if let knob = c.knob, look.face != .well {
                    let r = WardPalette.contrast(knob, c.face)
                    let key = "\(name): the knob reads 3:1 on the filled track"
                    check(key, r >= 3 || owner(key, r), "\(h(knob)) on \(h(c.face)) \(f(r))")
                }
                // no state is a blue outside Cards, whose indigo the
                // primary is (Questions is red since direction 3)
                if s != WardSection.outside {
                    for x in c.all {
                        check("\(name): \(h(x)) is not the palette's blue", !blues.contains(x))
                        guard chroma(x) >= colourful else { continue }
                        let d = blues.map { hueApart(hue(x), hue($0)) }.min() ?? 360
                        check("\(name): \(h(x)) is not a blue", d >= blueReach, "\(f(d)) degrees from blue")
                    }
                }
                // held, it sinks: the face, or a switch's knob
                if state.isHeld && state.isEnabled {
                    let sinks: Bool = control == .toggle ? look.knobStand?.isPressedIn == true : look.stand.isPressedIn
                    check("\(name): sinks into the base", sinks)
                }
                // disabled: 3:1 or more, and told apart from enabled by its
                // label (a switch by its track or its knob's edge); it lies
                // at the lowest lift
                if !state.isEnabled {
                    let twin = control.look(state.enabledTwin).colours(s, dark: dark)
                    let d: Double
                    if let label = c.label, let was = twin.label {
                        let r = WardPalette.contrast(label, c.readOn)
                        check("\(name): its label reads 3:1 on its face", r >= 3, f(r))
                        d = distance(label, was)
                        check("\(name): its label is told apart from enabled", d >= apart, "\(h(label)) vs \(h(was)) \(f(d))")
                    } else {
                        d = told(c, from: twin, unmarked: unmarked(twin))
                        check("\(name): told apart from enabled by more than relief", d >= apart, f(d))
                    }
                    if control == .toggle {
                        // a switch with words: the track and the knob's edge
                        // tell it apart as well as the words do (the review's B3)
                        let dt = told(c, from: twin, unmarked: unmarked(twin))
                        check("\(name): its track or knob edge is told apart from enabled by more than relief",
                              dt >= apart, f(dt))
                    }
                    if d < worstDisabledApart.0 { worstDisabledApart = (d, name) }
                    if control != .toggle {
                        let low: Bool = look.stand == .raised(.low) || look.stand == .pressedIn(.low)
                        check("\(name): lies at the lowest lift", low, "\(look.stand)")
                    }
                }
                // chosen: told apart from unchosen by more than relief, in
                // every state, disabled too; pressed in (a switch: the tint
                // fills its track)
                if state.isChosen {
                    let twin = control.look(state.unchosenTwin).colours(s, dark: dark)
                    let d = told(c, from: twin, unmarked: unmarked(twin))
                    let key = "\(name): told apart from unchosen by more than relief"
                    check(key, d >= apart || owner(key, d), f(d))
                    if d < worstChosenApart.0 { worstChosenApart = (d, name) }
                    if control != .toggle {
                        check("\(name): pressed in", look.stand.isPressedIn)
                        check("\(name): a solid edge in the accent", look.mark == .primaryInk)
                    }
                }
            }
        }
    }
}

// The model's rules, as WardControls draws them: a disabled control says
// its word in the disabled ink, whatever its kind; chosen and disabled, it
// stays chosen.
for control in WardControl.allCases {
    let off = control.look(.disabled)
    check("\(control): disabled, its label is the disabled ink", off.label == WardControlStates.disabledInk)
    if control == .toggle {
        // a switch with words: they go Biro Grey with the track and the
        // knob's edge, in every state it can be disabled in
        check("toggle: disabled, its words are the disabled ink", off.words == WardControlStates.disabledInk)
        check("toggle: disabled, its knob edge is the disabled ink", off.mark == WardControlStates.disabledInk)
        for state in control.states where !state.isEnabled {
            check("toggle: \(state), its words are the disabled ink",
                  control.look(state).words == WardControlStates.disabledInk)
        }
        for state in control.states where state.isEnabled {
            check("toggle: \(state), its words are Chart Ink", control.look(state).words == .ink)
        }
    }
    if !control.isButton {
        let both = control.look(.selectedDisabled)
        check("\(control): chosen and disabled, still chosen",
              control == .toggle ? both.face == WardControlStates.disabledInk
                                 : both.stand.isPressedIn && both.mark == .primaryInk)
    }
}
check("a disabled switch's knob lies flat with an edge",
      WardControl.toggle.look(.disabled).knobStand == .flat && WardControlStates.knobEdgeWidth > 0)
check("a chosen edge is wider than a control's own 1-point edge", WardControlStates.chosenEdgeWidth > 1)

// MARK: - The dock's chosen tab: concentric with the panel, its name inside

// The owner, 21 Oct: "the corner of the part doesn't match the corner
// around it". The chosen tab's ring is concentric with the dock's panel
// (its radius the panel's less the inset between them, continuous like the
// panel's), along the bottom and in the iPad's rail; and its name sits
// wholly inside the ring at every text size the dock is drawn at.
check("the dock's panel is WardRadius.bar's 24 points", WardDock.panelRadius == WardScale.xl && WardDock.panelRadius == 24)
for (name, inset, tab) in [("bar", WardDock.barInset, WardDock.barTabRadius), ("rail", WardDock.railInset, WardDock.railTabRadius)] {
    check("\(name): the tab's radius is the panel's less the inset (\(f(WardDock.panelRadius)) - \(f(inset)))",
          tab == WardDock.panelRadius - inset && WardDock.tabRadius(inset: inset) == tab && tab > WardDock.ringWidth,
          f(tab))
    // the two continuous corners run parallel: from every point of the
    // tab's corner to the panel's, about the inset (within a tenth of it)
    let outer = WardDock.cornerPoints(radius: WardDock.panelRadius, steps: 120)
    let inner = WardDock.cornerPoints(radius: tab, steps: 120).map { (x: $0.x + inset, y: $0.y + inset) }
    func distance(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double)) -> Double {
        let dx: Double = a.x - b.x
        let dy: Double = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }
    func gaps(_ points: [(x: Double, y: Double)]) -> (Double, Double) {
        var d: [Double] = []
        for p in points {
            var nearest = Double.infinity
            for q in outer { nearest = min(nearest, distance(p, q)) }
            d.append(nearest)
        }
        return (d.min() ?? 0, d.max() ?? 0)
    }
    let (lo, hi) = gaps(inner)
    check("\(name): the tab's corner runs parallel to the panel's, \(f(inset)) apart",
          lo >= inset * 0.9 && hi <= inset * 1.0001, "\(f(lo))...\(f(hi))")
    // the 16-point tab this replaced came within 2 points of the panel's corner
    let (oldLo, _) = gaps(WardDock.cornerPoints(radius: 16, steps: 120).map { (x: $0.x + inset, y: $0.y + inset) })
    check("\(name): the old 16-point tab was not parallel (the check bites)", oldLo < inset * 0.9, f(oldLo))
}
// The name's box: centred across its tab (the slot is never narrower than
// the name and its side room, DockSlots), with at least labelVertical under
// it (the tab is at least 56 tall at the standard size, and grows with the
// text past that by the same room above and below). caption2 bold, from the
// smallest text size to xxxLarge (past it, the dock is one list button).
let caption2 = [(11.0, 13.0), (11, 13), (11, 13), (11, 13), (13, 16), (15, 18), (17, 20)]
let symbolLine = [24.0, 24, 24, 24, 26, 28, 31]
for (size, (point, line)) in caption2.enumerated() {
    // the widest name, "Questions", at about 0.6 em a letter
    let width = point * 0.6 * 9
    let content = symbolLine[size] + 3 + line
    let height = max(WardDock.tabMinHeight, content + 2 * WardDock.labelVertical)
    let below = (height - content) / 2
    for (name, radius) in [("bar", WardDock.barTabRadius), ("rail", WardDock.railTabRadius)] {
        check("\(name), text size \(size): the chosen name sits inside its ring, \(f(WardDock.labelClearance)) clear",
              below >= WardDock.labelVertical
              && WardDock.labelFits(width: width, below: below, tabWidth: width + 2 * WardDock.labelSide, radius: radius),
              "below \(f(below))")
    }
}
check("a name's room keeps it clear of the ring at its smallest (labelVertical under it)",
      WardDock.labelFits(width: 60, below: WardDock.labelVertical, tabWidth: 60 + 2 * WardDock.labelSide, radius: WardDock.barTabRadius)
      && WardDock.labelFits(width: 60, below: WardDock.labelVertical, tabWidth: 60 + 2 * WardDock.labelSide, radius: WardDock.railTabRadius))
check("the old room (4 at the sides, 2 below at large text) crossed the ring's corner (the check bites)",
      !WardDock.labelFits(width: 60, below: 2, tabWidth: 60 + 8, radius: 16)
      && !WardDock.labelFits(width: 60, below: 8, tabWidth: 60 + 8, radius: 16))
// a continuous corner of radius 20 meets its diagonal about 0.323 radii
// (6.46 points) in from each edge, a little deeper than a circle's 0.293
check("a continuous corner: clear past its reach, cut off across its diagonal",
      WardDock.inside(x: 1.6 * 20, y: 0.5, radius: 20, clearance: 0.4)
      && !WardDock.inside(x: 6, y: 6, radius: 20, clearance: 0)
      && WardDock.inside(x: 7.2, y: 7.2, radius: 20, clearance: 0.4)
      && !WardDock.inside(x: 6.6, y: 6.6, radius: 20, clearance: 0.4)
      && WardDock.inside(x: 20, y: 20, radius: 20, clearance: 1))

// The dock draws with these numbers (the source, read from the repository root).
let dockSource = (try? String(contentsOfFile: "ios/RedPen/Features/Library/StudyCategory.swift", encoding: .utf8)) ?? ""
let dockStart = dockSource.range(of: "struct CategoryDock")
let dockEnd = dockSource.range(of: "private struct DockListSheet")
let dock = dockStart.flatMap { a in dockEnd.map { String(dockSource[a.lowerBound..<$0.lowerBound]) } } ?? ""
let tokens = (try? String(contentsOfFile: "ios/RedPen/Shared/Ward/WardTokens.swift", encoding: .utf8)) ?? ""
check("found the dock's source", !dock.isEmpty)
check("the panel is WardDock's radius, continuous",
      dock.contains("RoundedRectangle(cornerRadius: CGFloat(WardDock.panelRadius), style: .continuous)")
      && tokens.contains("static let bar = CGFloat(WardScale.xl)"))
check("the chosen tab is the panel's radius less the inset, continuous, in the bar and the rail",
      dock.contains("let inset: Double = axis == .vertical ? WardDock.railInset : WardDock.barInset")
      && dock.contains("RoundedRectangle(cornerRadius: CGFloat(WardDock.tabRadius(inset: inset)), style: .continuous)")
      && !dock.contains("cornerRadius: WardRadius.button"))
check("the insets are WardDock's",
      dock.contains(".padding(CGFloat(WardDock.barInset))") && dock.contains(".padding(CGFloat(WardDock.railInset))"))
check("every tab keeps its name's room, and the rail is as wide as its widest name needs",
      dock.components(separatedBy: ".padding(.horizontal, CGFloat(WardDock.labelSide))").count == 3
      && dock.components(separatedBy: ".padding(.vertical, CGFloat(WardDock.labelVertical))").count == 3
      && dock.components(separatedBy: "minHeight: CGFloat(WardDock.tabMinHeight)").count == 3
      && dock.contains(".frame(minWidth: 76)\n        .fixedSize(horizontal: true, vertical: false)"))

print("ok   words and glyphs: the lowest is \(f(worstText.0)):1 (\(worstText.1))")
print("ok   disabled from enabled: the nearest is \(f(worstDisabledApart.0)) (\(worstDisabledApart.1))")
print("ok   chosen from unchosen: the nearest is \(f(worstChosenApart.0)) (\(worstChosenApart.1))")

// The owner's list holds only cases a check above measured short.
check("the owner's list is read (\(ownerFile), WardStatesTests.swift)", !ownerList.isEmpty)
let ownerStale = ownerList.keys.filter { !ownerSeen.contains($0) }.sorted()
check("every case on the owner's list is one a check here measured short", ownerStale.isEmpty,
      ownerStale.joined(separator: "; "))
print("ok   the owner's accepted cases: \(ownerSeen.count) measured short, each at its listed value")
print(failures.isEmpty ? "\nall \(checks) passed" : "\n\(failures.count) of \(checks) failed")
exit(failures.isEmpty ? 0 : 1)
