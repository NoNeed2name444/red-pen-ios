import Foundation

/// Decides which backend answers. Everything that wants a model asks here,
/// and the answer is always the same one: the worker's writer route
/// (WriterRoute), for every role. There is no writer to choose and no model
/// to download or add (the owner, 22 Oct); the worker answers from its hosted
/// writer, behind PRO_PAYS and its spend caps, and without it nothing is
/// written (the owner, 23 Oct: "Lock it"). No key is ever in the app.
@MainActor
final class LocalLLMService: ObservableObject {
    static let shared = LocalLLMService()

    /// Check generated questions and stations before they reach the set
    /// (Settings > Verify what is generated).
    @Published var checkGenerated: Bool {
        didSet { UserDefaults.standard.set(checkGenerated, forKey: Self.checkGeneratedKey) }
    }

    /// Who is signed in and whether they are Pro, for CramDown Cloud. Held
    /// weakly: both are owned by the app.
    private weak var account: AccountStore?
    private weak var subscriptions: SubscriptionStore?
    private static let checkGeneratedKey = "llm.checkGenerated"

    private init() {
        checkGenerated = UserDefaults.standard.object(forKey: Self.checkGeneratedKey) as? Bool ?? true
        // the phone writes nothing now: earlier builds' model files go
        RetiredModels.removeAll()
    }

    func attach(account: AccountStore, subscriptions: SubscriptionStore) {
        self.account = account
        self.subscriptions = subscriptions
    }

    /// A real account session (not "this device only", which the server has
    /// never heard of) - the cloud models' key.
    var cloudToken: String? {
        if let token = account?.token, token != Session.localToken { return token }
        return Self.ownerKey
    }

    /// Started "on this device only": no server account behind it.
    var isLocalOnly: Bool { account?.token == Session.localToken }

    /// Whose background jobs a bearer reaches: "owner" for the owner key, or
    /// the signed-in account's id. The server keeps jobs per identity, so a
    /// job is only ever asked about with the one it was made under.
    func cloudIdentity(for bearer: String) -> String? {
        if let key = Self.ownerKey, bearer == key { return "owner" }
        if let token = account?.token, bearer == token { return account?.account?.id }
        return nil
    }

    /// The bearer that reaches jobs made under `identity`, if this device can
    /// still reach them: nil when that account is no longer signed in here.
    /// A job from before identities were recorded is asked about as before.
    func cloudBearer(for identity: String?) -> String? {
        guard let identity else { return cloudToken }
        if identity == "owner" { return Self.ownerKey }
        guard let token = account?.token, token != Session.localToken,
              account?.account?.id == identity else { return nil }
        return token
    }

    /// The owner key, present only in the owner's personal build: CramDown
    /// Cloud without an Apple or Google account.
    private static let ownerKey: String? = {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "RedPenOwnerKey") as? String,
              key.count >= 32 else { return nil }
        return key
    }()

    var isPro: Bool { subscriptions?.isPro ?? false }

    /// Why CramDown Cloud can't be used right now, or nil when it can.
    var cloudBlocker: String? {
        WriterRoute.blocker(isPro: isPro, bearer: cloudToken, brand: Brand.name, google: GoogleSignIn.isConfigured)
    }

    // MARK: which backend answers

    /// The backend a role uses: the worker's writer route, or nil while the
    /// cloud is blocked (not Pro, not signed in).
    func backend(for role: LLMRole) -> LLMBackend? {
        guard cloudBlocker == nil, let token = cloudToken else { return nil }
        return HostedLLMClient(role: role, bearer: token)
    }

    /// The writer every text job uses.
    func writer() -> LLMBackend? { backend(for: .writer) }

    /// Why there is no writer, in the cloud's own words.
    var noWriter: String { cloudBlocker ?? "\(Brand.name) Cloud can't be reached right now." }

    /// A short line saying what writes, for the generate screens.
    func summary(for role: LLMRole) -> String? {
        backend(for: role).map { "\($0.label), hosted" }
    }
}
