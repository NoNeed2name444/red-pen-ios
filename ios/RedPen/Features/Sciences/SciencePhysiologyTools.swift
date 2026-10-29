import Charts
import SwiftUI

// The physiology tools: each one an engine in Shared/Sciences (Physiology,
// CardiacCycle, AcidBase) with values to change, its plot and its numbers.

// MARK: - Membrane potential

struct MembranePotentialTool: View {
    @State private var ions = Membrane.Ions()
    @State private var permeability = Membrane.Permeability()

    private struct Bar: Identifiable {
        let id: String
        let mV: Double
        let membrane: Bool
    }

    var body: some View {
        let vm: Double = Membrane.goldman(ions, permeability) ?? .nan
        let ek: Double = Membrane.nernst(valence: 1, outside: ions.kOut, inside: ions.kIn) ?? .nan
        let ena: Double = Membrane.nernst(valence: 1, outside: ions.naOut, inside: ions.naIn) ?? .nan
        let ecl: Double = Membrane.nernst(valence: -1, outside: ions.clOut, inside: ions.clIn) ?? .nan
        let bars: [Bar] = [Bar(id: "EK", mV: ek, membrane: false), Bar(id: "ENa", mV: ena, membrane: false),
                           Bar(id: "ECl", mV: ecl, membrane: false), Bar(id: "Membrane", mV: vm, membrane: true)]
        ScienceToolPage(tool: .membranePotential) {
            Section {
                ScienceFigure(title: "Each ion's pull, and where the membrane sits",
                              caption: "The membrane rests nearest the ion it lets through most. At rest that is potassium.",
                              spoken: "Potassium \(scienceNumber(ek)) millivolts, sodium \(scienceNumber(ena)), chloride \(scienceNumber(ecl)); the membrane \(scienceNumber(vm)).") {
                    Chart {
                        ForEach(bars) { bar in
                            BarMark(x: .value("Potential", bar.id), y: .value("mV", bar.mV))
                                .foregroundStyle(bar.membrane ? Color.wardBeam : Color.wardPrimaryInk.opacity(0.7))
                                .cornerRadius(4)
                        }
                        RuleMark(y: .value("Zero", 0.0))
                            .foregroundStyle(Color.wardInkSecondary)
                    }
                    .chartYScale(domain: -120.0...90.0)
                    .chartYAxisLabel("mV")
                }
            }
            .wardRowBackground()

            Section("Values") {
                ScienceSlider(name: "Potassium outside", value: $ions.kOut, range: 1...12, step: 0.1,
                              shown: scienceNumber(ions.kOut, 1) + " mmol/L")
                ScienceSlider(name: "Sodium outside", value: $ions.naOut, range: 110...170, step: 1,
                              shown: scienceNumber(ions.naOut) + " mmol/L")
                ScienceSlider(name: "Sodium inside", value: $ions.naIn, range: 5...40, step: 1,
                              shown: scienceNumber(ions.naIn) + " mmol/L")
                ScienceSlider(name: "Sodium's permeability", value: $permeability.na, range: 0.01...20, step: 0.01,
                              shown: scienceNumber(permeability.na, 2) + " \u{00D7} potassium's")
                ScienceSlider(name: "Chloride's permeability", value: $permeability.cl, range: 0...1, step: 0.01,
                              shown: scienceNumber(permeability.cl, 2) + " \u{00D7} potassium's")
            }
            .wardRowBackground()

            Section("Result") {
                ScienceReading(label: "Membrane (Goldman)", value: scienceNumber(vm) + " mV")
                ScienceReading(label: "Potassium (Nernst)", value: scienceNumber(ek) + " mV")
                ScienceReading(label: "Sodium (Nernst)", value: scienceNumber(ena) + " mV")
                ScienceReading(label: "Chloride (Nernst)", value: scienceNumber(ecl) + " mV")
                ScienceVerdict(text: verdict(vm))
            }
            .wardRowBackground()
            .accessibilityElement(children: .combine)

            Section("Try") {
                SciencePresetButton(title: "At rest", detail: "The usual concentrations") {
                    ions = Membrane.Ions(); permeability = Membrane.Permeability()
                }
                SciencePresetButton(title: "Hyperkalaemia", detail: "Potassium outside 7.5 mmol/L") {
                    ions = Membrane.Ions(); ions.kOut = 7.5; permeability = Membrane.Permeability()
                }
                SciencePresetButton(title: "Hypokalaemia", detail: "Potassium outside 2.5 mmol/L") {
                    ions = Membrane.Ions(); ions.kOut = 2.5; permeability = Membrane.Permeability()
                }
                SciencePresetButton(title: "The top of an action potential", detail: "Sodium channels open: twenty times potassium's permeability") {
                    ions = Membrane.Ions(); permeability = Membrane.Permeability(); permeability.na = 20
                }
            }
            .wardRowBackground()

            ScienceTextSection(title: "How it is worked out",
                               text: "Nernst, for one ion: E = (RT/zF) ln([out]/[in]), about 61.5 mV for each tenfold difference at 37 \u{00B0}C. Goldman, for the membrane: Vm = (RT/F) ln((pK[K]out + pNa[Na]out + pCl[Cl]in) / (pK[K]in + pNa[Na]in + pCl[Cl]out)). Chloride's inside and outside swap because it carries a negative charge.")
            ScienceTextSection(title: "Keep in mind",
                               text: "Raising potassium outside depolarises every cell a little: at first it is easier to fire, then sodium channels stay inactivated and the heart conducts poorly (peaked T waves, then a broad QRS). The sodium-potassium pump keeps the gradients but adds only a few millivolts itself.")
        }
    }

    private func verdict(_ vm: Double) -> String {
        if vm > 0 { return "The membrane is positive inside: sodium dominates, as at the top of an action potential." }
        if vm > -60 { return "Depolarised: closer to threshold than a resting cell." }
        if vm < -80 { return "Hyperpolarised: further from threshold than a resting cell." }
        return "A normal resting potential."
    }
}

// MARK: - Action potential

struct ActionPotentialTool: View {
    @State private var stimulus = 15.0
    @State private var second = true
    @State private var gap = 10.0
    @State private var sodiumBlock = 0.0
    @State private var potassiumBlock = 0.0
    @State private var kOut = 4.0

    private struct Gate: Identifiable {
        let id: Int
        let t: Double
        let value: Double
        let name: String
    }

    private var parameters: HodgkinHuxley.Parameters {
        HodgkinHuxley.Parameters()
            .sodiumBlocked(sodiumBlock)
            .potassiumBlocked(potassiumBlock)
            .outsidePotassium(kOut)
    }

    private var pulses: [HodgkinHuxley.Pulse] {
        var out: [HodgkinHuxley.Pulse] = [HodgkinHuxley.Pulse(start: 2, duration: 1, amplitude: stimulus)]
        if second { out.append(HodgkinHuxley.Pulse(start: 2 + gap, duration: 1, amplitude: stimulus)) }
        return out
    }

    var body: some View {
        let trace: [HodgkinHuxley.Sample] = HodgkinHuxley.run(parameters, pulses: pulses, milliseconds: 40)
        let spikes: [Double] = HodgkinHuxley.spikes(trace)
        let peak: Double = trace.map(\.v).max() ?? .nan
        let rest: Double = trace.first?.v ?? .nan
        let gates: [Gate] = trace.enumerated().flatMap { i, s in
            [Gate(id: i * 3, t: s.t, value: s.m, name: "m (sodium opens)"),
             Gate(id: i * 3 + 1, t: s.t, value: s.h, name: "h (sodium inactivates)"),
             Gate(id: i * 3 + 2, t: s.t, value: s.n, name: "n (potassium opens)")]
        }
        ScienceToolPage(tool: .actionPotential) {
            Section {
                ScienceFigure(title: "Membrane potential",
                              caption: "Dashed lines mark the stimuli. A second stimulus inside the refractory period fails or fires a smaller spike.",
                              spoken: "\(spikes.count) action potentials in 40 milliseconds, peaking at \(scienceNumber(peak)) millivolts from a rest of \(scienceNumber(rest)).") {
                    Chart {
                        ForEach(trace, id: \.t) { s in
                            LineMark(x: .value("Time", s.t), y: .value("mV", s.v))
                                .foregroundStyle(Color.wardPrimaryInk)
                        }
                        ForEach(pulses, id: \.start) { p in
                            RuleMark(x: .value("Stimulus", p.start))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .foregroundStyle(Color.wardBeam)
                        }
                    }
                    .chartYScale(domain: -90.0...60.0)
                    .chartXAxisLabel("ms")
                    .chartYAxisLabel("mV")
                }
            }
            .wardRowBackground()

            Section {
                ScienceFigure(title: "The gates",
                              caption: "m opens fast and h closes slowly: the spike ends, and until h recovers and n closes, the next one is hard to start.",
                              spoken: "The sodium activation, sodium inactivation and potassium gates through the same 40 milliseconds.") {
                    Chart(gates) { g in
                        LineMark(x: .value("Time", g.t), y: .value("Open", g.value), series: .value("Gate", g.name))
                            .foregroundStyle(by: .value("Gate", g.name))
                    }
                    .chartForegroundStyleScale(["m (sodium opens)": Color.wardPrimaryInk,
                                                "h (sodium inactivates)": Color.wardBeam,
                                                "n (potassium opens)": Color.wardEcg])
                    .chartYScale(domain: 0.0...1.0)
                    .chartXAxisLabel("ms")
                }
            }
            .wardRowBackground()

            Section("Values") {
                ScienceSlider(name: "Stimulus", value: $stimulus, range: 0...40, step: 0.5,
                              shown: scienceNumber(stimulus, 1) + " \u{00B5}A/cm\u{00B2}")
                Toggle("A second stimulus", isOn: $second)
                if second {
                    ScienceSlider(name: "After the first", value: $gap, range: 2...30, step: 0.5,
                                  shown: scienceNumber(gap, 1) + " ms")
                }
                ScienceSlider(name: "Sodium channels blocked", value: $sodiumBlock, range: 0...1, step: 0.01,
                              shown: sciencePercent(sodiumBlock))
                ScienceSlider(name: "Potassium channels blocked", value: $potassiumBlock, range: 0...1, step: 0.01,
                              shown: sciencePercent(potassiumBlock))
                ScienceSlider(name: "Potassium outside", value: $kOut, range: 1...10, step: 0.1,
                              shown: scienceNumber(kOut, 1) + " mmol/L")
            }
            .wardRowBackground()

            Section("Result") {
                ScienceReading(label: "Action potentials", value: "\(spikes.count)")
                ScienceReading(label: "Peak", value: scienceNumber(peak) + " mV")
                ScienceReading(label: "Rest", value: scienceNumber(rest, 1) + " mV")
                ScienceVerdict(text: verdict(spikes: spikes.count, peak: peak))
            }
            .wardRowBackground()
            .accessibilityElement(children: .combine)

            ScienceTextSection(title: "How it is worked out",
                               text: "The Hodgkin-Huxley model of the squid giant axon (1952): the membrane's capacitance charged by sodium, potassium and leak currents, each through gates that open and close at voltage-dependent rates, integrated in 0.01 ms steps. Blocking a channel scales its conductance down; potassium outside moves its equilibrium potential as the Nernst equation says.")
            ScienceTextSection(title: "Keep in mind",
                               text: "Sodium channel blockers (tetrodotoxin, lidocaine) raise the threshold until nothing fires. Potassium channel blockers (amiodarone's class III effect) widen the spike. A high potassium outside depolarises the resting membrane, which inactivates sodium channels: first excitable, then not.")
        }
    }

    private func verdict(spikes: Int, peak: Double) -> String {
        if spikes == 0 {
            return sodiumBlock > 0.5
                ? "Nothing fires: too few sodium channels are left to make the upstroke regenerate."
                : "Nothing fires: the stimulus does not reach threshold."
        }
        if second && spikes == 1 {
            return "The second stimulus fell in the refractory period: sodium channels were still inactivated (h low) and potassium channels still open (n high)."
        }
        if spikes > pulses.count {
            return "More spikes than stimuli: the membrane fires on its own, as a depolarised membrane can."
        }
        return "Each stimulus fired a spike."
    }
}

// MARK: - Cardiac cycle

struct CardiacCycleTool: View {
    @State private var preset: CardiacCycle.Preset = .normal
    @State private var beat: CardiacCycle.Beat = Self.normal

    /// The healthy heart, worked out once: the first beat shown, and the
    /// grey loop under every other.
    private static let normal: CardiacCycle.Beat = CardiacCycle.beat()

    private struct Trace: Identifiable {
        let id: Int
        let t: Double
        let mmHg: Double
        let name: String
    }

    private struct Valve: Identifiable {
        var id: String { name }
        let name: String
        let ms: Double
    }

    var body: some View {
        let loop: [CardiacCycle.Sample] = beat.samples + Array(beat.samples.prefix(1))
        let reference: [CardiacCycle.Sample] = Self.normal.samples + Array(Self.normal.samples.prefix(1))
        let traces: [Trace] = beat.samples.enumerated().flatMap { i, s in
            [Trace(id: i * 3, t: s.t * 1000, mmHg: s.lvPressure, name: "Left ventricle"),
             Trace(id: i * 3 + 1, t: s.t * 1000, mmHg: s.aorticPressure, name: "Aorta"),
             Trace(id: i * 3 + 2, t: s.t * 1000, mmHg: s.laPressure, name: "Left atrium")]
        }
        let events: [Valve] = [CardiacCycle.Event.mitralCloses, .aorticOpens, .aorticCloses, .mitralOpens]
            .compactMap { e in beat.eventTimes[e].map { Valve(name: e.name, ms: $0 * 1000) } }
        ScienceToolPage(tool: .cardiacCycle) {
            Section {
                Picker("Heart", selection: $preset) {
                    ForEach(CardiacCycle.Preset.allCases) { p in
                        Text(p.name).tag(p)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Values")
            } footer: {
                Text(preset.change)
            }
            .wardRowBackground()

            Section {
                ScienceFigure(title: "Pressure-volume loop",
                              caption: preset == .normal ? "Counter-clockwise: filling along the bottom, the valves at the corners, ejection across the top."
                                                         : "The dashed loop is the normal heart, for comparison.",
                              spoken: "From \(scienceNumber(beat.edv)) to \(scienceNumber(beat.esv)) millilitres, peaking at \(scienceNumber(beat.lvSystolic)) millimetres of mercury.") {
                    Chart {
                        if preset != .normal {
                            ForEach(Array(reference.enumerated()), id: \.offset) { _, s in
                                LineMark(x: .value("Volume", s.lvVolume), y: .value("Pressure", s.lvPressure),
                                         series: .value("Heart", "Normal"))
                                    .foregroundStyle(Color.wardInkSecondary)
                                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            }
                        }
                        ForEach(Array(loop.enumerated()), id: \.offset) { _, s in
                            LineMark(x: .value("Volume", s.lvVolume), y: .value("Pressure", s.lvPressure),
                                     series: .value("Heart", preset.name))
                                .foregroundStyle(Color.wardPrimaryInk)
                        }
                    }
                    .chartXAxisLabel("mL")
                    .chartYAxisLabel("mmHg")
                }
            }
            .wardRowBackground()

            Section {
                ScienceFigure(title: "Pressures through one beat",
                              caption: "The dashed lines are the valves: mitral closes (S1), aortic opens, aortic closes (S2), mitral opens.",
                              spoken: "Aortic pressure \(scienceNumber(beat.aorticSystolic)) over \(scienceNumber(beat.aorticDiastolic)); left atrial mean \(scienceNumber(beat.meanLA)).") {
                    Chart {
                        ForEach(traces) { tr in
                            LineMark(x: .value("Time", tr.t), y: .value("mmHg", tr.mmHg), series: .value("Chamber", tr.name))
                                .foregroundStyle(by: .value("Chamber", tr.name))
                        }
                        ForEach(events) { e in
                            RuleMark(x: .value("Valve", e.ms))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .foregroundStyle(Color.wardInkSecondary)
                        }
                    }
                    .chartForegroundStyleScale(["Left ventricle": Color.wardPrimaryInk,
                                                "Aorta": Color.wardEcg,
                                                "Left atrium": Color.wardBeam])
                    .chartXAxisLabel("ms")
                    .chartYAxisLabel("mmHg")
                }
            }
            .wardRowBackground()

            Section("Result") {
                ScienceReading(label: "Blood pressure",
                               value: scienceNumber(beat.aorticSystolic) + "/" + scienceNumber(beat.aorticDiastolic))
                ScienceReading(label: "Stroke volume", value: scienceNumber(beat.strokeVolume) + " mL")
                ScienceReading(label: "Ejection fraction", value: sciencePercent(beat.ejectionFraction))
                ScienceReading(label: "Cardiac output", value: scienceNumber(beat.cardiacOutput, 1) + " L/min")
                ScienceReading(label: "End-diastolic pressure", value: scienceNumber(beat.lvEndDiastolic) + " mmHg")
                ScienceReading(label: "Left atrium, mean", value: scienceNumber(beat.meanLA) + " mmHg")
                if beat.peakAorticGradient > 10 {
                    ScienceReading(label: "Aortic valve gradient", value: scienceNumber(beat.peakAorticGradient) + " mmHg")
                }
                if beat.meanMitralGradient > 3 {
                    ScienceReading(label: "Mitral valve gradient", value: scienceNumber(beat.meanMitralGradient) + " mmHg")
                }
                if beat.regurgitantFraction > 0.05 {
                    ScienceReading(label: "Regurgitant fraction", value: sciencePercent(beat.regurgitantFraction))
                }
            }
            .wardRowBackground()
            .accessibilityElement(children: .combine)

            ScienceTextSection(title: "How it is worked out",
                               text: "Each chamber is an elastance that stiffens as it contracts and relaxes back; the arteries are a three-element Windkessel (impedance, compliance, resistance) and the veins a reservoir. Valves let blood through by Bernoulli's law (gradient = 4v\u{00B2}) and a leak lets it back. The model runs until each beat matches the last, then shows that beat.")
        }
        .onChange(of: preset) { _, now in
            beat = CardiacCycle.beat(now.parameters)
        }
    }
}

// MARK: - Blood pressure and flow

struct HaemodynamicsTool: View {
    @State private var systolic = 120.0
    @State private var diastolic = 80.0
    @State private var heartRate = 70.0
    @State private var strokeVolume = 70.0
    @State private var cvp = 5.0
    @State private var radius = 1.0

    private struct Point: Identifiable {
        let id: Int
        let ratio: Double
        let flow: Double
    }

    var body: some View {
        let low: Double = min(systolic, diastolic)
        let map: Double = Haemodynamics.meanArterial(systolic: max(systolic, diastolic), diastolic: low)
        let output: Double = Haemodynamics.cardiacOutput(heartRate: heartRate, strokeVolume: strokeVolume)
        let resistance: Double = Haemodynamics.systemicResistance(map: map, cvp: cvp, cardiacOutput: output) ?? .nan
        let flow: Double = Haemodynamics.poiseuilleFlowRatio(radiusRatio: radius)
        let curve: [Point] = (0...40).map { i in
            let r: Double = 0.5 + Double(i) / 40
            return Point(id: i, ratio: r, flow: Haemodynamics.poiseuilleFlowRatio(radiusRatio: r))
        }
        ScienceToolPage(tool: .haemodynamics) {
            Section("Values") {
                ScienceSlider(name: "Systolic", value: $systolic, range: 70...220, step: 1,
                              shown: scienceNumber(systolic) + " mmHg")
                ScienceSlider(name: "Diastolic", value: $diastolic, range: 30...130, step: 1,
                              shown: scienceNumber(diastolic) + " mmHg")
                ScienceSlider(name: "Heart rate", value: $heartRate, range: 30...200, step: 1,
                              shown: scienceNumber(heartRate) + " /min")
                ScienceSlider(name: "Stroke volume", value: $strokeVolume, range: 20...150, step: 1,
                              shown: scienceNumber(strokeVolume) + " mL")
                ScienceSlider(name: "Central venous pressure", value: $cvp, range: 0...25, step: 1,
                              shown: scienceNumber(cvp) + " mmHg")
            }
            .wardRowBackground()

            Section("Result") {
                ScienceReading(label: "Mean arterial pressure", value: scienceNumber(map) + " mmHg")
                ScienceReading(label: "Cardiac output", value: scienceNumber(output, 1) + " L/min")
                ScienceReading(label: "Systemic resistance", value: scienceNumber(resistance) + " dyn\u{00B7}s/cm\u{2075}")
                ScienceVerdict(text: verdict(map: map, resistance: resistance))
            }
            .wardRowBackground()
            .accessibilityElement(children: .combine)

            Section {
                ScienceFigure(title: "Why radius rules flow",
                              caption: "At the same pressure, flow follows the fourth power of the radius (Poiseuille): a vessel at \(sciencePercent(radius)) of its width carries \(sciencePercent(flow)) of the flow.",
                              spoken: "At \(sciencePercent(radius)) of its radius, a vessel carries \(sciencePercent(flow)) of its flow.") {
                    Chart {
                        ForEach(curve) { p in
                            LineMark(x: .value("Radius", p.ratio * 100), y: .value("Flow", p.flow * 100))
                                .foregroundStyle(Color.wardPrimaryInk)
                        }
                        PointMark(x: .value("Radius", radius * 100), y: .value("Flow", flow * 100))
                            .foregroundStyle(Color.wardBeam)
                            .symbolSize(80)
                    }
                    .chartXAxisLabel("radius, % of normal")
                    .chartYAxisLabel("flow, %")
                }
                ScienceSlider(name: "Radius", value: $radius, range: 0.5...1.5, step: 0.01,
                              shown: sciencePercent(radius) + " of normal")
            }
            .wardRowBackground()

            ScienceTextSection(title: "How it is worked out",
                               text: "Mean arterial pressure \u{2248} diastolic + a third of the pulse pressure. Cardiac output = heart rate \u{00D7} stroke volume. Systemic resistance = 80 \u{00D7} (MAP \u{2212} CVP) / cardiac output, the 80 turning mmHg\u{00B7}min/L into dyn\u{00B7}s/cm\u{2075}; normal is about 800 to 1,200.")
        }
    }

    private func verdict(map: Double, resistance: Double) -> String {
        if map < 65 { return "A mean pressure under 65 mmHg: organs are no longer sure of their blood supply." }
        if resistance > 1400 { return "High resistance: the vessels are clamped down, as in cardiogenic or hypovolaemic shock, or hypertension." }
        if resistance < 700 { return "Low resistance: the vessels are wide open, as in sepsis or anaphylaxis, or during exercise." }
        return "Pressure and resistance in the usual range."
    }
}

// MARK: - Capillary forces

struct StarlingTool: View {
    @State private var cause: Starling.Oedema?
    @State private var arterial = 35.0
    @State private var venous = 15.0
    @State private var capillaryOncotic = 25.0
    @State private var interstitialOncotic = 3.0
    @State private var reflection = 1.0

    private struct Point: Identifiable {
        let id: Int
        let along: Double
        let net: Double
    }

    private func forces(at hydrostatic: Double) -> Starling.Forces {
        Starling.Forces(capillaryHydrostatic: hydrostatic, capillaryOncotic: capillaryOncotic,
                        interstitialOncotic: interstitialOncotic, reflection: reflection)
    }

    var body: some View {
        let points: [Point] = (0...20).map { i in
            let x: Double = Double(i) / 20
            return Point(id: i, along: x * 100, net: Starling.net(forces(at: arterial + (venous - arterial) * x)))
        }
        let atArterial: Double = Starling.net(forces(at: arterial))
        let atVenous: Double = Starling.net(forces(at: venous))
        let mean: Double = points.map(\.net).reduce(0, +) / Double(points.count)
        ScienceToolPage(tool: .starling) {
            Section {
                ScienceFigure(title: "Net pressure along the capillary",
                              caption: "Above the line fluid leaves the capillary; below it, fluid comes back. Whatever is left over, the lymph has to carry away.",
                              spoken: "Net \(scienceNumber(atArterial)) millimetres of mercury out at the arterial end and \(scienceNumber(atVenous)) at the venous end.") {
                    Chart {
                        ForEach(points) { p in
                            AreaMark(x: .value("Along", p.along), y: .value("Net", p.net))
                                .foregroundStyle(Color.wardPrimaryInk.opacity(0.25))
                            LineMark(x: .value("Along", p.along), y: .value("Net", p.net))
                                .foregroundStyle(Color.wardPrimaryInk)
                        }
                        RuleMark(y: .value("Zero", 0.0))
                            .foregroundStyle(Color.wardInkSecondary)
                    }
                    .chartYScale(domain: -25.0...35.0)
                    .chartXAxisLabel("arterial end \u{2192} venous end, %")
                    .chartYAxisLabel("mmHg")
                }
            }
            .wardRowBackground()

            Section("Values") {
                Picker("Cause of oedema", selection: $cause) {
                    Text("None").tag(Starling.Oedema?.none)
                    ForEach(Starling.Oedema.allCases) { c in
                        Text(c.name).tag(Starling.Oedema?.some(c))
                    }
                }
                .pickerStyle(.menu)
                ScienceSlider(name: "Capillary pressure, arterial end", value: $arterial, range: 10...60, step: 1,
                              shown: scienceNumber(arterial) + " mmHg")
                ScienceSlider(name: "Capillary pressure, venous end", value: $venous, range: 0...40, step: 1,
                              shown: scienceNumber(venous) + " mmHg")
                ScienceSlider(name: "Plasma oncotic pressure", value: $capillaryOncotic, range: 5...35, step: 1,
                              shown: scienceNumber(capillaryOncotic) + " mmHg")
                ScienceSlider(name: "Tissue oncotic pressure", value: $interstitialOncotic, range: 0...15, step: 0.5,
                              shown: scienceNumber(interstitialOncotic, 1) + " mmHg")
                ScienceSlider(name: "Reflection coefficient", value: $reflection, range: 0...1, step: 0.05,
                              shown: scienceNumber(reflection, 2))
            }
            .wardRowBackground()

            Section("Result") {
                ScienceReading(label: "Arterial end", value: signed(atArterial) + " mmHg")
                ScienceReading(label: "Venous end", value: signed(atVenous) + " mmHg")
                ScienceReading(label: "On average", value: signed(mean) + " mmHg")
                ScienceVerdict(text: mean > 5 ? "More leaves than returns: if the lymph cannot keep up, oedema."
                                              : "Filtration and return nearly balance; the lymph carries the small remainder.")
            }
            .wardRowBackground()
            .accessibilityElement(children: .combine)

            ScienceTextSection(title: "How it is worked out",
                               text: "Net pressure = (Pc \u{2212} Pi) \u{2212} \u{03C3}(\u{03C0}c \u{2212} \u{03C0}i): the capillary's pressure pushing out against the tissue's, less the proteins' pull back in, scaled by how well the wall holds protein (\u{03C3}, 1 for a tight wall). The tissue's own pressure is taken as 1 mmHg.")
            ScienceTextSection(title: "Keep in mind",
                               text: "The revised Starling principle: the glycocalyx sets the oncotic gradient that matters, and in most tissues little fluid returns at the venous end; the lymph returns most of it. The four causes of oedema still follow from the same terms.")
        }
        .onChange(of: cause) { _, now in
            let v: Starling.Forces = now?.venousEnd ?? Starling.venousEnd
            venous = v.capillaryHydrostatic
            arterial = Starling.arterialEnd.capillaryHydrostatic + (v.capillaryHydrostatic - Starling.venousEnd.capillaryHydrostatic)
            capillaryOncotic = v.capillaryOncotic
            interstitialOncotic = v.interstitialOncotic
            reflection = v.reflection
        }
    }

    private func signed(_ x: Double) -> String { (x > 0 ? "+" : "") + scienceNumber(x) }
}

// MARK: - Oxygen curve

struct OxygenCurveTool: View {
    @State private var paco2 = 40.0
    @State private var baseExcess = 0.0
    @State private var celsius = 37.0
    @State private var fetal = false
    @State private var po2 = 40.0
    /// Haemoglobin as moved; until then (and again when the body changes)
    /// the body's typical value.
    @State private var hbMoved: Double?
    @AppStorage(AnatomySex.rememberedKey) private var rememberedBody = AnatomySex.male.rawValue

    private var sex: AnatomySex { AnatomySex(remembered: rememberedBody) }
    private var hb: Double { hbMoved ?? OxygenCurve.typicalHaemoglobin(sex) }

    private struct Point: Identifiable {
        let id: String
        let po2: Double
        let sat: Double
        let curve: String
    }

    /// pH from the PaCO2 and a bicarbonate of 24 + base excess
    /// (Henderson-Hasselbalch), so carbon dioxide moves the curve the way it
    /// does in the blood (the Bohr effect).
    private var pH: Double {
        AcidBase.predictedPH(hco3: max(4, 24 + baseExcess), paco2: paco2)
    }

    var body: some View {
        let shifted = OxygenCurve.Conditions(pH: pH, celsius: celsius, baseExcess: baseExcess, fetal: fetal)
        let standard = OxygenCurve.Conditions()
        let changed: Bool = shifted != standard
        let points: [Point] = OxygenCurve.curve(shifted).map { Point(id: "s\($0.po2)", po2: $0.po2, sat: $0.sat * 100, curve: "Now") }
            + (changed ? OxygenCurve.curve(standard).map { Point(id: "n\($0.po2)", po2: $0.po2, sat: $0.sat * 100, curve: "Standard") } : [])
        let p50: Double = OxygenCurve.p50(shifted)
        let sat: Double = OxygenCurve.saturation(po2: po2, shifted)
        let content: Double = OxygenCurve.content(hb: hb, saturation: sat, po2: po2)
        ScienceToolPage(tool: .oxygenCurve) {
            Section {
                ScienceFigure(title: "Haemoglobin's saturation against PO2",
                              caption: changed ? "The dashed curve is the standard one (pH 7.4, 37 \u{00B0}C). Right means oxygen is given up more easily; left, held more tightly."
                                               : "The standard curve: pH 7.4, 37 \u{00B0}C, half-saturated at about 27 mmHg.",
                              spoken: "P50 \(scienceNumber(p50, 1)) millimetres of mercury; at \(scienceNumber(po2)) the saturation is \(sciencePercent(sat)).") {
                    Chart {
                        ForEach(points) { p in
                            LineMark(x: .value("PO2", p.po2), y: .value("Saturation", p.sat), series: .value("Curve", p.curve))
                                .foregroundStyle(p.curve == "Now" ? Color.wardPrimaryInk : Color.wardInkSecondary)
                                .lineStyle(p.curve == "Now" ? StrokeStyle(lineWidth: 2) : StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        }
                        RuleMark(x: .value("P50", p50))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                            .foregroundStyle(Color.wardBeam)
                        PointMark(x: .value("PO2", po2), y: .value("Saturation", sat * 100))
                            .foregroundStyle(Color.wardBeam)
                            .symbolSize(80)
                    }
                    .chartYScale(domain: 0.0...100.0)
                    .chartXAxisLabel("PO2, mmHg")
                    .chartYAxisLabel("%")
                }
            }
            .wardRowBackground()

            Section("Values") {
                ScienceSlider(name: "Carbon dioxide (PaCO2)", value: $paco2, range: 15...90, step: 1,
                              shown: scienceNumber(paco2) + " mmHg")
                ScienceSlider(name: "Base excess", value: $baseExcess, range: -15...15, step: 1,
                              shown: scienceNumber(baseExcess) + " mmol/L")
                ScienceSlider(name: "Temperature", value: $celsius, range: 32...42, step: 0.1,
                              shown: scienceNumber(celsius, 1) + " \u{00B0}C")
                Toggle("Fetal haemoglobin", isOn: $fetal)
                ScienceSlider(name: "PO2 to read", value: $po2, range: 5...120, step: 1,
                              shown: scienceNumber(po2) + " mmHg")
                ScienceBodyPicker(sex: Binding(get: { sex }, set: { rememberedBody = $0.rawValue; hbMoved = nil }))
                ScienceSlider(name: "Haemoglobin", value: Binding(get: { hb }, set: { hbMoved = $0 }), range: 4...20, step: 0.5,
                              shown: scienceNumber(hb, 1) + " g/dL")
            }
            .wardRowBackground()

            Section("Result") {
                ScienceReading(label: "pH", value: scienceNumber(pH, 2))
                ScienceReading(label: "P50", value: scienceNumber(p50, 1) + " mmHg")
                ScienceReading(label: "Saturation", value: sciencePercent(sat, 1))
                ScienceReading(label: "Oxygen content", value: scienceNumber(content, 1) + " mL/dL")
                if !fetal {
                    ScienceReading(label: "Anaemia line", value: "under " + scienceNumber(OxygenCurve.anaemiaLine(sex)) + " g/dL")
                }
                ScienceVerdict(text: (p50 > OxygenCurve.standardP50 + 1 ? "Shifted right: acid, carbon dioxide or heat, as in working muscle. Oxygen is unloaded more easily."
                                      : p50 < OxygenCurve.standardP50 - 1 ? "Shifted left: oxygen is held more tightly, as by fetal haemoglobin, in alkalosis or cold."
                                      : "Close to the standard curve.")
                               + (!fetal && hb < OxygenCurve.anaemiaLine(sex) ? " Haemoglobin is below the line: anaemic, so the blood carries less oxygen at any saturation." : ""))
            }
            .wardRowBackground()
            .accessibilityElement(children: .combine)

            ScienceTextSection(title: "How it is worked out",
                               text: "Severinghaus's equation for the curve, S = 1 / (23,400 / (P\u{00B3} + 150P) + 1), with Kelman's shifts of P50 for pH, temperature and base excess. The pH here comes from the PaCO2 and a bicarbonate of 24 + base excess. Oxygen content = 1.34 \u{00D7} Hb \u{00D7} saturation + 0.003 \u{00D7} PO2.")
            ScienceTextSection(title: "Keep in mind",
                               text: "2,3-BPG shifts the curve right too (anaemia, altitude); it is not modelled here. Carbon monoxide shifts it left and takes haemoglobin out of play. The anaemia lines are the WHO's for adults who are not pregnant. Men's run higher: testosterone drives erythropoietin, and menstruation costs iron.")
        }
    }
}

// MARK: - Alveolar gas

struct AlveolarGasTool: View {
    @State private var fio2 = 0.21
    @State private var paco2 = 40.0
    @State private var pao2 = 90.0
    @State private var age = 40.0
    @State private var altitude = 0

    private static let pressures: [(name: String, mmHg: Double)] = [("Sea level", 760), ("1,500 m", 630), ("3,000 m", 525), ("5,000 m", 405)]

    var body: some View {
        let atmospheric: Double = Self.pressures[altitude].mmHg
        let alveolar: Double = LungGas.alveolarO2(fio2: fio2, paco2: paco2, atmospheric: atmospheric)
        let gradient: Double = LungGas.aaGradient(pao2: pao2, paco2: paco2, fio2: fio2, atmospheric: atmospheric)
        let expected: Double = LungGas.expectedAAGradient(age: age)
        ScienceToolPage(tool: .alveolarGas) {
            Section("Values") {
                ScienceSlider(name: "Inspired oxygen (FiO2)", value: $fio2, range: 0.21...1, step: 0.01,
                              shown: sciencePercent(fio2))
                ScienceSlider(name: "PaCO2", value: $paco2, range: 15...100, step: 1,
                              shown: scienceNumber(paco2) + " mmHg")
                ScienceSlider(name: "PaO2", value: $pao2, range: 30...600, step: 1,
                              shown: scienceNumber(pao2) + " mmHg")
                ScienceSlider(name: "Age", value: $age, range: 18...95, step: 1,
                              shown: scienceNumber(age) + " years")
                VStack(alignment: .leading, spacing: WardSpace.s) {
                    Text("Altitude")
                    WardSegmented(selection: $altitude, options: Array(Self.pressures.indices)) { i in
                        Text(Self.pressures[i].name)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Altitude")
                }
                .padding(.vertical, WardSpace.xs)
            }
            .wardRowBackground()

            Section("Result") {
                ScienceReading(label: "Alveolar oxygen (PAO2)", value: scienceNumber(alveolar) + " mmHg")
                ScienceReading(label: "A-a gradient", value: scienceNumber(gradient) + " mmHg")
                ScienceReading(label: "Expected at this age", value: "under " + scienceNumber(expected) + " mmHg")
                ScienceVerdict(text: verdict(gradient: gradient, expected: expected))
            }
            .wardRowBackground()
            .accessibilityElement(children: .combine)

            ScienceTextSection(title: "How it is worked out",
                               text: "PAO2 = FiO2 \u{00D7} (barometric pressure \u{2212} 47) \u{2212} PaCO2 / 0.8: the oxygen breathed in, less water vapour, less what carbon dioxide displaces (the respiratory quotient is taken as 0.8). The A-a gradient is PAO2 \u{2212} PaO2; breathing air, its upper limit is about age / 4 + 4.")
            ScienceTextSection(title: "Keep in mind",
                               text: "A low PaO2 with a normal gradient is hypoventilation (opioids, weakness) or thin air. A raised gradient means the lung itself: ventilation-perfusion mismatch (the commonest), shunt, or a diffusion problem. On high oxygen the gradient widens anyway, so judge it breathing air where you can.")
        }
    }

    private func verdict(gradient: Double, expected: Double) -> String {
        if gradient < 0 { return "A negative gradient is impossible: check that the PaO2 and FiO2 belong together." }
        if fio2 > 0.3 { return "On added oxygen the gradient runs high even in healthy lungs; read it with care." }
        if gradient > expected { return "Raised: the problem is in the lung itself (mismatch, shunt or diffusion)." }
        return pao2 < 80 ? "Normal gradient with a low PaO2: hypoventilation or low inspired oxygen."
                         : "Normal."
    }
}

// MARK: - The body a tool is for

/// Male or Female, for a tool whose numbers differ by sex: the atlas's
/// remembered choice (AnatomySex.rememberedKey), so the body chosen there
/// is the one the tools start with.
struct ScienceBodyPicker: View {
    @Binding var sex: AnatomySex

    var body: some View {
        VStack(alignment: .leading, spacing: WardSpace.s) {
            Text("Body")
            WardSegmented(selection: $sex, options: AnatomySex.allCases) { sex in
                Text(sex.name)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Body")
            .accessibilityIdentifier("scienceBody")
        }
        .padding(.vertical, WardSpace.xs)
    }
}

// MARK: - Renal clearance

struct RenalClearanceTool: View {
    @State private var plasmaCreatinine = 90.0
    @State private var urineCreatinine = 9.0
    @State private var flow = 1.0
    @State private var plasmaNa = 140.0
    @State private var urineNa = 20.0
    @State private var plasmaOsm = 290.0
    @State private var urineOsm = 600.0
    @State private var age = 40.0
    @AppStorage(AnatomySex.rememberedKey) private var rememberedBody = AnatomySex.male.rawValue

    private var sex: AnatomySex { AnatomySex(remembered: rememberedBody) }

    var body: some View {
        let egfr: Double = WardFormula.ckdEpi2021(age: age, creatinineMgdl: plasmaCreatinine * WardUnit.creatinine.usPerSI,
                                                  female: sex == .female)
        let urineCrMicro: Double = urineCreatinine * 1000
        let clearance: Double = RenalPhysiology.clearance(urine: urineCrMicro, flow: flow, plasma: plasmaCreatinine) ?? .nan
        let fena: Double = RenalPhysiology.fractionalExcretionNa(urineNa: urineNa, plasmaNa: plasmaNa,
                                                                 urineCreatinine: urineCrMicro,
                                                                 plasmaCreatinine: plasmaCreatinine) ?? .nan
        let freeWater: Double = RenalPhysiology.freeWaterClearance(flow: flow, urineOsm: urineOsm, plasmaOsm: plasmaOsm) ?? .nan
        ScienceToolPage(tool: .renalClearance) {
            Section("Values") {
                ScienceSlider(name: "Plasma creatinine", value: $plasmaCreatinine, range: 40...900, step: 5,
                              shown: scienceNumber(plasmaCreatinine) + " \u{00B5}mol/L")
                ScienceSlider(name: "Urine creatinine", value: $urineCreatinine, range: 1...25, step: 0.5,
                              shown: scienceNumber(urineCreatinine, 1) + " mmol/L")
                ScienceSlider(name: "Urine flow", value: $flow, range: 0.1...10, step: 0.1,
                              shown: scienceNumber(flow, 1) + " mL/min")
                ScienceSlider(name: "Plasma sodium", value: $plasmaNa, range: 115...165, step: 1,
                              shown: scienceNumber(plasmaNa) + " mmol/L")
                ScienceSlider(name: "Urine sodium", value: $urineNa, range: 1...150, step: 1,
                              shown: scienceNumber(urineNa) + " mmol/L")
                ScienceSlider(name: "Plasma osmolality", value: $plasmaOsm, range: 250...330, step: 1,
                              shown: scienceNumber(plasmaOsm) + " mOsm/kg")
                ScienceSlider(name: "Urine osmolality", value: $urineOsm, range: 50...1200, step: 10,
                              shown: scienceNumber(urineOsm) + " mOsm/kg")
                ScienceBodyPicker(sex: Binding(get: { sex }, set: { rememberedBody = $0.rawValue }))
                ScienceSlider(name: "Age", value: $age, range: 18...95, step: 1,
                              shown: scienceNumber(age) + " years")
            }
            .wardRowBackground()

            Section("Result") {
                ScienceReading(label: "Creatinine clearance", value: scienceNumber(clearance) + " mL/min")
                ScienceReading(label: "FENa", value: scienceNumber(fena, 2) + "%")
                ScienceReading(label: "Free water clearance", value: scienceNumber(freeWater, 1) + " mL/min")
                ScienceReading(label: "eGFR", value: scienceNumber(egfr) + " mL/min/1.73 m\u{00B2}")
                ScienceVerdict(text: RenalPhysiology.fenaReading(fena) + " "
                               + (freeWater < 0 ? "Negative free water clearance: the kidney is concentrating, keeping water (ADH at work)."
                                                : "Positive free water clearance: the kidney is making dilute urine, losing water."))
            }
            .wardRowBackground()
            .accessibilityElement(children: .combine)

            Section("Try") {
                SciencePresetButton(title: "Healthy", detail: "Clearance about 100 mL/min") {
                    plasmaCreatinine = 90; urineCreatinine = 9; flow = 1; urineNa = 60; urineOsm = 600
                }
                SciencePresetButton(title: "Prerenal: dehydration", detail: "Sodium held, urine concentrated") {
                    plasmaCreatinine = 180; urineCreatinine = 18; flow = 0.3; urineNa = 10; urineOsm = 800
                }
                SciencePresetButton(title: "Acute tubular injury", detail: "Sodium lost, urine near plasma's strength") {
                    plasmaCreatinine = 400; urineCreatinine = 3; flow = 0.4; urineNa = 60; urineOsm = 320
                }
            }
            .wardRowBackground()

            ScienceTextSection(title: "How it is worked out",
                               text: "Clearance = urine concentration \u{00D7} urine flow / plasma concentration. Creatinine is filtered and barely secreted, so its clearance estimates the GFR (a little high, by the part secreted). FENa = (urine Na \u{00D7} plasma creatinine) / (plasma Na \u{00D7} urine creatinine) \u{00D7} 100. Free water clearance = flow \u{2212} (urine osmolality \u{00D7} flow / plasma osmolality). The eGFR is the CKD-EPI 2021 equation, from the plasma creatinine, age and sex.")
            ScienceTextSection(title: "Keep in mind",
                               text: "Diuretics make FENa unreliable (urea's fractional excretion, under 35% in a prerenal kidney, is used instead). Inulin clearance is the true GFR; PAH clearance measures renal plasma flow. The same creatinine means a lower GFR in a woman, who has less muscle to make it, and in someone older.")
        }
    }
}

// MARK: - Blood gas reader

struct AcidBaseTool: View {
    @State private var pH = 7.40
    @State private var paco2 = 40.0
    @State private var hco3 = 24.0
    @State private var sodium = 140.0
    @State private var chloride = 104.0
    @State private var albumin = 40.0

    private struct Example {
        let name: String
        let detail: String
        let values: (pH: Double, paco2: Double, hco3: Double, na: Double, cl: Double, albumin: Double)
    }

    private static let examples: [Example] = [
        Example(name: "Diabetic ketoacidosis", detail: "High anion gap acidosis, breathing it off",
                values: (7.12, 22, 7, 134, 98, 40)),
        Example(name: "Diarrhoea", detail: "Normal anion gap acidosis", values: (7.28, 30, 14, 138, 114, 40)),
        Example(name: "Vomiting", detail: "Metabolic alkalosis", values: (7.52, 47, 38, 136, 88, 40)),
        Example(name: "Opioid overdose", detail: "Acute respiratory acidosis", values: (7.21, 70, 27, 140, 103, 40)),
        Example(name: "COPD, stable", detail: "Chronic respiratory acidosis", values: (7.36, 60, 33, 140, 97, 40)),
        Example(name: "Panic attack", detail: "Acute respiratory alkalosis", values: (7.55, 25, 22, 140, 104, 40)),
    ]

    var body: some View {
        let gas = AcidBase.Gas(pH: pH, paco2: paco2, hco3: hco3, sodium: sodium, chloride: chloride, albumin: albumin)
        let reading: AcidBase.Reading = AcidBase.read(gas)
        ScienceToolPage(tool: .acidBase) {
            Section("Values") {
                ScienceSlider(name: "pH", value: $pH, range: 6.8...7.8, step: 0.01, shown: scienceNumber(pH, 2))
                ScienceSlider(name: "PaCO2", value: $paco2, range: 10...120, step: 1, shown: scienceNumber(paco2) + " mmHg")
                ScienceSlider(name: "Bicarbonate", value: $hco3, range: 2...60, step: 1, shown: scienceNumber(hco3) + " mmol/L")
                ScienceSlider(name: "Sodium", value: $sodium, range: 115...165, step: 1, shown: scienceNumber(sodium) + " mmol/L")
                ScienceSlider(name: "Chloride", value: $chloride, range: 75...130, step: 1, shown: scienceNumber(chloride) + " mmol/L")
                ScienceSlider(name: "Albumin", value: $albumin, range: 10...50, step: 1, shown: scienceNumber(albumin) + " g/L")
            }
            .wardRowBackground()

            Section("Result") {
                if let gap = reading.anionGap {
                    ScienceReading(label: "Anion gap", value: scienceNumber(gap))
                }
                if let corrected = reading.correctedGap {
                    ScienceReading(label: "Corrected for albumin", value: scienceNumber(corrected, 1))
                }
                if let delta = reading.deltaRatio {
                    ScienceReading(label: "Delta ratio", value: scienceNumber(delta, 1))
                }
                if reading.isNormal {
                    ScienceVerdict(text: "No acid-base disorder.")
                }
                ForEach(reading.disorders, id: \.self) { d in
                    Label(d.name, systemImage: d == reading.primary ? "1.circle.fill" : "plus.circle")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.wardInk)
                }
                if let timing = reading.timing {
                    ScienceVerdict(text: timing)
                }
            }
            .wardRowBackground()
            .accessibilityElement(children: .combine)

            Section("Step by step") {
                ForEach(Array(reading.steps.enumerated()), id: \.offset) { i, step in
                    Label {
                        Text(step)
                            .font(.subheadline)
                            .foregroundStyle(Color.wardInk)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "\(min(i + 1, 50)).circle")
                            .foregroundStyle(Color.wardPrimaryInk)
                    }
                }
            }
            .wardRowBackground()

            Section("Try") {
                ForEach(Self.examples, id: \.name) { e in
                    SciencePresetButton(title: e.name, detail: e.detail) {
                        pH = e.values.pH; paco2 = e.values.paco2; hco3 = e.values.hco3
                        sodium = e.values.na; chloride = e.values.cl; albumin = e.values.albumin
                    }
                }
            }
            .wardRowBackground()

            ScienceTextSection(title: "How it is worked out",
                               text: "The pH names the side; the PaCO2 or bicarbonate that explains it is the primary disorder. Compensation is checked against what is expected: Winter's formula (PaCO2 = 1.5 \u{00D7} HCO3 + 8 \u{00B1} 2) for a metabolic acidosis, 0.7 \u{00D7} HCO3 + 21 for an alkalosis, and the bicarbonate's rise per 10 mmHg of CO2 for an acute or chronic respiratory disorder. Anion gap = Na \u{2212} (Cl + HCO3), plus 2.5 for every 10 g/L of albumin under 40; the delta ratio looks for a second metabolic disorder.")
        }
    }
}
