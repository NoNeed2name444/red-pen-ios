import Foundation

/// The physiology tools' arithmetic: membrane potentials, the nerve action
/// potential, the oxygen-haemoglobin curve, capillary fluid exchange, the
/// lung's gas equations, renal clearance and the haemodynamic formulas.
///
/// Every number here comes from a published equation, written out in its
/// doc comment, so the screens draw what the textbook formula gives and no
/// copyrighted figure is copied. Foundation only: numbers in, numbers out,
/// so all of it is tested on Linux (SciencePhysiologyTests).
enum Membrane {

    /// R, J/(mol·K), and F, C/mol (CODATA 2018, exact in SI).
    static let gasConstant: Double = 8.314_462_618
    static let faraday: Double = 96_485.332_12

    /// RT/F in millivolts at `celsius` (26.7 mV at 37 °C).
    static func thermalVoltage(celsius: Double = 37) -> Double {
        gasConstant * (celsius + 273.15) / faraday * 1000
    }

    /// The Nernst equation: E = (RT/zF) ln([out]/[in]), in mV.
    /// Nil when a concentration is not positive or the valence is zero.
    static func nernst(valence z: Int, outside: Double, inside: Double, celsius: Double = 37) -> Double? {
        guard z != 0, outside > 0, inside > 0 else { return nil }
        return thermalVoltage(celsius: celsius) / Double(z) * log(outside / inside)
    }

    /// Ion concentrations in mmol/L, inside and outside a typical mammalian
    /// cell (the usual teaching values).
    struct Ions: Hashable {
        var kOut: Double = 4, kIn: Double = 140
        var naOut: Double = 145, naIn: Double = 12
        var clOut: Double = 110, clIn: Double = 10
    }

    /// Relative permeabilities at rest, K : Na : Cl = 1 : 0.04 : 0.45.
    struct Permeability: Hashable {
        var k: Double = 1, na: Double = 0.04, cl: Double = 0.45
    }

    /// The Goldman-Hodgkin-Katz voltage equation, in mV:
    /// Vm = (RT/F) ln((pK[K]o + pNa[Na]o + pCl[Cl]i) / (pK[K]i + pNa[Na]i + pCl[Cl]o)).
    /// Chloride's inside and outside swap because it carries a negative charge.
    static func goldman(_ ions: Ions = Ions(), _ p: Permeability = Permeability(), celsius: Double = 37) -> Double? {
        let top: Double = p.k * ions.kOut + p.na * ions.naOut + p.cl * ions.clIn
        let bottom: Double = p.k * ions.kIn + p.na * ions.naIn + p.cl * ions.clOut
        guard top > 0, bottom > 0 else { return nil }
        return thermalVoltage(celsius: celsius) * log(top / bottom)
    }
}

/// The Hodgkin-Huxley model of the squid giant axon (1952), in the modern
/// convention with rest at -65 mV, integrated with fourth-order Runge-Kutta.
///
/// C dV/dt = I − gNa·m³h(V − ENa) − gK·n⁴(V − EK) − gL(V − EL),
/// with each gate x following dx/dt = αx(1 − x) − βx·x and the original
/// rate functions (ms⁻¹, V in mV). The knobs the screen offers are the ones
/// a student meets in pharmacology and pathology: sodium channel block
/// (tetrodotoxin, local anaesthetics), potassium channel block, and the
/// outside potassium that moves EK the way the Nernst equation says.
enum HodgkinHuxley {

    struct Parameters: Hashable {
        /// Peak conductances, mS/cm².
        var gNa: Double = 120, gK: Double = 36, gL: Double = 0.3
        /// Reversal potentials, mV.
        var eNa: Double = 50, eK: Double = -77, eL: Double = -54.387
        /// Membrane capacitance, µF/cm².
        var capacitance: Double = 1

        /// The same axon with sodium channels `block` blocked (0...1).
        func sodiumBlocked(_ block: Double) -> Parameters {
            var p: Parameters = self
            p.gNa = gNa * (1 - min(1, max(0, block)))
            return p
        }

        /// The same axon with potassium channels `block` blocked (0...1).
        func potassiumBlocked(_ block: Double) -> Parameters {
            var p: Parameters = self
            p.gK = gK * (1 - min(1, max(0, block)))
            return p
        }

        /// EK moved by the Nernst shift for outside potassium going from
        /// 4 mmol/L to `kOut` (37 °C), as in hyper- or hypokalaemia.
        func outsidePotassium(_ kOut: Double) -> Parameters {
            var p: Parameters = self
            p.eK = eK + Membrane.thermalVoltage() * log(max(0.1, kOut) / 4)
            return p
        }
    }

    /// A square current pulse: `amplitude` µA/cm² from `start` for
    /// `duration` ms.
    struct Pulse: Hashable {
        var start: Double
        var duration: Double
        var amplitude: Double
        func current(at t: Double) -> Double { t >= start && t < start + duration ? amplitude : 0 }
    }

    struct State: Hashable {
        var v: Double, m: Double, h: Double, n: Double
    }

    struct Sample: Hashable {
        var t: Double
        var v: Double
        var m: Double, h: Double, n: Double
        /// Ionic currents, µA/cm² (positive outward).
        var iNa: Double, iK: Double
        var stimulus: Double
    }

    // The rate functions. Their 0/0 points (V = -55 for αn, -40 for αm) are
    // replaced by their limits.
    static func alphaN(_ v: Double) -> Double {
        let x: Double = v + 55
        return abs(x) < 1e-7 ? 0.1 : 0.01 * x / (1 - exp(-x / 10))
    }
    static func betaN(_ v: Double) -> Double { 0.125 * exp(-(v + 65) / 80) }
    static func alphaM(_ v: Double) -> Double {
        let x: Double = v + 40
        return abs(x) < 1e-7 ? 1 : 0.1 * x / (1 - exp(-x / 10))
    }
    static func betaM(_ v: Double) -> Double { 4 * exp(-(v + 65) / 18) }
    static func alphaH(_ v: Double) -> Double { 0.07 * exp(-(v + 65) / 20) }
    static func betaH(_ v: Double) -> Double { 1 / (1 + exp(-(v + 35) / 10)) }

    /// The gates' steady state at `v`, where a resting membrane starts.
    static func resting(at v: Double = -65) -> State {
        let m: Double = alphaM(v) / (alphaM(v) + betaM(v))
        let h: Double = alphaH(v) / (alphaH(v) + betaH(v))
        let n: Double = alphaN(v) / (alphaN(v) + betaN(v))
        return State(v: v, m: m, h: h, n: n)
    }

    private static func derivative(_ s: State, current: Double, _ p: Parameters) -> State {
        let iNa: Double = p.gNa * s.m * s.m * s.m * s.h * (s.v - p.eNa)
        let iK: Double = p.gK * pow(s.n, 4) * (s.v - p.eK)
        let iL: Double = p.gL * (s.v - p.eL)
        let dv: Double = (current - iNa - iK - iL) / p.capacitance
        let dm: Double = alphaM(s.v) * (1 - s.m) - betaM(s.v) * s.m
        let dh: Double = alphaH(s.v) * (1 - s.h) - betaH(s.v) * s.h
        let dn: Double = alphaN(s.v) * (1 - s.n) - betaN(s.v) * s.n
        return State(v: dv, m: dm, h: dh, n: dn)
    }

    private static func step(_ s: State, by k: State, _ f: Double) -> State {
        State(v: s.v + k.v * f, m: s.m + k.m * f, h: s.h + k.h * f, n: s.n + k.n * f)
    }

    /// Runs the model for `milliseconds`, keeping every `keepEvery`-th step
    /// of `dt` ms. The membrane starts at the resting state its own
    /// parameters settle to, so a changed EK starts from its new rest.
    static func run(_ p: Parameters = Parameters(), pulses: [Pulse],
                    milliseconds: Double = 30, dt: Double = 0.01, keepEvery: Int = 5) -> [Sample] {
        var s: State = settle(p)
        var out: [Sample] = []
        let steps: Int = Int((milliseconds / dt).rounded())
        for i in 0...steps {
            let t: Double = Double(i) * dt
            let stim: Double = pulses.reduce(0) { $0 + $1.current(at: t) }
            if i % max(1, keepEvery) == 0 {
                let iNa: Double = p.gNa * s.m * s.m * s.m * s.h * (s.v - p.eNa)
                let iK: Double = p.gK * pow(s.n, 4) * (s.v - p.eK)
                out.append(Sample(t: t, v: s.v, m: s.m, h: s.h, n: s.n, iNa: iNa, iK: iK, stimulus: stim))
            }
            let k1: State = derivative(s, current: stim, p)
            let k2: State = derivative(step(s, by: k1, dt / 2), current: stim, p)
            let k3: State = derivative(step(s, by: k2, dt / 2), current: stim, p)
            let k4: State = derivative(step(s, by: k3, dt), current: stim, p)
            s = State(v: s.v + dt / 6 * (k1.v + 2 * k2.v + 2 * k3.v + k4.v),
                      m: s.m + dt / 6 * (k1.m + 2 * k2.m + 2 * k3.m + k4.m),
                      h: s.h + dt / 6 * (k1.h + 2 * k2.h + 2 * k3.h + k4.h),
                      n: s.n + dt / 6 * (k1.n + 2 * k2.n + 2 * k3.n + k4.n))
        }
        return out
    }

    /// The resting state for `p`: 100 ms with no stimulus from -65 mV.
    static func settle(_ p: Parameters) -> State {
        var s: State = resting()
        let dt: Double = 0.02
        for _ in 0..<5000 {
            let k1: State = derivative(s, current: 0, p)
            let k2: State = derivative(step(s, by: k1, dt / 2), current: 0, p)
            let k3: State = derivative(step(s, by: k2, dt / 2), current: 0, p)
            let k4: State = derivative(step(s, by: k3, dt), current: 0, p)
            s = State(v: s.v + dt / 6 * (k1.v + 2 * k2.v + 2 * k3.v + k4.v),
                      m: s.m + dt / 6 * (k1.m + 2 * k2.m + 2 * k3.m + k4.m),
                      h: s.h + dt / 6 * (k1.h + 2 * k2.h + 2 * k3.h + k4.h),
                      n: s.n + dt / 6 * (k1.n + 2 * k2.n + 2 * k3.n + k4.n))
        }
        return s
    }

    /// The times (ms) at which the trace crosses 0 mV going up: one per
    /// action potential.
    static func spikes(_ trace: [Sample], threshold: Double = 0) -> [Double] {
        var out: [Double] = []
        for i in 1..<max(1, trace.count) where trace[i - 1].v < threshold && trace[i].v >= threshold {
            out.append(trace[i].t)
        }
        return out
    }
}

/// The oxygen-haemoglobin dissociation curve.
///
/// Saturation follows Severinghaus's equation (J Appl Physiol 1979),
/// S = 1 / (23400 / (P³ + 150P) + 1), whose P50 is 26.9 mmHg, applied to a
/// "virtual" PO2 that carries the curve's shifts (Kelman's corrections):
/// log10 P50 moves by -0.48 per pH unit, +0.024 per °C and -0.0013 per
/// mmol/L of base excess. Fetal haemoglobin is taken as a P50 of 19 mmHg.
enum OxygenCurve {

    /// The standard P50 of Severinghaus's curve, mmHg (pH 7.4, 37 °C).
    static let standardP50: Double = 26.86
    /// Fetal haemoglobin's P50, mmHg.
    static let fetalP50: Double = 19

    /// The WHO's line for anaemia in a non-pregnant adult, g/dL: 13 for a man,
    /// 12 for a woman (WHO, Haemoglobin concentrations for the diagnosis of
    /// anaemia, 2011). Men make more red cells: testosterone drives
    /// erythropoietin, and menstruation costs iron.
    static func anaemiaLine(_ sex: AnatomySex) -> Double { sex == .male ? 13 : 12 }

    /// A typical adult haemoglobin, g/dL, where the tool starts for each sex.
    static func typicalHaemoglobin(_ sex: AnatomySex) -> Double { sex == .male ? 15 : 13.5 }

    struct Conditions: Hashable {
        var pH: Double = 7.4
        var celsius: Double = 37
        var baseExcess: Double = 0
        var fetal: Bool = false
    }

    /// P50 under `c`, mmHg.
    static func p50(_ c: Conditions = Conditions()) -> Double {
        let base: Double = c.fetal ? fetalP50 : standardP50
        let shift: Double = -0.48 * (c.pH - 7.4) + 0.024 * (c.celsius - 37) - 0.0013 * c.baseExcess
        return base * pow(10, shift)
    }

    /// Saturation 0...1 at `po2` mmHg.
    static func saturation(po2: Double, _ c: Conditions = Conditions()) -> Double {
        guard po2 > 0 else { return 0 }
        let p: Double = po2 * standardP50 / p50(c)
        return 1 / (23_400 / (p * p * p + 150 * p) + 1)
    }

    /// Arterial oxygen content, mL O2 per dL of blood:
    /// CaO2 = 1.34 × Hb (g/dL) × SaO2 + 0.003 × PaO2 (mmHg).
    static func content(hb: Double, saturation: Double, po2: Double) -> Double {
        1.34 * hb * saturation + 0.003 * po2
    }

    /// Oxygen delivery, mL/min: cardiac output (L/min) × CaO2 × 10.
    static func delivery(cardiacOutput: Double, content: Double) -> Double {
        cardiacOutput * content * 10
    }

    /// The curve as (PO2, saturation) points from 0 to `maxPO2`.
    static func curve(_ c: Conditions = Conditions(), maxPO2: Double = 120, points: Int = 121) -> [(po2: Double, sat: Double)] {
        (0..<max(2, points)).map { i in
            let p: Double = maxPO2 * Double(i) / Double(max(2, points) - 1)
            return (p, saturation(po2: p, c))
        }
    }
}

/// Starling's principle of capillary fluid exchange:
/// Jv = Kf × [(Pc − Pi) − σ(πc − πi)], pressures in mmHg.
///
/// Positive is filtration out of the capillary, negative absorption into it.
/// The defaults are teaching values for a systemic capillary; the screen's
/// notes add the revised principle (the glycocalyx), under which most
/// tissues absorb little at the venous end and lymph returns the filtrate.
enum Starling {

    struct Forces: Hashable {
        var capillaryHydrostatic: Double
        var interstitialHydrostatic: Double = 1
        var capillaryOncotic: Double = 25
        var interstitialOncotic: Double = 3
        var reflection: Double = 1
    }

    /// The net driving pressure, mmHg.
    static func net(_ f: Forces) -> Double {
        (f.capillaryHydrostatic - f.interstitialHydrostatic)
            - f.reflection * (f.capillaryOncotic - f.interstitialOncotic)
    }

    /// Flow per unit time: Kf × net.
    static func flux(_ f: Forces, kf: Double = 1) -> Double { kf * net(f) }

    static let arterialEnd: Forces = Forces(capillaryHydrostatic: 35)
    static let venousEnd: Forces = Forces(capillaryHydrostatic: 15)

    /// The causes of oedema, each as the force it moves.
    enum Oedema: String, CaseIterable, Identifiable {
        case heartFailure, lowAlbumin, inflammation, lymphObstruction
        var id: String { rawValue }

        var name: String {
            switch self {
            case .heartFailure: return "Raised venous pressure (heart failure)"
            case .lowAlbumin: return "Low albumin (nephrotic syndrome, cirrhosis)"
            case .inflammation: return "Leaky capillaries (inflammation, sepsis)"
            case .lymphObstruction: return "Blocked lymph (lymphoedema)"
            }
        }

        /// The forces at the venous end under this cause.
        var venousEnd: Forces {
            var f: Forces = Starling.venousEnd
            switch self {
            case .heartFailure: f.capillaryHydrostatic = 25
            case .lowAlbumin: f.capillaryOncotic = 15
            case .inflammation: f.reflection = 0.5; f.interstitialOncotic = 8
            case .lymphObstruction: f.interstitialOncotic = 10
            }
            return f
        }
    }
}

/// The lung's gas equations.
enum LungGas {

    /// Atmospheric pressure at sea level and water vapour pressure at 37 °C, mmHg.
    static let seaLevel: Double = 760
    static let waterVapour: Double = 47
    /// 1 kPa in mmHg.
    static let mmHgPerKPa: Double = 7.500_62

    /// The alveolar gas equation, mmHg:
    /// PAO2 = FiO2 × (Patm − PH2O) − PaCO2 / R, with R = 0.8.
    static func alveolarO2(fio2: Double = 0.21, paco2: Double = 40,
                           atmospheric: Double = seaLevel, quotient: Double = 0.8) -> Double {
        fio2 * (atmospheric - waterVapour) - paco2 / quotient
    }

    /// The A-a gradient, mmHg.
    static func aaGradient(pao2: Double, paco2: Double, fio2: Double = 0.21,
                           atmospheric: Double = seaLevel) -> Double {
        alveolarO2(fio2: fio2, paco2: paco2, atmospheric: atmospheric) - pao2
    }

    /// The usual upper limit of the A-a gradient breathing air, mmHg:
    /// age / 4 + 4.
    static func expectedAAGradient(age: Double) -> Double { age / 4 + 4 }

    /// Alveolar ventilation, mL/min: (tidal volume − dead space) × rate.
    static func alveolarVentilation(tidal: Double, deadSpace: Double, rate: Double) -> Double {
        max(0, tidal - deadSpace) * rate
    }

    /// Bohr's dead space fraction VD/VT = (PaCO2 − PECO2) / PaCO2.
    static func deadSpaceFraction(paco2: Double, mixedExpiredCO2: Double) -> Double? {
        guard paco2 > 0 else { return nil }
        return (paco2 - mixedExpiredCO2) / paco2
    }

    /// Compliance, mL/cmH2O: change in volume over change in pressure.
    static func compliance(deltaVolume: Double, deltaPressure: Double) -> Double? {
        guard deltaPressure != 0 else { return nil }
        return deltaVolume / deltaPressure
    }
}

/// Renal clearance and the measures built on it.
enum RenalPhysiology {

    /// Clearance, mL/min: urine concentration × urine flow / plasma concentration.
    static func clearance(urine: Double, flow: Double, plasma: Double) -> Double? {
        guard plasma > 0 else { return nil }
        return urine * flow / plasma
    }

    /// Filtration fraction: GFR / renal plasma flow (about 0.2).
    static func filtrationFraction(gfr: Double, rpf: Double) -> Double? {
        guard rpf > 0 else { return nil }
        return gfr / rpf
    }

    /// Renal blood flow from plasma flow: RPF / (1 − haematocrit).
    static func bloodFlow(rpf: Double, haematocrit: Double) -> Double? {
        guard haematocrit < 1 else { return nil }
        return rpf / (1 - haematocrit)
    }

    /// Filtered load, per minute: GFR (mL/min) × plasma concentration.
    static func filteredLoad(gfr: Double, plasma: Double) -> Double { gfr * plasma }

    /// Fractional excretion of sodium, %:
    /// (urine Na × plasma creatinine) / (plasma Na × urine creatinine) × 100.
    static func fractionalExcretionNa(urineNa: Double, plasmaNa: Double,
                                      urineCreatinine: Double, plasmaCreatinine: Double) -> Double? {
        guard plasmaNa > 0, urineCreatinine > 0 else { return nil }
        return urineNa * plasmaCreatinine / (plasmaNa * urineCreatinine) * 100
    }

    /// What a FENa says in oliguric acute kidney injury: under 1% points to
    /// a prerenal cause, over 2% to acute tubular injury (diuretics make it
    /// unreliable).
    static func fenaReading(_ fena: Double) -> String {
        if fena < 1 { return "Under 1%: the tubules are holding sodium, as in a prerenal cause." }
        if fena > 2 { return "Over 2%: the tubules are losing sodium, as in acute tubular injury." }
        return "Between 1% and 2%: not decisive."
    }

    /// Free water clearance, mL/min: V − Cosm, where Cosm = Uosm × V / Posm.
    /// Positive when dilute urine is made, negative when it is concentrated.
    static func freeWaterClearance(flow: Double, urineOsm: Double, plasmaOsm: Double) -> Double? {
        guard plasmaOsm > 0 else { return nil }
        return flow - urineOsm * flow / plasmaOsm
    }
}

/// The haemodynamic formulas.
enum Haemodynamics {

    /// Mean arterial pressure ≈ diastolic + (systolic − diastolic) / 3.
    static func meanArterial(systolic: Double, diastolic: Double) -> Double {
        diastolic + (systolic - diastolic) / 3
    }

    /// Cardiac output, L/min: heart rate × stroke volume (mL) / 1000.
    static func cardiacOutput(heartRate: Double, strokeVolume: Double) -> Double {
        heartRate * strokeVolume / 1000
    }

    /// Systemic vascular resistance, dyn·s·cm⁻⁵: 80 × (MAP − CVP) / CO.
    static func systemicResistance(map: Double, cvp: Double, cardiacOutput: Double) -> Double? {
        guard cardiacOutput > 0 else { return nil }
        return 80 * (map - cvp) / cardiacOutput
    }

    /// Ejection fraction: stroke volume / end-diastolic volume.
    static func ejectionFraction(edv: Double, esv: Double) -> Double? {
        guard edv > 0 else { return nil }
        return (edv - esv) / edv
    }

    /// Poiseuille: flow at a fixed pressure scales with radius⁴, so a vessel
    /// at `radiusRatio` of its radius carries this fraction of the flow.
    static func poiseuilleFlowRatio(radiusRatio: Double) -> Double { pow(max(0, radiusRatio), 4) }

    /// Fick's principle, L/min: O2 consumption (mL/min) / (CaO2 − CvO2) (mL/dL) / 10.
    static func fickOutput(vo2: Double, arterialContent: Double, venousContent: Double) -> Double? {
        let difference: Double = arterialContent - venousContent
        guard difference > 0 else { return nil }
        return vo2 / (difference * 10)
    }

    /// Laplace's law for a sphere: wall stress = P × r / (2 × wall thickness).
    static func wallStress(pressure: Double, radius: Double, thickness: Double) -> Double? {
        guard thickness > 0 else { return nil }
        return pressure * radius / (2 * thickness)
    }
}
