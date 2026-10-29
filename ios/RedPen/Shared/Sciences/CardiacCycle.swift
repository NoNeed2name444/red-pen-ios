import Foundation

/// The left heart's cycle, from a lumped model: what the Wiggers diagram and
/// the pressure-volume loop on the physiology screen are drawn from.
///
/// Each chamber is a time-varying elastance, P = E(t) × (V − V0) (Suga and
/// Sagawa), with E rising from its diastolic to its end-systolic value on a
/// cosine and falling back. The aorta is a compliance emptying through the
/// systemic resistance into one venous compliance that refills the left
/// atrium (the lungs and the right heart lumped together). Valves let blood
/// through an orifice: a small resistance plus Bernoulli's loss,
/// ΔP = R·Q + ρ/(2A²)·Q², so a narrow valve makes the gradient a student
/// sees on echo (about 4v²). A leaking valve lets blood back through its
/// regurgitant orifice by the same law.
///
/// Integrated with fourth-order Runge-Kutta for a few beats until it
/// settles, then one beat is reported. Teaching values throughout: it shows
/// directions and sizes, not one patient. Foundation only.
enum CardiacCycle {

    struct Parameters: Hashable {
        var heartRate: Double = 75
        /// Left ventricle: end-systolic and diastolic elastance (mmHg/mL)
        /// and unstressed volume (mL).
        var lvEmax: Double = 3.0
        var lvEmin: Double = 0.075
        var lvV0: Double = 10
        /// Left atrium.
        var laEmax: Double = 0.3
        var laEmin: Double = 0.16
        var laV0: Double = 4
        /// Ventricular contraction to peak, and relaxation, in seconds.
        var contraction: Double = 0.3
        var relaxation: Double = 0.15
        /// The three-element Windkessel: the aorta's characteristic
        /// impedance and compliance (mL/mmHg), and the systemic resistance
        /// (mmHg·s/mL).
        var characteristicImpedance: Double = 0.04
        var aorticCompliance: Double = 1.4
        var systemicResistance: Double = 0.95
        /// The lumped venous side: compliance and its resistance back into
        /// the left atrium.
        var venousCompliance: Double = 40
        var venousResistance: Double = 0.03
        /// Valve areas, cm². Normal aortic 3 to 4, mitral 4 to 6.
        var aorticArea: Double = 3.5
        var mitralArea: Double = 5
        /// Regurgitant orifice areas, cm² (0: competent).
        var aorticLeak: Double = 0
        var mitralLeak: Double = 0
        /// Stressed blood volume across the model, mL (its total above the
        /// unstressed volumes).
        var stressedVolume: Double = 700
    }

    /// The conditions the screen offers, each as the parameter it moves.
    enum Preset: String, CaseIterable, Identifiable {
        case normal, aorticStenosis, aorticRegurgitation, mitralStenosis, mitralRegurgitation
        case systolicFailure, diastolicFailure, hypertension, haemorrhage, exercise
        var id: String { rawValue }

        var name: String {
            switch self {
            case .normal: return "Normal"
            case .aorticStenosis: return "Aortic stenosis"
            case .aorticRegurgitation: return "Aortic regurgitation"
            case .mitralStenosis: return "Mitral stenosis"
            case .mitralRegurgitation: return "Mitral regurgitation"
            case .systolicFailure: return "Systolic heart failure"
            case .diastolicFailure: return "Stiff ventricle (HFpEF)"
            case .hypertension: return "Raised afterload"
            case .haemorrhage: return "Blood loss"
            case .exercise: return "Exercise"
            }
        }

        /// What changed, in the student's terms.
        var change: String {
            switch self {
            case .normal: return "A healthy adult at rest."
            case .aorticStenosis: return "Aortic valve area 0.8 cm² (severe is under 1.0)."
            case .aorticRegurgitation: return "A 0.3 cm² leak in the aortic valve."
            case .mitralStenosis: return "Mitral valve area 1.0 cm² (severe is 1.5 or less), with the fluid the kidneys hold."
            case .mitralRegurgitation: return "A 0.4 cm² leak in the mitral valve."
            case .systolicFailure: return "Contractility (end-systolic elastance) cut by 60%, with the fluid the kidneys hold."
            case .diastolicFailure: return "A ventricle three times as stiff in diastole, with the fluid the kidneys hold."
            case .hypertension: return "Narrower, stiffer arteries: resistance up by 40%, aortic compliance down by a third."
            case .haemorrhage: return "A fifth of the stressed blood volume lost. The model has no reflexes: in a person the baroreflex would raise the heart rate and tighten the vessels."
            case .exercise: return "Heart rate 130, contractility up by half, resistance down, faster relaxation."
            }
        }

        var parameters: Parameters {
            var p: Parameters = Parameters()
            switch self {
            case .normal: break
            case .aorticStenosis: p.aorticArea = 0.8
            case .aorticRegurgitation: p.aorticLeak = 0.3
            case .mitralStenosis: p.mitralArea = 1.0; p.stressedVolume = 900
            case .mitralRegurgitation: p.mitralLeak = 0.4
            case .systolicFailure: p.lvEmax = 0.95; p.stressedVolume = 1000
            case .diastolicFailure: p.lvEmin = 0.225; p.stressedVolume = 900
            case .hypertension: p.systemicResistance = 1.35; p.aorticCompliance = 0.9
            case .haemorrhage: p.stressedVolume = 560
            case .exercise:
                p.heartRate = 130; p.lvEmax = 3.6; p.systemicResistance = 0.6
                p.contraction = 0.2; p.relaxation = 0.1; p.stressedVolume = 840
            }
            return p
        }
    }

    struct Sample: Hashable {
        /// Seconds from the start of ventricular contraction.
        var t: Double
        /// mmHg.
        var lvPressure: Double, aorticPressure: Double, laPressure: Double
        /// mL.
        var lvVolume: Double
        /// mL/s, forward positive.
        var mitralFlow: Double, aorticFlow: Double
    }

    enum Event: String, Hashable {
        case mitralCloses, aorticOpens, aorticCloses, mitralOpens

        var name: String {
            switch self {
            case .mitralCloses: return "Mitral valve closes (S1)"
            case .aorticOpens: return "Aortic valve opens"
            case .aorticCloses: return "Aortic valve closes (S2)"
            case .mitralOpens: return "Mitral valve opens"
            }
        }
    }

    struct Beat: Hashable {
        var samples: [Sample]
        var eventTimes: [Event: Double]
        var edv: Double, esv: Double
        var aorticSystolic: Double, aorticDiastolic: Double
        var lvSystolic: Double, lvEndDiastolic: Double
        var meanLA: Double
        /// Forward flow through the aortic valve per beat, and what leaked
        /// back through either valve, mL.
        var forwardStroke: Double
        var regurgitant: Double
        var peakAorticGradient: Double
        var meanMitralGradient: Double
        var heartRate: Double

        var strokeVolume: Double { edv - esv }
        var ejectionFraction: Double { edv > 0 ? (edv - esv) / edv : 0 }
        /// Net forward cardiac output, L/min.
        var cardiacOutput: Double { (forwardStroke - aorticBack) * heartRate / 1000 }
        var meanArterial: Double { Haemodynamics.meanArterial(systolic: aorticSystolic, diastolic: aorticDiastolic) }
        var pulsePressure: Double { aorticSystolic - aorticDiastolic }
        /// The part of the total stroke volume that went backwards.
        var regurgitantFraction: Double { strokeVolume > 0 ? regurgitant / strokeVolume : 0 }
        /// Blood back through the aortic valve, mL (counted in `regurgitant`).
        var aorticBack: Double
    }

    /// Blood density over two, in mmHg·s²/mL² per 1/cm⁴: ρ/2 with ρ 1.06 g/mL,
    /// converted from dyn/cm² (1 mmHg = 1333.22 dyn/cm²).
    static let bernoulli: Double = 1.06 / 2 / 1333.22
    /// The open valve's own resistance, mmHg·s/mL.
    static let valveResistance: Double = 0.004

    /// Normalised activation 0...1 at `t` seconds into a cycle that starts
    /// with contraction.
    ///
    /// It rises on a quarter sine, so pressure climbs from the first moment
    /// (a dP/dt near 1500 mmHg/s at rest, an isovolumic contraction of about
    /// 50 ms), and falls on a half cosine.
    static func activation(_ t: Double, contraction: Double, relaxation: Double) -> Double {
        if t < 0 { return 0 }
        if t < contraction { return sin(Double.pi / 2 * t / contraction) }
        if t < contraction + relaxation { return 0.5 * (1 + cos(Double.pi * (t - contraction) / relaxation)) }
        return 0
    }

    /// The atrium contracts 0.16 s before the ventricle (the PR interval),
    /// for 0.09 s, and relaxes over 0.09 s.
    static func atrialActivation(_ t: Double, period: Double) -> Double {
        var s: Double = t - (period - 0.16)
        if s < -period / 2 { s += period }
        guard s >= 0, s < 0.18 else { return 0 }
        return 0.5 * (1 - cos(Double.pi * s / 0.09))
    }

    /// Forward flow through an orifice of `area` cm² for a pressure drop
    /// `dp` (mmHg), with a backward leak of `leak` cm². `series` is a
    /// resistance in line with the valve (the aorta's characteristic
    /// impedance): dp = (r + series)·Q + b·Q², solved for Q.
    static func valveFlow(_ dp: Double, area: Double, leak: Double, series: Double = 0) -> Double {
        if dp > 0 {
            let b: Double = bernoulli / max(0.05, area * area)
            let r: Double = valveResistance + series
            return (-r + (r * r + 4 * b * dp).squareRoot()) / (2 * b)
        }
        guard leak > 0 else { return 0 }
        let b: Double = bernoulli / (leak * leak)
        return -(-series + (series * series + 4 * b * (-dp)).squareRoot()) / (2 * b)
    }

    private struct State {
        var lv: Double, la: Double, ao: Double, ven: Double
    }

    private struct Pressures {
        var lv: Double, la: Double, ao: Double, ven: Double
        var mitral: Double, aortic: Double, systemic: Double, venous: Double
    }

    /// The aorta's and veins' unstressed volumes are taken as zero: volumes
    /// in those two compartments are stressed volume.
    private static func pressures(_ s: State, at t: Double, _ p: Parameters) -> Pressures {
        let period: Double = 60 / p.heartRate
        let e: Double = activation(t, contraction: p.contraction, relaxation: p.relaxation)
        let ea: Double = atrialActivation(t, period: period)
        let lvP: Double = (p.lvEmin + (p.lvEmax - p.lvEmin) * e) * (s.lv - p.lvV0)
        let laP: Double = (p.laEmin + (p.laEmax - p.laEmin) * ea) * (s.la - p.laV0)
        let windkessel: Double = s.ao / p.aorticCompliance
        let venP: Double = s.ven / p.venousCompliance
        let mitral: Double = valveFlow(laP - lvP, area: p.mitralArea, leak: p.mitralLeak)
        let aortic: Double = valveFlow(lvP - windkessel, area: p.aorticArea, leak: p.aorticLeak,
                                       series: p.characteristicImpedance)
        // The pressure in the aortic root, what a catheter there reads.
        let aoP: Double = windkessel + p.characteristicImpedance * aortic
        let systemic: Double = (windkessel - venP) / p.systemicResistance
        let venous: Double = max(0, (venP - laP) / p.venousResistance)
        return Pressures(lv: lvP, la: laP, ao: aoP, ven: venP,
                         mitral: mitral, aortic: aortic, systemic: systemic, venous: venous)
    }

    private static func derivative(_ s: State, at t: Double, _ p: Parameters) -> State {
        let q: Pressures = pressures(s, at: t, p)
        return State(lv: q.mitral - q.aortic, la: q.venous - q.mitral,
                     ao: q.aortic - q.systemic, ven: q.systemic - q.venous)
    }

    /// One settled beat under `p`, sampled every `sampleEvery` seconds.
    static func beat(_ p: Parameters = Parameters(), settleBeats: Int = 14,
                     dt: Double = 0.0002, sampleEvery: Double = 0.004) -> Beat {
        let period: Double = 60 / p.heartRate
        // Start near a resting distribution of the stressed volume.
        let lv: Double = p.lvV0 + 110, la: Double = p.laV0 + 50
        let ao: Double = 90 * p.aorticCompliance
        let ven: Double = max(0, p.stressedVolume - (lv - p.lvV0) - (la - p.laV0) - ao)
        var s: State = State(lv: lv, la: la, ao: ao, ven: ven)
        let stepsPerBeat: Int = Int((period / dt).rounded())
        let keep: Int = max(1, Int((sampleEvery / dt).rounded()))
        var samples: [Sample] = []
        for b in 0...settleBeats {
            let last: Bool = b == settleBeats
            for i in 0..<stepsPerBeat {
                let t: Double = Double(i) * dt
                if last && i % keep == 0 {
                    let q: Pressures = pressures(s, at: t, p)
                    samples.append(Sample(t: t, lvPressure: q.lv, aorticPressure: q.ao, laPressure: q.la,
                                          lvVolume: s.lv, mitralFlow: q.mitral, aorticFlow: q.aortic))
                }
                let k1: State = derivative(s, at: t, p)
                let k2: State = derivative(add(s, k1, dt / 2), at: t + dt / 2, p)
                let k3: State = derivative(add(s, k2, dt / 2), at: t + dt / 2, p)
                let k4: State = derivative(add(s, k3, dt), at: t + dt, p)
                s = State(lv: s.lv + dt / 6 * (k1.lv + 2 * k2.lv + 2 * k3.lv + k4.lv),
                          la: s.la + dt / 6 * (k1.la + 2 * k2.la + 2 * k3.la + k4.la),
                          ao: s.ao + dt / 6 * (k1.ao + 2 * k2.ao + 2 * k3.ao + k4.ao),
                          ven: s.ven + dt / 6 * (k1.ven + 2 * k2.ven + 2 * k3.ven + k4.ven))
            }
        }
        return summarise(samples, p)
    }

    private static func add(_ s: State, _ k: State, _ f: Double) -> State {
        State(lv: s.lv + k.lv * f, la: s.la + k.la * f, ao: s.ao + k.ao * f, ven: s.ven + k.ven * f)
    }

    private static func summarise(_ samples: [Sample], _ p: Parameters) -> Beat {
        let dtS: Double = samples.count > 1 ? samples[1].t - samples[0].t : 0
        let volumes: [Double] = samples.map(\.lvVolume)
        let edv: Double = volumes.max() ?? 0
        let esv: Double = volumes.min() ?? 0
        var events: [Event: Double] = [:]
        for i in 1..<max(1, samples.count) {
            let a: Sample = samples[i - 1], b: Sample = samples[i]
            if a.mitralFlow > 0.5, b.mitralFlow <= 0.5, b.t < 0.2, events[.mitralCloses] == nil { events[.mitralCloses] = b.t }
            if a.aorticFlow <= 0.5, b.aorticFlow > 0.5, events[.aorticOpens] == nil { events[.aorticOpens] = b.t }
            if a.aorticFlow > 0.5, b.aorticFlow <= 0.5, events[.aorticOpens] != nil, events[.aorticCloses] == nil { events[.aorticCloses] = b.t }
            if a.mitralFlow <= 0.5, b.mitralFlow > 0.5, events[.aorticCloses] != nil, events[.mitralOpens] == nil { events[.mitralOpens] = b.t }
        }
        // Mitral closure happens at the very start of contraction; if the
        // valve was already shut when the beat began, the first sample is it.
        if events[.mitralCloses] == nil, let first = samples.first, first.mitralFlow <= 0.5 { events[.mitralCloses] = 0 }
        let forward: Double = samples.reduce(0) { $0 + max(0, $1.aorticFlow) } * dtS
        let aorticBack: Double = samples.reduce(0) { $0 + max(0, -$1.aorticFlow) } * dtS
        let mitralBack: Double = samples.reduce(0) { $0 + max(0, -$1.mitralFlow) } * dtS
        let gradients: [Double] = samples.filter { $0.aorticFlow > 0.5 }.map { $0.lvPressure - $0.aorticPressure }
        let filling: [Sample] = samples.filter { $0.mitralFlow > 0.5 }
        let mitralGradient: Double = filling.isEmpty ? 0
            : filling.reduce(0) { $0 + ($1.laPressure - $1.lvPressure) } / Double(filling.count)
        // End-diastole is the onset of contraction, the beat's first sample.
        let lvEDP: Double = samples.first?.lvPressure ?? 0
        return Beat(samples: samples, eventTimes: events, edv: edv, esv: esv,
                    aorticSystolic: samples.map(\.aorticPressure).max() ?? 0,
                    aorticDiastolic: samples.map(\.aorticPressure).min() ?? 0,
                    lvSystolic: samples.map(\.lvPressure).max() ?? 0,
                    lvEndDiastolic: lvEDP,
                    meanLA: samples.isEmpty ? 0 : samples.reduce(0) { $0 + $1.laPressure } / Double(samples.count),
                    forwardStroke: forward, regurgitant: aorticBack + mitralBack,
                    peakAorticGradient: gradients.max() ?? 0, meanMitralGradient: mitralGradient,
                    heartRate: p.heartRate, aorticBack: aorticBack)
    }

    /// The phase of the cycle at `t` in `beat`, as the diagram labels it.
    static func phase(at t: Double, in beat: Beat) -> String {
        let e: [Event: Double] = beat.eventTimes
        let open: Double = e[.aorticOpens] ?? 0, close: Double = e[.aorticCloses] ?? 0
        let mOpen: Double = e[.mitralOpens] ?? 0
        if t < open { return "Isovolumic contraction" }
        if t < close { return "Ejection" }
        if t < mOpen { return "Isovolumic relaxation" }
        let period: Double = 60 / beat.heartRate
        if t > period - 0.16 { return "Atrial contraction" }
        return "Filling"
    }
}
