import Foundation

// Study Lens: keeping one chip per question while the camera moves.
//
// Every processed frame gives a fresh list of detections. The same question
// read twice is rarely read identically - a word dropped at the edge, a
// letter misread - and its box shifts as the phone moves. The tracker matches
// each detection to the question it already knows (same key, or mostly the
// same words near the same place), eases the box towards the new position so
// a chip glides instead of jumping, shows a question only once it has been
// seen twice (no flicker from a half-read line), and lets it go after a few
// frames without it.
//
// The gate decides when frames are worth reading at all: not while the phone
// and the page are both still (nothing new to find, and every read costs
// battery), and at a lower rate on the Smooth graphics setting.
//
// Foundation only; tested in Tests/LensTests.swift.

/// One question the lens is following.
struct LensTrack: Identifiable, Hashable {
    let id: Int
    var question: DetectedQuestion
    /// The eased box, normalised, origin top left.
    var box: CGRect
    var hits: Int
    var misses: Int
}

struct LensTracker {
    private(set) var tracks: [LensTrack] = []
    private var nextID: Int = 1

    /// How far a box moves towards its new place each frame, 0...1.
    var easing: Double = 0.45
    /// Frames a question may go unseen before its chip goes.
    var maxMisses: Int = 4
    /// Frames a question must be seen before its chip shows.
    var minHits: Int = 2
    /// The most chips on screen at once.
    var maxVisible: Int = 6

    init(minHits: Int = 2) {
        self.minHits = minHits
    }

    /// Takes one frame's detections.
    mutating func update(_ found: [DetectedQuestion]) {
        var pairs: [(track: Int, found: Int, score: Double)] = []
        for (t, track) in tracks.enumerated() {
            for (f, q) in found.enumerated() {
                let s: Double = Self.matchScore(track, q)
                if s > 0 { pairs.append((track: t, found: f, score: s)) }
            }
        }
        pairs.sort { $0.score > $1.score }
        var usedTracks: Set<Int> = []
        var usedFound: Set<Int> = []
        for pair in pairs where !usedTracks.contains(pair.track) && !usedFound.contains(pair.found) {
            usedTracks.insert(pair.track)
            usedFound.insert(pair.found)
            tracks[pair.track] = Self.merged(tracks[pair.track], with: found[pair.found], easing: easing)
        }
        for t in tracks.indices where !usedTracks.contains(t) {
            tracks[t].misses += 1
        }
        tracks.removeAll { $0.misses > maxMisses }
        for (f, q) in found.enumerated() where !usedFound.contains(f) {
            tracks.append(LensTrack(id: nextID, question: q, box: q.box, hits: 1, misses: 0))
            nextID += 1
        }
    }

    /// Forgets everything (a new photo, the lens closed).
    mutating func reset() {
        tracks = []
    }

    /// The chips to show: seen often enough, seen lately, at most
    /// `maxVisible` - the ones nearest the middle of the view, which is where
    /// the student is pointing - in reading order.
    var visible: [LensTrack] {
        let shown: [LensTrack] = tracks.filter { $0.hits >= minHits && $0.misses <= 1 }
        let centre = CGPoint(x: 0.5, y: 0.5)
        let nearest: [LensTrack] = shown.sorted { Self.distance($0.box, centre) < Self.distance($1.box, centre) }
        let kept: [LensTrack] = Array(nearest.prefix(maxVisible))
        return kept.sorted { a, b in
            if abs(a.box.minY - b.box.minY) > 0.02 { return a.box.minY < b.box.minY }
            return a.box.minX < b.box.minX
        }
    }

    /// The keys on screen, to tell whether the scene changed.
    var visibleKeys: Set<String> { Set(visible.map { $0.question.key }) }

    // MARK: matching

    /// How well a detection fits a track: 0 for not at all. The same key
    /// always matches; otherwise the words must mostly agree and the boxes be
    /// near each other.
    static func matchScore(_ track: LensTrack, _ q: DetectedQuestion) -> Double {
        let near: Double = max(0, 1 - distance(track.box, q.box) * 2.5)
        if track.question.key == q.key { return 2 + near }
        let words: Double = LensHash.similarity(track.question.fullText, q.fullText)
        guard words >= 0.55, near > 0 else { return 0 }
        return words + near * 0.5
    }

    static func distance(_ a: CGRect, _ b: CGRect) -> Double {
        let dx: Double = Double(a.midX - b.midX)
        let dy: Double = Double(a.midY - b.midY)
        return (dx * dx + dy * dy).squareRoot()
    }

    static func distance(_ a: CGRect, _ p: CGPoint) -> Double {
        let dx: Double = Double(a.midX - p.x)
        let dy: Double = Double(a.midY - p.y)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// The track after seeing `q` again: the box eased towards the new one
    /// (snapped when it jumped - the page changed), and the fuller reading of
    /// the question kept.
    static func merged(_ track: LensTrack, with q: DetectedQuestion, easing: Double) -> LensTrack {
        var out = track
        out.hits += 1
        out.misses = 0
        let jumped: Bool = distance(track.box, q.box) > 0.3
        out.box = jumped ? q.box : ease(track.box, q.box, easing)
        if isFuller(q, than: track.question) {
            out.question = q
        } else {
            out.question.box = q.box
        }
        return out
    }

    /// Whether `a` holds more of the question than `b`: more options, or as
    /// many and a longer stem.
    static func isFuller(_ a: DetectedQuestion, than b: DetectedQuestion) -> Bool {
        if a.options.count != b.options.count { return a.options.count > b.options.count }
        return a.stem.count > b.stem.count
    }

    static func ease(_ from: CGRect, _ to: CGRect, _ k: Double) -> CGRect {
        let x: Double = lerp(Double(from.minX), Double(to.minX), k)
        let y: Double = lerp(Double(from.minY), Double(to.minY), k)
        let w: Double = lerp(Double(from.width), Double(to.width), k)
        let h: Double = lerp(Double(from.height), Double(to.height), k)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    static func lerp(_ a: Double, _ b: Double, _ k: Double) -> Double {
        a + (b - a) * k
    }
}

// MARK: - When to read a frame

/// Whether the next frame is worth reading. Reading costs battery; a phone
/// held still over a page it has already read has nothing new to find.
struct LensActivityGate {
    /// Seconds of stillness - no movement and no new questions - before
    /// reading pauses.
    var stillAfter: Double = 3
    /// Movement (g of user acceleration plus rad/s of rotation, summed) that
    /// counts as the phone moving.
    var moveThreshold: Double = 0.12
    /// Seconds between reads: more often on High quality, less on Smooth.
    var interval: Double = 0.3

    private(set) var lastMove: Double = -1_000
    private(set) var lastChange: Double = -1_000
    private(set) var lastRead: Double = -1_000
    private(set) var started: Bool = false

    init(smooth: Bool) {
        interval = Self.interval(smooth: smooth)
    }

    static func interval(smooth: Bool) -> Double { smooth ? 0.7 : 0.3 }

    /// A motion sample.
    mutating func noteMotion(_ magnitude: Double, at time: Double) {
        if magnitude >= moveThreshold { lastMove = time }
    }

    /// The outcome of a read: whether it found anything new.
    mutating func noteRead(changed: Bool, at time: Double) {
        lastRead = time
        started = true
        if changed { lastChange = time }
    }

    /// Wakes reading at once (the student tapped Resume, or came back).
    mutating func wake(at time: Double) {
        lastMove = time
    }

    /// Reading is live: something moved or changed lately, or nothing has
    /// been read yet.
    func isActive(at time: Double) -> Bool {
        guard started else { return true }
        let recent: Double = max(lastMove, lastChange)
        return time - recent < stillAfter
    }

    /// Read this frame: live, and the interval since the last read is up.
    func shouldRead(at time: Double) -> Bool {
        isActive(at: time) && time - lastRead >= interval
    }
}

// MARK: - Where chips sit

enum LensLayout {
    /// A chip's top-left corner for each box, in points: at the box's top
    /// left, kept inside the view, and moved down past any chip already
    /// placed that it would cover.
    static func chipOrigins(_ boxes: [CGRect], chip: CGSize, in view: CGSize) -> [CGPoint] {
        var placed: [CGRect] = []
        var out: [CGPoint] = []
        let maxX: Double = max(0, Double(view.width - chip.width) - 8)
        let maxY: Double = max(0, Double(view.height - chip.height) - 8)
        for box in boxes {
            let x0: Double = Double(box.minX * view.width)
            let y0: Double = Double(box.minY * view.height) - Double(chip.height) * 0.6
            var x: Double = min(max(8, x0), maxX)
            var y: Double = min(max(8, y0), maxY)
            var rect = CGRect(x: x, y: y, width: Double(chip.width), height: Double(chip.height))
            var tries: Int = 0
            while tries < 8, let hit = placed.first(where: { $0.intersects(rect) }) {
                y = Double(hit.maxY) + 4
                if y > maxY {
                    y = maxY
                    x = min(Double(hit.maxX) + 4, maxX)
                }
                rect = CGRect(x: x, y: y, width: Double(chip.width), height: Double(chip.height))
                tries += 1
            }
            placed.append(rect)
            out.append(CGPoint(x: x, y: y))
        }
        return out
    }

    /// A box normalised to an image of `image` size, drawn aspect-FILL into
    /// a view of `view` size (the live preview), in the view's points.
    static func fill(_ box: CGRect, image: CGSize, view: CGSize) -> CGRect {
        let scale: Double = max(Double(view.width / max(image.width, 1)), Double(view.height / max(image.height, 1)))
        return placed(box, image: image, view: view, scale: scale)
    }

    /// The same, drawn aspect-FIT (a still photo shown whole).
    static func fit(_ box: CGRect, image: CGSize, view: CGSize) -> CGRect {
        let scale: Double = min(Double(view.width / max(image.width, 1)), Double(view.height / max(image.height, 1)))
        return placed(box, image: image, view: view, scale: scale)
    }

    private static func placed(_ box: CGRect, image: CGSize, view: CGSize, scale: Double) -> CGRect {
        let drawnW: Double = Double(image.width) * scale
        let drawnH: Double = Double(image.height) * scale
        let offX: Double = (Double(view.width) - drawnW) / 2
        let offY: Double = (Double(view.height) - drawnH) / 2
        let x: Double = offX + Double(box.minX) * drawnW
        let y: Double = offY + Double(box.minY) * drawnH
        return CGRect(x: x, y: y, width: Double(box.width) * drawnW, height: Double(box.height) * drawnH)
    }

    /// A box from Vision (origin bottom left) with its origin at the top left.
    static func flipped(_ visionBox: CGRect) -> CGRect {
        CGRect(x: visionBox.minX, y: 1 - visionBox.maxY, width: visionBox.width, height: visionBox.height)
    }

    /// A box in points within `size` as a normalised one.
    static func normalised(_ rect: CGRect, in size: CGSize) -> CGRect {
        let w: Double = max(1, Double(size.width))
        let h: Double = max(1, Double(size.height))
        return CGRect(x: Double(rect.minX) / w, y: Double(rect.minY) / h,
                      width: Double(rect.width) / w, height: Double(rect.height) / h)
    }
}
