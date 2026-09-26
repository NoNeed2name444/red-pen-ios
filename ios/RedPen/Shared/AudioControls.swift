// Red Pen · the lecture player's controls, as arithmetic
//
// A lecture is listened to on the bus, at the gym and in bed. What makes that
// bearable is the same in every good player, and none of it is about audio:
//
//   AudioRate      the speeds on offer (0.75x to 2.5x in quarter steps), and
//                  the one remembered for each lecture and for the next new one
//   SleepCountdown the sleep timer: listening time left, and how loud the last
//                  ten seconds are as it fades out
//   AudioChapters  a lecture cut into sections - from its headings when it has
//                  them, otherwise at the pauses nearest every few minutes -
//                  and which section a moment or a line is in
//
// Foundation only, so all of it runs in the Linux tests (AudioControlsTests).
import Foundation

// MARK: speed

enum AudioRate {
    /// Quarter steps: past 2.5x a lecture stops being words.
    static let steps: [Double] = [0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5]
    static let normal: Double = 1

    /// The nearest speed on offer. Anything that is not a number is Normal.
    static func snapped(_ rate: Double) -> Double {
        guard rate.isFinite, rate > 0 else { return normal }
        var best: Double = normal
        var gap: Double = .infinity
        for step in steps where abs(step - rate) < gap {
            gap = abs(step - rate)
            best = step
        }
        return best
    }

    static func faster(than rate: Double) -> Double {
        let now: Double = snapped(rate)
        return steps.first { $0 > now } ?? now
    }

    static func slower(than rate: Double) -> Double {
        let now: Double = snapped(rate)
        return steps.last { $0 < now } ?? now
    }

    /// "1.25\u{00d7}" - the speed as the chip shows it.
    static func label(_ rate: Double) -> String {
        String(format: "%g\u{00d7}", snapped(rate))
    }

    /// The menu's words: Normal for 1x, the number otherwise.
    static func name(_ rate: Double) -> String {
        snapped(rate) == normal ? "Normal" : label(rate)
    }

    // MARK: remembered

    static let defaultKey = "audio.rate.default"
    static let lecturesKey = "audio.rate.lectures"

    /// The speed a lecture opens at: the one it was last heard at, or the
    /// last speed chosen for any lecture, or Normal.
    static func remembered(for lecture: UUID, in defaults: UserDefaults) -> Double {
        let saved: [String: Double] = (defaults.dictionary(forKey: lecturesKey) as? [String: Double]) ?? [:]
        if let own = saved[lecture.uuidString] { return snapped(own) }
        let global: Double = defaults.double(forKey: defaultKey)
        return global > 0 ? snapped(global) : normal
    }

    /// A speed chosen for a lecture is kept for it, and becomes the one the
    /// next new lecture opens at.
    static func remember(_ rate: Double, for lecture: UUID, in defaults: UserDefaults) {
        let kept: Double = snapped(rate)
        var saved: [String: Double] = (defaults.dictionary(forKey: lecturesKey) as? [String: Double]) ?? [:]
        saved[lecture.uuidString] = kept
        defaults.set(saved, forKey: lecturesKey)
        defaults.set(kept, forKey: defaultKey)
    }
}

// MARK: the sleep timer

enum SleepChoice: Hashable, Sendable {
    case minutes(Int)
    /// Stops where the section playing now ends.
    case endOfSection

    static let all: [SleepChoice] = [.minutes(5), .minutes(10), .minutes(15), .minutes(30),
                                     .minutes(45), .minutes(60), .endOfSection]

    var name: String {
        switch self {
        case .minutes(let m): return "\(m) minutes"
        case .endOfSection: return "End of this section"
        }
    }
}

/// How long is left before the lecture stops, in listening time: a paused
/// lecture does not use up the timer, so pausing for a sip of water does not
/// cut the last five minutes short.
struct SleepCountdown: Equatable, Sendable {
    /// The last ten seconds fade out rather than stopping dead.
    static let fade: Double = 10
    /// The most one check may take off. Checks come every second; a longer
    /// gap means the app was not running, and so nothing was heard either.
    static let maxStep: Double = 5

    let choice: SleepChoice
    private(set) var remaining: Double

    /// Nil for "end of this section" when the player cannot say where the
    /// section ends.
    init?(choice: SleepChoice, sectionLeft: Double? = nil) {
        self.choice = choice
        switch choice {
        case .minutes(let m):
            remaining = Double(max(1, m)) * 60
        case .endOfSection:
            guard let sectionLeft, sectionLeft.isFinite else { return nil }
            remaining = max(0, sectionLeft)
        }
    }

    /// Time heard since the last check.
    mutating func advance(listened seconds: Double) {
        guard seconds.isFinite, seconds > 0 else { return }
        remaining = max(0, remaining - min(seconds, Self.maxStep))
    }

    /// "End of this section" follows the player's own clock: a scrub back
    /// gives time back, and a faster speed takes it away.
    mutating func follow(sectionLeft: Double) {
        guard sectionLeft.isFinite else { return }
        remaining = max(0, sectionLeft)
    }

    var isDone: Bool { remaining <= 0 }

    var volume: Float { Self.volume(remaining: remaining) }

    /// Seconds until the next check: once a second, ten times a second
    /// while fading so the volume slides rather than steps - and never
    /// sleeping past the moment the fade begins.
    var nextCheck: Double {
        let untilFade: Double = remaining - Self.fade
        if untilFade <= 0 { return 0.1 }
        return max(0.1, min(1, untilFade))
    }

    /// Minutes and seconds left, for the chip.
    var label: String {
        let total: Int = Int(remaining.rounded(.up))
        let minutes: Int = total / 60
        let seconds: Int = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Full volume until the last ten seconds, then down along a square
    /// curve: it sounds even to the ear, where a straight line seems to hang
    /// on loud and then drop away at the end.
    static func volume(remaining: Double, over: Double = fade) -> Float {
        guard remaining.isFinite, over > 0 else { return 1 }
        let x: Double = min(1, max(0, remaining / over))
        return Float(x * x)
    }
}

// MARK: chapters

/// One section of a lecture: its first and last line, and where it starts
/// in the recording when there is one.
struct AudioChapter: Equatable, Sendable {
    let title: String
    let lines: Range<Int>
    let start: Double?
}

enum AudioChapters {
    /// Without headings, a lecture shorter than this is one section.
    static let shortest: Double = 6 * 60
    /// Roughly how long a section runs when there are no headings to go by.
    static let target: Double = 5 * 60
    /// "Previous" within this long of a section's start goes to the one
    /// before, as a music player's Back does; later, to this one's start.
    static let backGrace: Double = 3
    /// Speaking pace used when a line has no timing: 150 words a minute.
    static let wordsPerSecond: Double = 2.5

    /// A lecture's sections. `starts` and `ends` are each line's times in the
    /// recording (nil when a line is not timed). Empty when the lecture is
    /// one section - there is nothing to jump between.
    static func derive(lines: [String], starts: [Double?] = [], ends: [Double?] = []) -> [AudioChapter] {
        guard lines.count >= 2 else { return [] }
        let timed: Bool = starts.count == lines.count && !starts.contains { $0 == nil }
        let at: [Double] = timed ? starts.map { $0 ?? 0 } : estimatedStarts(lines)
        let fromHeadings: [AudioChapter] = byHeadings(lines, at: timed ? at : nil, timed: timed)
        if fromHeadings.count >= 2 { return fromHeadings }
        return byLength(lines, at: at, ends: timed ? ends : [], timed: timed)
    }

    /// Where each line would start, read at 150 words a minute.
    static func estimatedStarts(_ lines: [String]) -> [Double] {
        var out: [Double] = []
        var t: Double = 0
        for line in lines {
            out.append(t)
            t += seconds(toSay: line)
        }
        return out
    }

    static func seconds(toSay line: String) -> Double {
        let words: Int = line.split(whereSeparator: { $0 == " " || $0 == "\n" }).count
        return Double(max(1, words)) / wordsPerSecond
    }

    // MARK: headings

    /// The heading a line is, if it reads as one: a Markdown "#", a
    /// "Slide 4" / "Part two" / "Section B", a short line ending in a colon,
    /// or - in a typed lecture only - a short capitalised line with no full
    /// stop. A recogniser's transcript often has no punctuation at all, so
    /// that last rule would make every other line a heading there.
    static func heading(_ raw: String, timed: Bool = false) -> String? {
        let line: String = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, line.count <= 80 else { return nil }
        if line.hasPrefix("#") {
            let bare: String = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            return bare.isEmpty ? nil : bare
        }
        let words: [Substring] = line.split(separator: " ")
        if words.count <= 10, startsWithMarker(words) { return tidy(line) }
        if words.count <= 8, line.hasSuffix(":") { return tidy(line) }
        guard !timed, words.count <= 6, let first = line.first, first.isUppercase else { return nil }
        let stops: Set<Character> = [".", "?", "!", ",", ";", "\u{2026}", "\u{060C}", "\u{061F}"]
        guard let last = line.last, !stops.contains(last), line.contains(where: \.isLetter) else { return nil }
        return tidy(line)
    }

    private static let markers: Set<String> = ["slide", "section", "part", "chapter", "topic", "lecture", "unit"]

    private static func startsWithMarker(_ words: [Substring]) -> Bool {
        guard words.count >= 2 else { return false }
        let first: String = words[0].lowercased()
        return markers.contains(first)
    }

    private static func tidy(_ line: String) -> String {
        var out: String = line
        while let last = out.last, last == ":" || last == "." || last == " " { out.removeLast() }
        return out
    }

    /// A section at every heading. Headings in a row (a title and its
    /// subtitle) start one section, under the first; the lines before the
    /// first heading are an opening section of their own.
    private static func byHeadings(_ lines: [String], at: [Double]?, timed: Bool) -> [AudioChapter] {
        var starts: [Int] = []
        var titles: [String] = []
        var previousWasHeading = false
        var headingLines = 0
        for (i, line) in lines.enumerated() {
            guard let title = heading(line, timed: timed) else {
                previousWasHeading = false
                continue
            }
            headingLines += 1
            if !previousWasHeading {
                starts.append(i)
                titles.append(title)
            }
            previousWasHeading = true
        }
        // headings on most lines are a list, not a lecture's sections
        guard !starts.isEmpty, headingLines * 2 <= lines.count, starts.count * 3 <= lines.count else { return [] }
        if starts[0] > 0 {
            starts.insert(0, at: 0)
            titles.insert(shortTitle(lines[0]), at: 0)
        }
        return assemble(starts, titles: titles, count: lines.count, at: at)
    }

    // MARK: by length

    private static let turns: [String] = ["so ", "now ", "next ", "okay", "ok ", "moving on", "let's ",
                                          "lets ", "another ", "finally", "right,", "alright"]

    /// No headings: a section about every five minutes, cut where the
    /// lecturer paused longest near each mark, or at a line that turns to
    /// something new ("So", "Now", "Moving on").
    private static func byLength(_ lines: [String], at: [Double], ends: [Double?], timed: Bool) -> [AudioChapter] {
        let lastStart: Double = at.last ?? 0
        let total: Double = lastStart + seconds(toSay: lines[lines.count - 1])
        guard total >= shortest else { return [] }
        let count: Int = min(12, max(2, Int((total / target).rounded())))
        let span: Double = total / Double(count)
        var starts: [Int] = [0]
        for k in 1..<count {
            let mark: Double = span * Double(k)
            let previous: Int = starts[starts.count - 1]
            guard let cut = bestCut(near: mark, window: span * 0.35, after: previous,
                                    lines: lines, at: at, ends: ends) else { continue }
            starts.append(cut)
        }
        guard starts.count >= 2 else { return [] }
        let titles: [String] = starts.map { shortTitle(lines[$0]) }
        return assemble(starts, titles: titles, count: lines.count, at: timed ? at : nil)
    }

    private static func bestCut(near mark: Double, window: Double, after previous: Int,
                                lines: [String], at: [Double], ends: [Double?]) -> Int? {
        var best: Int?
        var bestScore: Double = -.infinity
        for i in (previous + 1)..<lines.count {
            let t: Double = at[i]
            if t < mark - window { continue }
            if t > mark + window { break }
            let score: Double = cutScore(i, mark: mark, window: window, lines: lines, at: at, ends: ends)
            if score > bestScore {
                bestScore = score
                best = i
            }
        }
        return best
    }

    /// A long pause before the line counts most, a turning word next, and
    /// being close to the mark breaks ties.
    private static func cutScore(_ i: Int, mark: Double, window: Double,
                                 lines: [String], at: [Double], ends: [Double?]) -> Double {
        var gap: Double = 0
        if i < ends.count, let end = ends[i - 1] { gap = max(0, at[i] - end) }
        let lower: String = lines[i].lowercased()
        let turn: Double = turns.contains { lower.hasPrefix($0) } ? 1.5 : 0
        let near: Double = 1 - abs(at[i] - mark) / max(window, 1)
        return min(gap, 6) + turn + near
    }

    private static func assemble(_ starts: [Int], titles: [String], count: Int, at: [Double]?) -> [AudioChapter] {
        var out: [AudioChapter] = []
        for (n, first) in starts.enumerated() {
            let end: Int = n + 1 < starts.count ? starts[n + 1] : count
            let start: Double? = at.map { $0[first] }
            out.append(AudioChapter(title: titles[n], lines: first..<end, start: start))
        }
        return out
    }

    /// A section named by its first words: "Buffers act in seconds, the\u{2026}".
    static func shortTitle(_ line: String, words limit: Int = 6) -> String {
        let words: [Substring] = line.split(separator: " ")
        guard !words.isEmpty else { return "Section" }
        var title: String = words.prefix(limit).joined(separator: " ")
        while let last = title.last, ",;:.".contains(last) { title.removeLast() }
        return words.count > limit ? title + "\u{2026}" : title
    }

    // MARK: where am I

    /// The section a line is in.
    static func index(containingLine line: Int, in chapters: [AudioChapter]) -> Int? {
        guard !chapters.isEmpty else { return nil }
        if line < chapters[0].lines.lowerBound { return 0 }
        return chapters.lastIndex { $0.lines.lowerBound <= line }
    }

    /// The section playing at `t` seconds into the recording: the last one
    /// that has started, by binary search.
    static func index(atTime t: Double, in chapters: [AudioChapter]) -> Int? {
        guard !chapters.isEmpty else { return nil }
        var low = 0
        var high: Int = chapters.count - 1
        while low < high {
            let mid: Int = (low + high + 1) / 2
            if (chapters[mid].start ?? 0) <= t { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// Where the section playing at `t` ends: the next one's start, or the
    /// end of the recording.
    static func end(after t: Double, in chapters: [AudioChapter], duration: Double) -> Double {
        guard let i = index(atTime: t, in: chapters), i + 1 < chapters.count,
              let next = chapters[i + 1].start else { return duration }
        return next
    }

    /// The section Back goes to from `t`: this one's start when well into it,
    /// the one before when just started.
    static func previous(fromTime t: Double, in chapters: [AudioChapter]) -> Int? {
        guard let i = index(atTime: t, in: chapters) else { return nil }
        let start: Double = chapters[i].start ?? 0
        if t - start > backGrace || i == 0 { return i }
        return i - 1
    }

    /// The same for a lecture read aloud, by line.
    static func previous(fromLine line: Int, in chapters: [AudioChapter]) -> Int? {
        guard let i = index(containingLine: line, in: chapters) else { return nil }
        if line > chapters[i].lines.lowerBound || i == 0 { return i }
        return i - 1
    }

    /// The section after the one holding `i`, or nil at the last.
    static func next(after i: Int?, in chapters: [AudioChapter]) -> Int? {
        guard let i else { return chapters.isEmpty ? nil : 0 }
        return i + 1 < chapters.count ? i + 1 : nil
    }

    /// Roughly how long, at `speed`, until the voice reaching line `end`
    /// when it is on word `word` of line `line`. Never quite zero before it
    /// gets there, so a sleep timer waits for the line rather than an
    /// estimate that ran out early.
    static func secondsToRead(_ lines: [String], line: Int, word: Int, until end: Int, speed: Double) -> Double {
        guard line < end, line < lines.count else { return 0 }
        var words: Int = max(0, lines[line].split(separator: " ").count - word)
        let upper: Int = min(end, lines.count)
        if line + 1 < upper {
            for i in (line + 1)..<upper { words += lines[i].split(separator: " ").count }
        }
        let pace: Double = wordsPerSecond * max(0.25, speed)
        return max(1, Double(words) / pace)
    }

    /// "Section 2 of 7", for the lock screen and the chip.
    static func position(_ i: Int, of chapters: [AudioChapter]) -> String {
        "Section \(i + 1) of \(chapters.count)"
    }
}
