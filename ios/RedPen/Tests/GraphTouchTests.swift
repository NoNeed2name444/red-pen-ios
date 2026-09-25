// Touching the Ideas map (GraphTouchModel.swift): what a touch was - tap,
// double tap, hold-and-drag, hold for options, or a turn of the camera -
// the selection's state as taps, chips, Open and Show links come in, and
// what the peek card says for each kind of body in each theme.
//
// Compiled with GraphTouchModel.swift alone (Foundation only).
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "PASS " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

func id(_ n: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-4000-8000-%012X", n)) ?? UUID()
}

// MARK: T1 what a touch was

func judge(_ onBody: Bool, _ held: Double, _ moved: Double, lifted: Bool = true, taps: Int = 1) -> GraphTouchKind {
    GraphTouchRules.judge(GraphTouch(onBody: onBody, held: held, moved: moved, lifted: lifted, taps: taps))
}
check("T1 a quick touch on a body is a tap", judge(true, 0.08, 2) == .tap)
check("T1 on empty space too (it lets the chosen one go)", judge(false, 0.08, 2) == .tap)
check("T1 two quick taps on a body: a double tap", judge(true, 0.08, 1, taps: 2) == .doubleTap)
check("T1 two on empty space: not ours (the camera's own)", judge(false, 0.08, 1, taps: 2) == .tap)
check("T1 a quick drag on a body turns the camera, never moves it", judge(true, 0.12, 40, lifted: false) == .orbit)
check("T1 a quick drag on empty space turns the camera", judge(false, 0.05, 60, lifted: false) == .orbit)
check("T1 held a quarter second, then moved: picked up", judge(true, 0.3, 25, lifted: false) == .drag)
check("T1 exactly at the hold: picked up", judge(true, GraphTouchRules.holdToDrag, 11, lifted: false) == .drag)
check("T1 held still on a body: its options", judge(true, 0.6, 3, lifted: false) == .menu)
check("T1 still deciding while held briefly", judge(true, 0.3, 2, lifted: false) == .pending)
check("T1 a slow tap is still a tap", judge(true, 0.4, 2) == .tap)
check("T1 held on empty space then moved: the camera", judge(false, 0.5, 30, lifted: false) == .orbit)
check("T1 a wobble within the slop is still a tap", judge(true, 0.1, GraphTouchRules.slop) == .tap)
check("T1 thresholds: 0.25 s to pick up, options after, 10 points of slop",
      GraphTouchRules.holdToDrag == 0.25 && GraphTouchRules.holdForMenu > 0.4 && GraphTouchRules.slop == 10)
check("T1 a double tap is close in time and place", GraphTouchRules.pairs(gap: 0.2, distance: 12)
      && !GraphTouchRules.pairs(gap: 0.5, distance: 12) && !GraphTouchRules.pairs(gap: 0.2, distance: 90))

// MARK: T2 the selection

let a: UUID = id(1)
let b: UUID = id(2)
var s = GraphSelection()
check("T2 nothing chosen: no card", !s.cardShown)
check("T2 tap a body: selected, card up, eases towards it", s.handle(.tapBody(a), at: 0) == [.select(a, glide: false)]
      && s.cardShown && s.selected == a)
check("T2 the double tap's second tap does not open twice", s.handle(.tapBody(a), at: 0.2) == [])
check("T2 the double tap opens", s.handle(.doubleTap(a), at: 0.21) == [.open(a)] && !s.cardShown)
check("T2 closing returns to the map with it still selected", s.handle(.closed, at: 3) == [] && s.selected == a
      && s.cardShown)
check("T2 tap it again: open", s.handle(.tapBody(a), at: 4) == [.open(a)])
_ = s.handle(.closed, at: 5)
check("T2 an open asked for twice at once opens once", s.handle(.openCard, at: 6) == [.open(a)]
      && s.handle(.openCard, at: 6.1) == [])
_ = s.handle(.closed, at: 7)
check("T2 Show links dims round it", s.handle(.showLinks, at: 8) == [.links(a)] && s.linksShown)
check("T2 a chip selects that body, the camera glides, the neighbourhood follows",
      s.handle(.chip(b), at: 9) == [.select(b, glide: true), .links(b)] && s.selected == b)
check("T2 Show links again: everything back", s.handle(.showLinks, at: 10) == [.links(nil)] && !s.linksShown)
check("T2 tap empty space: deselect, card hides", s.handle(.tapEmpty, at: 11) == [.clear] && !s.cardShown)
check("T2 again: nothing more", s.handle(.tapEmpty, at: 12) == [])
check("T2 a double tap on an unchosen body selects and opens", s.handle(.doubleTap(a), at: 13)
      == [.select(a, glide: false), .open(a)])
_ = s.handle(.closed, at: 14)
check("T2 hold: its options, selecting it first", s.handle(.hold(b), at: 15) == [.select(b, glide: false), .menu(b)])
_ = s.handle(.showLinks, at: 16)
check("T2 a deleted body lets go, and the map comes back", s.handle(.gone(b), at: 17) == [.links(nil), .clear]
      && s.selected == nil)
check("T2 another body going changes nothing", s.handle(.gone(a), at: 18) == [])
check("T2 Open with nothing chosen does nothing", s.handle(.openCard, at: 19) == [])

// MARK: T3 the peek card

func card(_ theme: String, _ role: String, page: Bool = false, folder: Bool = false) -> GraphPeekContent {
    var input = GraphPeekInput(theme: theme, role: role, folder: folder, title: "Heart failure", page: page)
    input.body = "# Heart failure\n\n- A syndrome, not a [[diagnosis]].\nTypes: HFrEF, HFpEF.\nCauses\nMore"
    input.links = [(id(9), "BNP"), (id(8), "ACE inhibitors")]
    return GraphPeek.content(input)
}
check("T3 Space: Gas giant · Page", card("space", "gasGiant", page: true).kind == "Gas giant \u{00B7} Page")
check("T3 Space: Rocky planet · Idea", card("space", "rocky").kind == "Rocky planet \u{00B7} Idea")
check("T3 Neurons: Interneuron · Idea", card("neurons", "4").kind == "Interneuron \u{00B7} Idea")
check("T3 Neurons: Neuron · Page", card("neurons", "3", page: true).kind == "Neuron \u{00B7} Page")
check("T3 Circuit: LED · Idea", card("circuit", "6").kind == "LED \u{00B7} Idea")
check("T3 Circuit: Capacitor · Page", card("circuit", "3", page: true).kind == "Capacitor \u{00B7} Page")
var single = GraphPeekInput(theme: "space", role: "", folder: false, title: "x", page: false)
single.lookName = "Pulsar"
check("T3 a single look names its style", GraphPeek.content(single).kind == "Pulsar \u{00B7} Idea")
single.lookName = ""
check("T3 no theme word: the plain type", GraphPeek.content(single).kind == "Idea")
let note: GraphPeekContent = card("space", "gasGiant", page: true)
check("T3 the first three lines, without markup", note.lines == ["Heart failure", "A syndrome, not a diagnosis.",
                                                                 "Types: HFrEF, HFpEF."], "\(note.lines)")
check("T3 links as chips, by title", note.chips.map(\.title) == ["ACE inhibitors", "BNP"])
check("T3 Open, Show links, More", note.primary == "Open" && note.secondary == ["Show links", "More"])
var many = GraphPeekInput(theme: "circuit", role: "6", folder: false, title: "Hub")
many.links = (0..<10).map { (id(100 + $0), "Link \($0)") }
let crowded: GraphPeekContent = GraphPeek.content(many)
check("T3 six chips and the rest counted", crowded.chips.count == 6 && crowded.moreLinks == 4)
check("T3 an empty note says so", crowded.lines == ["Nothing written yet."])
var folder = GraphPeekInput(theme: "space", role: "star", folder: true, title: "Inguinal")
folder.notes = 8
folder.subfolders = 1
folder.recent = ["Inguinal canal", "Internal ring test", "Direct inguinal hernia", "Old"]
let folderCard: GraphPeekContent = GraphPeek.content(folder)
check("T3 a folder: Star · Folder", folderCard.kind == "Star \u{00B7} Folder")
check("T3 a folder: counts and its latest notes", folderCard.lines == [
    "8 notes \u{00B7} 1 subfolder", "Latest: Inguinal canal, Internal ring test, Direct inguinal hernia"
], "\(folderCard.lines)")
check("T3 a folder: Open folder and Fly in", folderCard.primary == "Open folder" && folderCard.secondary == ["Fly in"])
check("T3 Neurons folder: Brain region", GraphPeek.content(GraphPeekInput(theme: "neurons", role: "0", folder: true,
                                                                          title: "C")).kind == "Brain region \u{00B7} Folder")
check("T3 Circuit folder: Processor", GraphPeek.content(GraphPeekInput(theme: "circuit", role: "0", folder: true,
                                                                       title: "C")).kind == "Processor \u{00B7} Folder")
check("T3 every card is read out whole", note.spoken.contains("Gas giant") && note.spoken.contains("2 links"))
check("T3 an untitled note", GraphPeek.content(GraphPeekInput(theme: "space", role: "rocky", folder: false,
                                                              title: "")).title == "Untitled")

// MARK: T4 the words around it

check("T4 the first-run card's three lines", GraphPeek.coachLines == [
    "Tap to preview", "Tap again or Open to read", "Hold to move or for options"
])
check("T4 VoiceOver's actions", GraphPeek.actions(folder: false) == ["Open", "Show links", "Delete"])
check("T4 a note's options", GraphPeek.menu(folder: false, home: false) == [
    "Open", "Rename", "Link to\u{2026}", "Move to folder\u{2026}", "Delete"
])
check("T4 a folder's options add a note there", GraphPeek.menu(folder: true, home: false).contains("Add note here")
      && !GraphPeek.menu(folder: true, home: false).contains("Link to\u{2026}"))
check("T4 the home star cannot be renamed or deleted", !GraphPeek.menu(folder: true, home: true).contains("Delete"))

print(failures.isEmpty ? "all passed" : "\(failures.count) failed")
exit(failures.isEmpty ? 0 : 1)
