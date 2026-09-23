import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif
#if canImport(LocalLLMClientLlama)
import LocalLLMClient
import LocalLLMClientLlama
#endif

/// The two jobs a model does in the app.
///
/// `writer` writes questions, stations and plays the patient (Doctor-R1 on the
/// device, or a hosted model such as Baichuan-M2-32B). `checker` reads what the
/// writer produced and grades it for medical accuracy (MedVAL-4B on the device,
/// or a hosted model given MedVAL's prompt).
enum LLMRole: String, CaseIterable, Identifiable {
    case writer, checker
    var id: String { rawValue }
    var title: String { self == .writer ? "Writing & patient" : "Accuracy checker" }
    var onDeviceModel: MedicalModel { self == .writer ? .doctorR1 : .medval }
}

/// What a role is set to use. Stored as a plain string so it survives in
/// UserDefaults: "off", "device", "cloud", or a hosted provider's id.
///
/// The tiers: Apple's own model and the Gemma fallback are free. Pro buys the
/// medical models - Doctor-R1 and MedVAL on the device, and CramDown Cloud,
/// the larger hosted models through our own worker. A provider added with the
/// student's own key is theirs to pay for, so it is not gated.
enum LLMChoice: Hashable {
    case off
    case device
    case cloud
    case hosted(UUID)

    init(stored: String?) {
        switch stored {
        case nil, "off": self = .off
        case "device": self = .device
        case "cloud": self = .cloud
        case let s?: self = UUID(uuidString: s).map { .hosted($0) } ?? .off
        }
    }

    var stored: String {
        switch self {
        case .off: return "off"
        case .device: return "device"
        case .cloud: return "cloud"
        case .hosted(let id): return id.uuidString
        }
    }
}

/// Owns the on-device medical models and decides, for each role, which backend
/// answers. Everything that wants a model asks here.
@MainActor
final class LocalLLMService: ObservableObject {
    static let shared = LocalLLMService()

    enum Status: Equatable {
        case notDownloaded
        case downloading(fraction: Double)
        case ready
        case failed(String)
        /// This device has too little memory for any build of the model.
        case unsupported
    }

    @Published private(set) var status: [MedicalModel: Status] = [:]
    @Published private(set) var providers: [HostedProvider] = []
    @Published var writerChoice: LLMChoice { didSet { save(writerChoice, for: .writer) } }
    @Published var checkerChoice: LLMChoice { didSet { save(checkerChoice, for: .checker) } }
    /// Check generated questions and stations before they reach the set.
    @Published var checkGenerated: Bool {
        didSet { UserDefaults.standard.set(checkGenerated, forKey: Self.checkGeneratedKey) }
    }

    private var downloads: [MedicalModel: Task<Void, Never>] = [:]
    /// Who is signed in and whether they are Pro, for CramDown Cloud. Held
    /// weakly: both are owned by the app.
    private weak var account: AccountStore?
    private weak var subscriptions: SubscriptionStore?
    private static let checkGeneratedKey = "llm.checkGenerated"

    private init() {
        let defaults = UserDefaults.standard
        writerChoice = LLMChoice(stored: defaults.string(forKey: "llm.choice.writer"))
        checkerChoice = LLMChoice(stored: defaults.string(forKey: "llm.choice.checker"))
        checkGenerated = defaults.object(forKey: Self.checkGeneratedKey) as? Bool ?? true
        providers = HostedProvider.loadAll()
        refreshStatus()
    }

    private func save(_ choice: LLMChoice, for role: LLMRole) {
        UserDefaults.standard.set(choice.stored, forKey: "llm.choice.\(role.rawValue)")
    }

    func attach(account: AccountStore, subscriptions: SubscriptionStore) {
        self.account = account
        self.subscriptions = subscriptions
    }

    /// A real account session (not "this device only", which the server has
    /// never heard of) - the cloud models' key.
    private var cloudToken: String? {
        if let token = account?.token, token != Session.localToken { return token }
        return Self.ownerKey
    }

    /// The owner key, present only in the owner's personal build: CramDown
    /// Cloud without an Apple or Google account.
    private static let ownerKey: String? = {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "RedPenOwnerKey") as? String,
              key.count >= 32 else { return nil }
        return key
    }()

    var isPro: Bool { subscriptions?.isPro ?? false }

    /// True when a role is set to something only Pro can use and this
    /// account isn't Pro - the moment to show the paywall rather than fail.
    func needsPro(_ role: LLMRole) -> Bool {
        guard !isPro else { return false }
        switch choice(for: role) {
        case .device, .cloud: return true
        case .off, .hosted: return false
        }
    }

    /// Why CramDown Cloud can't be used right now, or nil when it can.
    var cloudBlocker: String? {
        if !isPro { return "CramDown Cloud is part of Pro." }
        if cloudToken == nil { return "Sign in with Apple or Google to use CramDown Cloud." }
        return nil
    }

    func choice(for role: LLMRole) -> LLMChoice { role == .writer ? writerChoice : checkerChoice }

    func setChoice(_ choice: LLMChoice, for role: LLMRole) {
        if role == .writer { writerChoice = choice } else { checkerChoice = choice }
    }

    // MARK: which backend answers

    /// The backend a role would use right now, or nil when it is off or not
    /// ready (model not downloaded, provider deleted).
    func backend(for role: LLMRole) -> LLMBackend? {
        switch choice(for: role) {
        case .off:
            return nil
        case .device:
            let model = role.onDeviceModel
            guard isPro, status[model] == .ready, let variant = model.variant() else { return nil }
            return OnDeviceBackend(model: model, variant: variant)
        case .cloud:
            guard cloudBlocker == nil, let token = cloudToken else { return nil }
            return HostedLLMClient(provider: .cloud(for: role), bearer: token)
        case .hosted(let id):
            guard let provider = providers.first(where: { $0.id == id }) else { return nil }
            return HostedLLMClient(provider: provider)
        }
    }

    /// The writer for a free, on-device job when nothing is chosen: Apple's own
    /// model where the device has it. Used by the lecture writers that had no
    /// generator before (Anki, Cases, Textbook).
    func writerOrApple() -> LLMBackend? {
        backend(for: .writer) ?? (AppleFoundationBackend.isAvailable ? AppleFoundationBackend() : nil)
    }

    /// A short line saying what a role is using, for the generate screens.
    func summary(for role: LLMRole) -> String? {
        backend(for: role).map { $0.isOnDevice ? "\($0.label), on this device" : "\($0.label), hosted" }
    }

    // MARK: on-device models

    func refreshStatus() {
        for model in MedicalModel.allCases {
            if case .downloading = status[model] { continue }
            if model.variant() == nil { status[model] = .unsupported }
            else { status[model] = model.isDownloaded ? .ready : .notDownloaded }
        }
    }

    func download(_ model: MedicalModel) {
        guard downloads[model] == nil, let variant = model.variant() else { return }
        status[model] = .downloading(fraction: 0)
        downloads[model] = Task {
            do {
                try FileManager.default.createDirectory(at: MedicalModel.directory,
                                                        withIntermediateDirectories: true)
                let partial = MedicalModel.directory.appendingPathComponent(variant.filename + ".part")
                try await GemmaModel.download(from: variant.url, to: partial) { fraction in
                    Task { @MainActor in self.status[model] = .downloading(fraction: fraction) }
                }
                try Task.checkCancellation()
                model.removeOtherVariants(keeping: variant)
                try GemmaModel.replace(model.localURL(variant), with: partial)
                self.status[model] = .ready
            } catch is CancellationError {
                self.status[model] = model.isDownloaded ? .ready : .notDownloaded
            } catch {
                self.status[model] = .failed(error.localizedDescription)
            }
            self.downloads[model] = nil
        }
    }

    func cancelDownload(_ model: MedicalModel) { downloads[model]?.cancel() }

    func delete(_ model: MedicalModel) {
        cancelDownload(model)
        Task { await OnDeviceRunner.shared.unload() }
        model.removeOtherVariants(keeping: nil)
        refreshStatus()
    }

    // MARK: hosted providers

    func upsert(_ provider: HostedProvider, key: String?) {
        if let index = providers.firstIndex(where: { $0.id == provider.id }) {
            providers[index] = provider
        } else {
            providers.append(provider)
        }
        if let key { Keychain.set(Data(key.utf8), for: provider.keychainAccount) }
        HostedProvider.saveAll(providers)
    }

    func remove(_ provider: HostedProvider) {
        providers.removeAll { $0.id == provider.id }
        Keychain.remove(provider.keychainAccount)
        HostedProvider.saveAll(providers)
        for role in LLMRole.allCases where choice(for: role) == .hosted(provider.id) {
            setChoice(.off, for: role)
        }
    }
}

// MARK: - running a GGUF on the device

/// One on-device model at a time. Doctor-R1 and MedVAL together are larger
/// than any iPhone's memory allowance, so asking for the other one unloads the
/// first. The actor also keeps two screens from generating at once.
actor OnDeviceRunner {
    static let shared = OnDeviceRunner()

    #if canImport(LocalLLMClientLlama)
    private var loaded: (url: URL, client: LlamaClient)?
    #endif

    func unload() {
        #if canImport(LocalLLMClientLlama)
        loaded = nil
        #endif
    }

    func complete(url: URL, turns: [ChatTurn], maxTokens: Int,
                  temperature: Double, context: Int) async throws -> String {
        #if canImport(LocalLLMClientLlama)
        let client: LlamaClient
        if let loaded, loaded.url == url {
            client = loaded.client
        } else {
            loaded = nil // free the other model before loading this one
            client = try await LocalLLMClient.llama(
                url: url,
                parameter: .init(context: context, temperature: Float(temperature),
                                 topK: 40, topP: 0.9))
            loaded = (url, client)
        }
        let input = LLMInput.chat(turns.map { turn -> LLMInput.Message in
            switch turn.role {
            case .system: return .system(turn.text)
            case .user: return .user(turn.text)
            case .assistant: return .assistant(turn.text)
            }
        })
        var text = ""
        // llama.cpp has no per-call token limit here, so the reply is cut off
        // by length instead: about four characters to a token.
        let limit = maxTokens * 4
        for try await chunk in try await client.textStream(from: input) {
            try Task.checkCancellation()
            text += chunk
            if text.count >= limit { break }
        }
        return text
        #else
        throw LLMError.notReady("On-device medical models aren't available in this build \u{2014} add a hosted model in AI models.")
        #endif
    }
}

struct OnDeviceBackend: LLMBackend {
    let model: MedicalModel
    let variant: MedicalModel.Variant

    var label: String { model.displayName }
    var isOnDevice: Bool { true }
    /// About 2,000 tokens of source, leaving room for the instructions and the
    /// answer inside an 8K context.
    var promptBudgetChars: Int { 8_000 }

    func complete(_ turns: [ChatTurn], maxTokens: Int, temperature: Double) async throws -> String {
        let raw = try await OnDeviceRunner.shared.complete(
            url: model.localURL(variant), turns: LLMText.noThinking(turns), maxTokens: maxTokens,
            temperature: temperature, context: 8192)
        let text = LLMText.stripThinking(raw)
        guard !text.isEmpty else { throw LLMError.emptyReply }
        return text
    }
}

// MARK: - Apple's on-device model as a backend

/// Apple Intelligence's on-device model behind the same interface, so the
/// lecture writers work for free on any device that has it.
struct AppleFoundationBackend: LLMBackend {
    var label: String { "Apple on-device model" }
    var isOnDevice: Bool { true }
    var promptBudgetChars: Int { 10_000 }

    static var isAvailable: Bool { MCQGenerator.availability.isAvailable }

    func complete(_ turns: [ChatTurn], maxTokens: Int, temperature: Double) async throws -> String {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { throw LLMError.notReady("Needs iOS 26.") }
        let system = turns.filter { $0.role == .system }.map(\.text).joined(separator: "\n\n")
        let conversation = turns.filter { $0.role != .system }
            .map { ($0.role == .user ? "" : "Assistant: ") + $0.text }
            .joined(separator: "\n\n")
        let session = LanguageModelSession(instructions: Instructions { system })
        let response = try await session.respond(
            to: conversation,
            options: GenerationOptions(temperature: temperature, maximumResponseTokens: maxTokens))
        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw LLMError.emptyReply }
        return text
        #else
        throw LLMError.notReady("Apple's on-device model isn't available in this build.")
        #endif
    }
}

// MARK: - the checker the student chose, for screens that just want "check this"

extension AccuracyChecker {
    @MainActor static var backend: LLMBackend? { LocalLLMService.shared.backend(for: .checker) }
    @MainActor static var isAvailable: Bool { backend != nil }

    @MainActor
    static func check(instruction: String, input: String, output: String) async throws -> AccuracyVerdict {
        guard let backend else {
            throw LLMError.notReady("Choose an accuracy checker in AI models first.")
        }
        return try await check(instruction: instruction, input: input, output: output, using: backend)
    }
}
