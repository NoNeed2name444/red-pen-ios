// Every Ward control in every state (WardControlStates), for each section in
// light and dark. Words and glyphs read 4.5:1 on their face in every state.
// A disabled label reads 3:1 or more and is told apart from the enabled one.
// Chosen is told apart from unchosen by more than relief (an ink, a fill or a
// solid mark), disabled too. What sits on a fill reads on it. No state is a
// blue outside Questions. Held, every control sinks. And the disabled ink
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
// A blue: within this many degrees of the palette's blue or the
// Questions paper's (tests/ward/accent-blue.test.mjs).
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
                           WardSection.questions.ink(dark: dark)]
    for s in sections {
        // a chosen state that stands on the section's fill has white words
        let white = WardPalette.contrast(WardPalette.hex(.onPrimary, dark: dark), s.fill(dark: dark))
        check("\(mode) \(s): white reads 4.5:1 on its fill", white >= 4.5, f(white))
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
                    check("\(name): its \(what) read 4.5:1 on its face", r >= 4.5, "\(h(ink)) on \(h(c.readOn)) \(f(r))")
                    if r < worstText.0 { worstText = (r, name) }
                }
                // what sits on a fill reads on it: white words on the
                // section's fill, a switch's knob on its tint or its grey
                if look.face == .primary {
                    check("\(name): on the fill its words are white", look.words == .onPrimary && look.glyph == nil)
                }
                if let knob = c.knob, look.face != .well {
                    let r = WardPalette.contrast(knob, c.face)
                    check("\(name): the knob reads 3:1 on the filled track", r >= 3, "\(h(knob)) on \(h(c.face)) \(f(r))")
                }
                // no state is a blue outside Questions
                if s != .questions {
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
                    check("\(name): told apart from unchosen by more than relief", d >= apart, f(d))
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

print("ok   words and glyphs: the lowest is \(f(worstText.0)):1 (\(worstText.1))")
print("ok   disabled from enabled: the nearest is \(f(worstDisabledApart.0)) (\(worstDisabledApart.1))")
print("ok   chosen from unchosen: the nearest is \(f(worstChosenApart.0)) (\(worstChosenApart.1))")
print(failures.isEmpty ? "\nall \(checks) passed" : "\n\(failures.count) of \(checks) failed")
exit(failures.isEmpty ? 0 : 1)
