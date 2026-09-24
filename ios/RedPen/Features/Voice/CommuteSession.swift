import Foundation
import MediaPlayer
import Combine

/// The engine behind commute mode: read a question aloud, listen for the
/// answer, say whether it was right, rate the card, move on.
///
/// Written as one plain loop - say, listen, judge, say - because that is the
/// order it happens in; VoiceSpeaker and VoiceListener each wait until they
/// are done. Pausing bumps `generation`, and every step checks it, so a loop
/// that was paused mid-sentence stops at the next step instead of talking
/// over the one that replaces it.
@MainActor
final class CommuteSession: ObservableObject {

    enum Item {
        case card(ReviewPlan.Due)
        case question(MCQQuestion, setName: String)
    }

    struct Line: Identifiable {
        enum Kind { case app, you, right, wrong, note }
        let id = UUID()
        var kind: Kind
        var text: String
    }

    @Published private(set) var items: [Item] = []
    @Published private(set) var position = 0
    @Published private(set) var running = false
    @Published private(set) var lines: [Line] = []
    @Published private(set) var right = 0
    @Published private(set) var wrong = 0
    /// What the phone allowed, once asked. Nil until the first start.
    @Published private(set) var hearing: VoiceAccess.Hearing?

    let speaker = VoiceSpeaker()
    let listener = VoiceListener()

    private weak var reviews: ReviewStore?
    private var loop: Task<Void, Never>?
    private var generation = 0
    /// Cards already sent round again this sitting; a card is repeated once,
    /// not until it is got right, or a hard card holds up the whole drive.
    private var requeued = Set<UUID>()
    private var remoteTargets: [(command: MPRemoteCommand, token: Any)] = []

    var remaining: Int { max(0, items.count - position) }
    var finished: Bool { !items.isEmpty && position >= items.count }

    // MARK: controls

    func load(_ items: [Item], reviews: ReviewStore) {
        end()
        self.items = items
        self.reviews = reviews
        position = 0
        lines = []
        right = 0
        wrong = 0
        requeued = []
    }

    func toggle() { running ? pause() : start() }

    func start() {
        guard !running, position < items.count else { return }
        running = true
        generation += 1
        let current = generation
        attachRemote()
        updateNowPlaying()
        loop = Task { await self.run(current) }
    }

    func pause(quietly: Bool = false) {
        guard running else { return }
        running = false
        generation += 1
        loop?.cancel()
        loop = nil
        speaker.stop()
        listener.stop()
        updateNowPlaying()
        if !quietly { add(.note, "Paused.") }
    }

    /// Past whatever is being asked, without marking it.
    func skip() {
        let wasRunning = running
        pause(quietly: true)
        guard position < items.count else { return }
        add(.note, "Skipped.")
        position += 1
        if wasRunning { start() }
    }

    /// Stops everything and gives the audio and the headphone buttons back.
    func end() {
        pause(quietly: true)
        detachRemote()
        VoiceAccess.deactivate()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func clear() {
        end()
        items = []
        position = 0
        lines = []
    }

    // MARK: the loop

    private enum Outcome { case next, same }

    private func alive(_ current: Int) -> Bool {
        current == generation && running && !Task.isCancelled
    }

    private func run(_ current: Int) async {
        if hearing == nil { hearing = await VoiceAccess.request() }
        guard alive(current) else { return }
        VoiceAccess.activate()
        if position == 0, lines.isEmpty {
            let hint = hearing?.canHear == true
                ? "Answer out loud after each question. You can say skip, repeat, or I don't know."
                : "I can't hear you, so after each question I'll pause, then read the answer."
            await say("Commute mode. \(items.count) to go. \(hint)", current)
        }
        while alive(current), position < items.count {
            let outcome = await play(items[position], current)
            guard alive(current) else { return }
            if outcome == .next { position += 1 }
        }
        guard alive(current) else { return }
        let summary = wrong == 0
            ? "That's everything. \(right) right."
            : "That's everything. \(right) right, \(wrong) to go over again."
        add(.note, summary)
        await say(summary, current)
        running = false
        updateNowPlaying()
    }

    private func play(_ item: Item, _ current: Int) async -> Outcome {
        // the next item's first line is fetched while this one is played
        prefetchNext()
        switch item {
        case .card(let due): return await playCard(due, current)
        case .question(let question, let setName): return await playQuestion(question, setName: setName, current)
        }
    }

    // MARK: a card

    private func playCard(_ due: ReviewPlan.Due, _ current: Int) async -> Outcome {
        let card = due.card
        let prompt = QuizFromCards.stem(of: card)
        let answer = Self.answerLines(of: card)
        let answerText = answer.joined(separator: "; ")
        add(.app, prompt)
        await say("\(Self.deckName(due.setName)). \(prompt)", current)
        guard alive(current) else { return .same }

        guard let heard = await hear(current, hints: answer) else {
            // nobody to hear: time to think, then the answer, and no rating -
            // an answer nobody gave can't be marked
            await thinkingPause(current)
            guard alive(current) else { return .same }
            add(.note, "Answer: \(answerText). Not rated - rate it on Due today.")
            await say("The answer: \(answerText).", current)
            return .next
        }
        guard alive(current) else { return .same }

        let command = SpokenAnswer.command(in: heard)
        switch command {
        case .again?:
            return .same
        case .skip?:
            add(.note, "Skipped.")
            await say("Skipped.", current)
            return .next
        case .pause?:
            pause()
            return .same
        default:
            break
        }

        let correct = command != .dontKnow && !heard.isEmpty && SpokenAnswer.matches(heard, answer: answer)
        mark(card: due, correct: correct)
        let why = SpokenAnswer.firstSentence(card.why)
        if correct {
            add(.right, "Right \u{2014} \(answerText)")
            await say("Correct. \(answerText).", current)
        } else {
            add(.wrong, "Answer: \(answerText)" + (why.isEmpty ? "" : "\n\(why)"))
            let opener = heard.isEmpty ? "I didn't hear an answer." : "Not quite."
            await say("\(opener) It's \(answerText). \(why)", current)
        }
        return .next
    }

    /// What a card asks you to say: a cloze's hidden words, or the answer
    /// bullets.
    static func answerLines(of card: AnkiCard) -> [String] {
        if card.type == .cloze {
            return QuizFromCards.answer(of: card).map { [$0] } ?? []
        }
        return card.bullets.map(Highlight.plain)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Correct is Good and wrong is Again, through the same store the review
    /// screens use, so a card answered in the car is answered everywhere.
    private func mark(card due: ReviewPlan.Due, correct: Bool) {
        if correct { right += 1 } else { wrong += 1 }
        reviews?.rate(correct ? .good : .again, card: due.card)
        StudyLog.shared.record()
        if !correct, !requeued.contains(due.card.id) {
            requeued.insert(due.card.id)
            items.append(.card(due))
        }
    }

    // MARK: a question

    private func playQuestion(_ question: MCQQuestion, setName: String, _ current: Int) async -> Outcome {
        let letters = SpokenAnswer.letters
        let options = Array(question.options.prefix(letters.count))
        let listed = options.enumerated().map { "\(letters[$0.offset]). \($0.element)" }
        add(.app, ([question.stem] + listed).joined(separator: "\n"))
        speaker.prefetch(listed.joined(separator: ". \n"))
        await say("\(Self.deckName(setName)). \(question.stem)", current)
        guard alive(current) else { return .same }
        await say(listed.joined(separator: ". \n"), current)
        guard alive(current) else { return .same }

        let key = letters[min(max(question.correctIndex, 0), letters.count - 1)]
        let keyText = options.indices.contains(question.correctIndex) ? options[question.correctIndex] : ""
        let why = SpokenAnswer.firstSentence(question.explanation)

        guard var heard = await hear(current, hints: options) else {
            await thinkingPause(current)
            guard alive(current) else { return .same }
            add(.note, "Answer: \(key). \(keyText)")
            await say("The answer is \(key): \(keyText). \(why)", current)
            return .next
        }
        guard alive(current) else { return .same }

        switch SpokenAnswer.command(in: heard) {
        case .again?: return .same
        case .skip?:
            add(.note, "Skipped.")
            await say("Skipped.", current)
            return .next
        case .pause?:
            pause()
            return .same
        default: break
        }

        var choice = SpokenAnswer.option(in: heard, options: options)
        if choice == nil, !heard.isEmpty, SpokenAnswer.command(in: heard) != .dontKnow {
            // one more go: the recogniser is at its worst on a lone letter
            await say("Sorry, which letter? A to \(letters[max(0, options.count - 1)]).", current)
            guard alive(current) else { return .same }
            if let again = await hear(current, hints: options) {
                heard = again
                choice = SpokenAnswer.option(in: heard, options: options)
            }
            guard alive(current) else { return .same }
        }

        let correct = choice == question.correctIndex
        if correct { right += 1 } else { wrong += 1 }
        StudyLog.shared.record()
        if correct {
            add(.right, "Right \u{2014} \(key). \(keyText)")
            await say("Correct, \(key). \(why)", current)
        } else {
            add(.wrong, "Answer: \(key). \(keyText)" + (why.isEmpty ? "" : "\n\(why)"))
            let opener = choice.map { "No, not \(letters[$0])." } ?? "No answer."
            await say("\(opener) It's \(key): \(keyText). \(why)", current)
        }
        return .next
    }

    // MARK: speaking and listening

    private func say(_ text: String, _ current: Int) async {
        guard alive(current) else { return }
        await speaker.say(text)
    }

    /// Listens for one answer. Nil when there is no way to hear one: the
    /// permission was refused, or the microphone would not start.
    private func hear(_ current: Int, hints: [String]) async -> String? {
        guard alive(current), hearing?.canHear == true else { return nil }
        guard let heard = await listener.listenOnce(hints: Array(hints.prefix(20))) else {
            if let failure = listener.failure { add(.note, failure) }
            return nil
        }
        if !heard.isEmpty { add(.you, heard) }
        return heard
    }

    /// Starts fetching the natural voice for the next item's first line, so
    /// there is no pause before it.
    private func prefetchNext() {
        let next = position + 1
        guard items.indices.contains(next) else { return }
        speaker.prefetch(Self.opening(of: items[next]))
    }

    /// The first thing said for an item - the same words `playCard` and
    /// `playQuestion` say, so the fetched audio is the audio used.
    private static func opening(of item: Item) -> String {
        switch item {
        case .card(let due):
            return "\(deckName(due.setName)). \(QuizFromCards.stem(of: due.card))"
        case .question(let question, let setName):
            return "\(deckName(setName)). \(question.stem)"
        }
    }

    /// Time to think of the answer when it can't be said aloud.
    private func thinkingPause(_ current: Int) async {
        guard alive(current) else { return }
        try? await Task.sleep(for: .seconds(5))
    }

    private func add(_ kind: Line.Kind, _ text: String) {
        lines.append(Line(kind: kind, text: text))
    }

    /// "Example: Cardiology" is a folder label, not something to say.
    private static func deckName(_ name: String) -> String {
        name.replacingOccurrences(of: "Example: ", with: "")
    }

    // MARK: headphones and the lock screen

    private enum RemoteAction { case play, pause, toggle, next }

    private func handle(_ action: RemoteAction) {
        switch action {
        case .play: start()
        case .pause: pause()
        case .toggle: toggle()
        case .next: skip()
        }
    }

    private func attachRemote() {
        guard remoteTargets.isEmpty else { return }
        let center = MPRemoteCommandCenter.shared()
        let wanted: [(MPRemoteCommand, RemoteAction)] = [
            (center.playCommand, .play), (center.pauseCommand, .pause),
            (center.togglePlayPauseCommand, .toggle), (center.nextTrackCommand, .next),
        ]
        for (command, action) in wanted {
            command.isEnabled = true
            remoteTargets.append((command, Self.target(command, owner: self, action: action)))
        }
    }

    private func detachRemote() {
        for (command, token) in remoteTargets { command.removeTarget(token) }
        remoteTargets = []
    }

    /// Made outside the main actor: the handler is called by MediaPlayer, and
    /// only hops back here with the action.
    nonisolated private static func target(_ command: MPRemoteCommand, owner: CommuteSession,
                                           action: RemoteAction) -> Any {
        command.addTarget { [weak owner] _ in
            guard let session = owner else { return .commandFailed }
            Task { @MainActor in session.handle(action) }
            return .success
        }
    }

    /// The lock screen's now-playing card, which is also what routes the
    /// headphone buttons here.
    private func updateNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "Commute mode",
            MPMediaItemPropertyArtist: Brand.name,
            MPNowPlayingInfoPropertyPlaybackRate: running ? 1.0 : 0.0,
        ]
    }
}
