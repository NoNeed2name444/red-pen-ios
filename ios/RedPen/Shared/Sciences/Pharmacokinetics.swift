import Foundation

/// One-compartment pharmacokinetics: the concentration-time curve a student
/// draws for a single dose, repeated doses and an infusion, and the dosing
/// formulas built on clearance and volume of distribution.
///
/// k = CL / Vd and t½ = ln 2 / k. An intravenous bolus gives
/// C = D / Vd × e^(−kt); an oral dose follows the Bateman function,
/// C = F·D·ka / (Vd (ka − k)) × (e^(−kt) − e^(−ka·t)); repeated doses add up
/// (superposition); an infusion at R rises as C = R / CL × (1 − e^(−kt)).
/// Units: mg, L, L/h and hours, so concentrations are mg/L. Foundation only.
enum Pharmacokinetics {

    enum Route: String, CaseIterable, Identifiable {
        case intravenous, oral
        var id: String { rawValue }
        var name: String { self == .intravenous ? "IV bolus" : "By mouth" }
    }

    struct Drug: Hashable {
        /// Volume of distribution, L.
        var volume: Double = 40
        /// Clearance, L/h.
        var clearance: Double = 4
        /// Bioavailability 0...1 (used by mouth).
        var bioavailability: Double = 0.8
        /// Absorption rate constant, per hour (used by mouth).
        var absorption: Double = 1.2

        var elimination: Double { volume > 0 ? clearance / volume : 0 }
        var halfLife: Double { elimination > 0 ? log(2) / elimination : .infinity }
    }

    struct Regimen: Hashable {
        var dose: Double = 500
        /// Hours between doses; 0 for a single dose.
        var interval: Double = 12
        var route: Route = .oral
        /// Doses given (1 for a single dose).
        var doses: Int = 10
    }

    /// Concentration at `t` hours after a single dose given at time 0.
    static func single(_ drug: Drug, dose: Double, route: Route, at t: Double) -> Double {
        guard t >= 0, drug.volume > 0 else { return 0 }
        let k: Double = drug.elimination
        switch route {
        case .intravenous:
            return dose / drug.volume * exp(-k * t)
        case .oral:
            let ka: Double = drug.absorption
            let fd: Double = drug.bioavailability * dose
            if abs(ka - k) < 1e-9 { return fd * k * t * exp(-k * t) / drug.volume }
            return fd * ka / (drug.volume * (ka - k)) * (exp(-k * t) - exp(-ka * t))
        }
    }

    /// Concentration at `t` under a regimen (superposition of each dose).
    static func concentration(_ drug: Drug, _ r: Regimen, at t: Double) -> Double {
        let count: Int = r.interval > 0 ? max(1, r.doses) : 1
        var c: Double = 0
        for i in 0..<count {
            let given: Double = Double(i) * r.interval
            if given > t { break }
            c += single(drug, dose: r.dose, route: r.route, at: t - given)
        }
        return c
    }

    /// The curve from 0 to `hours`.
    static func curve(_ drug: Drug, _ r: Regimen, hours: Double, points: Int = 241) -> [(t: Double, c: Double)] {
        (0..<max(2, points)).map { i in
            let t: Double = hours * Double(i) / Double(max(2, points) - 1)
            return (t, concentration(drug, r, at: t))
        }
    }

    /// Average steady-state concentration: F × dose / (CL × τ). For an IV
    /// bolus F is 1.
    static func averageSteadyState(_ drug: Drug, _ r: Regimen) -> Double {
        guard drug.clearance > 0, r.interval > 0 else { return 0 }
        let f: Double = r.route == .oral ? drug.bioavailability : 1
        return f * r.dose / (drug.clearance * r.interval)
    }

    /// How much more drug is in the body at steady state than after the
    /// first dose: 1 / (1 − e^(−kτ)).
    static func accumulation(_ drug: Drug, interval: Double) -> Double {
        let x: Double = exp(-drug.elimination * interval)
        return x < 1 ? 1 / (1 - x) : .infinity
    }

    /// The fraction of steady state reached after `halfLives` half-lives:
    /// 1 − 0.5ⁿ (about 97% after five).
    static func fractionOfSteadyState(halfLives n: Double) -> Double { 1 - pow(0.5, n) }

    /// Loading dose for a target concentration: C × Vd / F.
    static func loadingDose(target: Double, volume: Double, bioavailability: Double = 1) -> Double {
        guard bioavailability > 0 else { return .infinity }
        return target * volume / bioavailability
    }

    /// Maintenance dose per interval: C × CL × τ / F.
    static func maintenanceDose(target: Double, clearance: Double, interval: Double, bioavailability: Double = 1) -> Double {
        guard bioavailability > 0 else { return .infinity }
        return target * clearance * interval / bioavailability
    }

    /// An infusion at `rate` mg/h, `t` hours after starting.
    static func infusion(_ drug: Drug, rate: Double, at t: Double) -> Double {
        guard drug.clearance > 0, t > 0 else { return 0 }
        return rate / drug.clearance * (1 - exp(-drug.elimination * t))
    }
}
