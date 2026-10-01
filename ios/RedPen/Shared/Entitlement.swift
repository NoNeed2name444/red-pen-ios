import Foundation

/// The two things that can be bought.
///
/// The identifiers must match the products created in App Store Connect
/// exactly; a typo here shows up as a paywall with nothing on it.
enum SubscriptionPlan: String, Codable, CaseIterable, Identifiable {
    case monthly = "com.redpen.pro.monthly"
    case yearly = "com.redpen.pro.yearly"

    var id: String { rawValue }
    var label: String { self == .monthly ? "Monthly" : "Yearly" }
    /// Both subscriptions belong to one group, so switching between them is an
    /// upgrade rather than a second subscription running alongside the first.
    static let groupName = "Red Pen Pro"
}

/// What the phone last managed to confirm about a subscription.
struct EntitlementRecord: Codable, Equatable {
    var plan: SubscriptionPlan?
    var expiresAt: Date?
    /// When the App Store last actually told us this, as opposed to when we
    /// last assumed it.
    var verifiedAt: Date?
    /// Apple keeps trying a failed renewal for a while before giving up. Being
    /// told that is the difference between "they cancelled" and "their card
    /// expired", and those deserve different treatment.
    var inBillingRetry: Bool = false
}

/// What the app is allowed to do.
enum Access: Equatable {
    case free
    case pro(until: Date)
    /// Paid, lapsed, and being given the benefit of the doubt - either because
    /// the card is being retried or because the phone has not been able to ask.
    case grace(until: Date, why: GraceReason)
    case lapsed

    var isPro: Bool {
        switch self {
        case .pro, .grace: return true
        case .free, .lapsed: return false
        }
    }
}

enum GraceReason: Equatable {
    case billingRetry
    case offline
}

/// Turning what we know into what the student may do.
///
/// Two judgements are made here rather than anywhere else, and both are
/// deliberate.
///
/// A renewal that FAILED is not a cancellation. Apple retries a card for days;
/// locking someone out the moment a payment bounces punishes them for their
/// bank's timing, and they have already paid for the month they are in.
///
/// A phone that cannot REACH the App Store is not an unsubscribed phone.
/// Somebody revising on a plane, or in a hospital basement, must not be told
/// they have to buy the app again. So a recently-verified subscription keeps
/// working for a few days offline, and the app asks again the moment it can.
/// The window is short enough that it is not a way to use the app for free, and
/// long enough to cover a weekend without signal.
enum Entitlement {

    /// How long a failed renewal keeps working. Apple's own billing grace
    /// period runs to sixteen days; matching it means the app agrees with the
    /// receipt rather than contradicting it.
    static let billingGrace: TimeInterval = 16 * 24 * 3600
    /// How long a subscription we cannot re-verify keeps working.
    static let offlineGrace: TimeInterval = 3 * 24 * 3600

    static func access(_ record: EntitlementRecord, now: Date = Date()) -> Access {
        guard let expiresAt = record.expiresAt else { return .free }

        if expiresAt > now { return .pro(until: expiresAt) }

        if record.inBillingRetry {
            let until = expiresAt.addingTimeInterval(billingGrace)
            if until > now { return .grace(until: until, why: .billingRetry) }
            return .lapsed
        }

        // Never verified since it lapsed: we may simply not have been able to
        // ask. Somebody who cancelled deliberately gets the same few days, which
        // is a price worth paying for not locking out somebody on a plane.
        if let verifiedAt = record.verifiedAt, verifiedAt <= expiresAt {
            let until = expiresAt.addingTimeInterval(offlineGrace)
            if until > now { return .grace(until: until, why: .offline) }
        }
        return .lapsed
    }

    /// Whether it is worth asking the App Store again.
    ///
    /// Once an hour while subscribed, and immediately once anything has lapsed:
    /// the moment a renewal goes through, the student should stop seeing a
    /// paywall.
    static func shouldRefresh(_ record: EntitlementRecord, now: Date = Date(),
                              every: TimeInterval = 3600) -> Bool {
        guard let verifiedAt = record.verifiedAt else { return true }
        if case .pro = access(record, now: now) {
            return now.timeIntervalSince(verifiedAt) >= every
        }
        return true
    }

    /// What to say about it, in words rather than dates.
    static func summary(_ access: Access, now: Date = Date()) -> String {
        switch access {
        case .free:
            return "No subscription yet."
        case .pro(let until):
            return "Subscribed \u{2014} renews " + short(until)
        case .grace(let until, .billingRetry):
            return "Payment didn't go through. Still working until " + short(until)
                + " while the App Store retries it."
        case .grace(let until, .offline):
            return "Couldn't reach the App Store. Still working until " + short(until) + "."
        case .lapsed:
            return "Your subscription has ended."
        }
    }

    private static func short(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
