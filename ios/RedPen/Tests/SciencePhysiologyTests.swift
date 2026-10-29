// The physiology tools' arithmetic against the numbers in every textbook:
// Nernst and Goldman potentials, the Hodgkin-Huxley action potential and its
// refractory period, the oxygen curve and its shifts, Starling forces, the
// alveolar gas equation, renal clearance, the cardiac cycle with its valve
// lesions, and the blood gas reader on classic cases.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

func near(_ a: Double?, _ b: Double, _ tol: Double) -> Bool {
    guard let a else { return false }
    return abs(a - b) <= tol
}

// MARK: membrane

check("RT/F is 26.7 mV at 37 °C", near(Membrane.thermalVoltage(), 26.7, 0.05))
let ek: Double? = Membrane.nernst(valence: 1, outside: 4, inside: 140)
check("EK is about -95 mV", near(ek, -95, 1), "\(ek ?? .nan)")
let ena: Double? = Membrane.nernst(valence: 1, outside: 145, inside: 12)
check("ENa is about +67 mV", near(ena, 66.6, 1), "\(ena ?? .nan)")
let eca: Double? = Membrane.nernst(valence: 2, outside: 2.5, inside: 0.0001)
check("ECa is about +135 mV", near(eca, 135, 2), "\(eca ?? .nan)")
let ecl: Double? = Membrane.nernst(valence: -1, outside: 110, inside: 10)
check("ECl is about -64 mV", near(ecl, -64, 1), "\(ecl ?? .nan)")
check("no Nernst potential for a zero concentration", Membrane.nernst(valence: 1, outside: 0, inside: 140) == nil)
let rest: Double? = Membrane.goldman()
check("Goldman gives a resting potential near -69 mV", near(rest, -69, 1.5), "\(rest ?? .nan)")
var hyperK: Membrane.Ions = Membrane.Ions(); hyperK.kOut = 8
check("raising outside K depolarises the cell", (Membrane.goldman(hyperK) ?? -100) > (rest ?? 0) + 5)

// MARK: Hodgkin-Huxley

let settled: HodgkinHuxley.State = HodgkinHuxley.settle(HodgkinHuxley.Parameters())
check("the axon rests at -65 mV", near(settled.v, -65, 0.5), "\(settled.v)")
let quiet: [HodgkinHuxley.Sample] = HodgkinHuxley.run(pulses: [])
check("with no stimulus there is no spike", HodgkinHuxley.spikes(quiet).isEmpty && quiet.allSatisfy { abs($0.v + 65) < 1 })
let fired: [HodgkinHuxley.Sample] = HodgkinHuxley.run(pulses: [.init(start: 2, duration: 1, amplitude: 15)])
let peak: Double = fired.map(\.v).max() ?? 0
check("a 15 µA/cm² pulse fires one action potential", HodgkinHuxley.spikes(fired).count == 1, "\(HodgkinHuxley.spikes(fired))")
check("the spike overshoots to about +40 mV", peak > 30 && peak < 50, "\(peak)")
let trough: Double = fired.filter { $0.t > 6 }.map(\.v).min() ?? 0
check("it undershoots below rest (after-hyperpolarisation)", trough < -70, "\(trough)")
let weak: [HodgkinHuxley.Sample] = HodgkinHuxley.run(pulses: [.init(start: 2, duration: 1, amplitude: 2)])
check("a 2 µA/cm² pulse stays below threshold", HodgkinHuxley.spikes(weak).isEmpty)
let pair: [HodgkinHuxley.Sample] = HodgkinHuxley.run(pulses: [.init(start: 2, duration: 1, amplitude: 15),
                                                              .init(start: 5, duration: 1, amplitude: 15)])
check("a second pulse 3 ms later finds the axon refractory", HodgkinHuxley.spikes(pair).count == 1)
let later: [HodgkinHuxley.Sample] = HodgkinHuxley.run(pulses: [.init(start: 2, duration: 1, amplitude: 15),
                                                               .init(start: 22, duration: 1, amplitude: 15)], milliseconds: 40)
check("20 ms later it fires again", HodgkinHuxley.spikes(later).count == 2)
let ttx: [HodgkinHuxley.Sample] = HodgkinHuxley.run(HodgkinHuxley.Parameters().sodiumBlocked(1),
                                                    pulses: [.init(start: 2, duration: 1, amplitude: 15)])
check("blocking sodium channels (tetrodotoxin) abolishes the spike", HodgkinHuxley.spikes(ttx).isEmpty)
let kBlock: [HodgkinHuxley.Sample] = HodgkinHuxley.run(HodgkinHuxley.Parameters().potassiumBlocked(0.6),
                                                       pulses: [.init(start: 2, duration: 1, amplitude: 15)])
func width(_ trace: [HodgkinHuxley.Sample]) -> Double {
    let above: [HodgkinHuxley.Sample] = trace.filter { $0.v > -20 }
    guard let a = above.first?.t, let b = above.last?.t else { return 0 }
    return b - a
}
check("blocking potassium channels widens the spike", width(kBlock) > width(fired) * 1.2,
      "\(width(kBlock)) vs \(width(fired))")
let hyperkalaemia: HodgkinHuxley.Parameters = HodgkinHuxley.Parameters().outsidePotassium(8)
check("hyperkalaemia moves EK up by the Nernst shift (about 18.5 mV)", near(hyperkalaemia.eK, -77 + 18.5, 0.3), "\(hyperkalaemia.eK)")
check("and depolarises the resting axon", HodgkinHuxley.settle(hyperkalaemia).v > settled.v + 2)
check("rate functions are finite at their 0/0 points",
      HodgkinHuxley.alphaN(-55).isFinite && HodgkinHuxley.alphaM(-40).isFinite
      && near(HodgkinHuxley.alphaN(-55), 0.1, 1e-9) && near(HodgkinHuxley.alphaM(-40), 1, 1e-9))

// MARK: oxygen

check("P50 is 26.9 mmHg at pH 7.4 and 37 °C", near(OxygenCurve.p50(), 26.86, 0.01))
check("the WHO's anaemia line: 13 g/dL for a man, 12 for a woman",
      OxygenCurve.anaemiaLine(.male) == 13 && OxygenCurve.anaemiaLine(.female) == 12)
check("each sex starts above its own line, the man higher",
      AnatomySex.allCases.allSatisfy { OxygenCurve.typicalHaemoglobin($0) > OxygenCurve.anaemiaLine($0) }
        && OxygenCurve.typicalHaemoglobin(.male) > OxygenCurve.typicalHaemoglobin(.female))
check("saturation is 50% at P50", near(OxygenCurve.saturation(po2: 26.86), 0.5, 0.005))
check("arterial blood (PO2 100) is about 97.5% saturated", near(OxygenCurve.saturation(po2: 100), 0.975, 0.005))
check("mixed venous blood (PO2 40) is about 75% saturated", near(OxygenCurve.saturation(po2: 40), 0.75, 0.01))
let acid: OxygenCurve.Conditions = OxygenCurve.Conditions(pH: 7.2)
check("acidosis shifts the curve right (Bohr)", OxygenCurve.p50(acid) > 32 && OxygenCurve.saturation(po2: 40, acid) < 0.7,
      "\(OxygenCurve.p50(acid))")
let fever: OxygenCurve.Conditions = OxygenCurve.Conditions(celsius: 40)
check("fever shifts it right", OxygenCurve.p50(fever) > OxygenCurve.p50() + 3)
let cold: OxygenCurve.Conditions = OxygenCurve.Conditions(celsius: 32)
check("cold shifts it left", OxygenCurve.p50(cold) < OxygenCurve.p50() - 3)
let fetal: OxygenCurve.Conditions = OxygenCurve.Conditions(fetal: true)
check("fetal haemoglobin sits left, P50 19", near(OxygenCurve.p50(fetal), 19, 0.01)
      && OxygenCurve.saturation(po2: 30, fetal) > OxygenCurve.saturation(po2: 30))
let content: Double = OxygenCurve.content(hb: 15, saturation: 0.98, po2: 100)
check("arterial O2 content is about 20 mL/dL", near(content, 20, 0.5), "\(content)")
check("anaemia halves the content though saturation is normal",
      near(OxygenCurve.content(hb: 7.5, saturation: 0.98, po2: 100) / content, 0.5, 0.02))
check("delivery is about 1000 mL/min at 5 L/min", near(OxygenCurve.delivery(cardiacOutput: 5, content: content), 1000, 30))
let points = OxygenCurve.curve()
check("the curve rises monotonically", zip(points, points.dropFirst()).allSatisfy { $0.sat <= $1.sat } && points.count == 121)

// MARK: Starling

check("filtration at the arterial end", Starling.net(Starling.arterialEnd) > 0)
check("absorption at the venous end (classical teaching)", Starling.net(Starling.venousEnd) < 0)
for cause in Starling.Oedema.allCases {
    check("\(cause.name) raises venous-end filtration", Starling.net(cause.venousEnd) > Starling.net(Starling.venousEnd))
}

// MARK: lung

check("PAO2 on air at sea level is about 100 mmHg", near(LungGas.alveolarO2(), 99.7, 0.5))
check("A-a gradient for PaO2 90 is about 10", near(LungGas.aaGradient(pao2: 90, paco2: 40), 9.7, 0.5))
check("expected A-a gradient at 40 years is 14", LungGas.expectedAAGradient(age: 40) == 14)
check("alveolar ventilation 500 mL, 150 dead space, 12 breaths: 4.2 L/min",
      LungGas.alveolarVentilation(tidal: 500, deadSpace: 150, rate: 12) == 4200)
check("Bohr dead space 0.3", near(LungGas.deadSpaceFraction(paco2: 40, mixedExpiredCO2: 28), 0.3, 1e-9))
check("compliance 500 mL over 5 cmH2O is 100", LungGas.compliance(deltaVolume: 500, deltaPressure: 5) == 100)
check("5.3 kPa is about 40 mmHg", near(AcidBase.mmHg(kPa: 5.3), 39.75, 0.05))

// MARK: renal

check("inulin clearance: U 30, V 1, P 0.25 gives 120 mL/min",
      near(RenalPhysiology.clearance(urine: 30, flow: 1, plasma: 0.25), 120, 1e-9))
check("filtration fraction 120/600 is 0.2", near(RenalPhysiology.filtrationFraction(gfr: 120, rpf: 600), 0.2, 1e-9))
check("renal blood flow 600 / (1 − 0.45) is about 1091", near(RenalPhysiology.bloodFlow(rpf: 600, haematocrit: 0.45), 1090.9, 0.5))
let fena: Double? = RenalPhysiology.fractionalExcretionNa(urineNa: 10, plasmaNa: 140, urineCreatinine: 10_000, plasmaCreatinine: 100)
check("FENa 0.07% reads as prerenal", near(fena, 0.0714, 0.001) && RenalPhysiology.fenaReading(fena ?? 9).contains("prerenal"))
check("dilute urine has positive free water clearance",
      (RenalPhysiology.freeWaterClearance(flow: 10, urineOsm: 100, plasmaOsm: 290) ?? 0) > 0)
check("concentrated urine has negative free water clearance",
      (RenalPhysiology.freeWaterClearance(flow: 1, urineOsm: 900, plasmaOsm: 290) ?? 0) < 0)

// MARK: haemodynamics

check("MAP of 120/80 is 93", near(Haemodynamics.meanArterial(systolic: 120, diastolic: 80), 93.3, 0.1))
check("CO of 70 beats × 70 mL is 4.9 L/min", near(Haemodynamics.cardiacOutput(heartRate: 70, strokeVolume: 70), 4.9, 1e-9))
check("SVR about 1200", near(Haemodynamics.systemicResistance(map: 93, cvp: 5, cardiacOutput: 5.5), 1280, 1))
check("halving a radius cuts flow sixteenfold", near(Haemodynamics.poiseuilleFlowRatio(radiusRatio: 0.5), 1.0 / 16, 1e-12))
check("Fick: VO2 250, contents 20 and 15: 5 L/min", near(Haemodynamics.fickOutput(vo2: 250, arterialContent: 20, venousContent: 15), 5, 1e-9))
check("EF of 120/50 is 58%", near(Haemodynamics.ejectionFraction(edv: 120, esv: 50), 0.583, 0.001))

// MARK: cardiac cycle

let normal: CardiacCycle.Beat = CardiacCycle.beat()
check("normal EDV about 120 mL", normal.edv > 105 && normal.edv < 135, "\(normal.edv)")
check("normal ESV about 50 mL", normal.esv > 40 && normal.esv < 60, "\(normal.esv)")
check("normal EF 55 to 65%", normal.ejectionFraction > 0.55 && normal.ejectionFraction < 0.65, "\(normal.ejectionFraction)")
check("aortic pressure about 120/80", normal.aorticSystolic > 110 && normal.aorticSystolic < 135
      && normal.aorticDiastolic > 70 && normal.aorticDiastolic < 88, "\(normal.aorticSystolic)/\(normal.aorticDiastolic)")
check("LVEDP under 12 mmHg", normal.lvEndDiastolic > 3 && normal.lvEndDiastolic < 12, "\(normal.lvEndDiastolic)")
check("cardiac output about 5 L/min", normal.cardiacOutput > 4.5 && normal.cardiacOutput < 6.5, "\(normal.cardiacOutput)")
let e: [CardiacCycle.Event: Double] = normal.eventTimes
check("all four valve events happen", e.count == 4, "\(e)")
if let mc = e[.mitralCloses], let ao = e[.aorticOpens], let ac = e[.aorticCloses], let mo = e[.mitralOpens] {
    check("in order: mitral closes, aortic opens, aortic closes, mitral opens", mc <= ao && ao < ac && ac < mo)
    check("isovolumic contraction about 50 ms", ao - mc > 0.02 && ao - mc < 0.09, "\(ao - mc)")
    check("ejection about 0.27 s", ac - ao > 0.22 && ac - ao < 0.32, "\(ac - ao)")
    check("the phase names follow the events", CardiacCycle.phase(at: (ao + ac) / 2, in: normal) == "Ejection"
          && CardiacCycle.phase(at: (ac + mo) / 2, in: normal) == "Isovolumic relaxation")
}
check("no regurgitation through normal valves", normal.regurgitant < 1)
check("volume is conserved through the beat (stroke volume equals forward flow)",
      abs(normal.strokeVolume - normal.forwardStroke) < 2, "\(normal.strokeVolume) vs \(normal.forwardStroke)")

let preset: (CardiacCycle.Preset) -> CardiacCycle.Beat = { CardiacCycle.beat($0.parameters) }
let stenosis: CardiacCycle.Beat = preset(.aorticStenosis)
check("aortic stenosis makes a peak gradient over 40 mmHg", stenosis.peakAorticGradient > 40, "\(stenosis.peakAorticGradient)")
check("and the ventricle pushes well above the aorta", stenosis.lvSystolic > stenosis.aorticSystolic + 30)
check("a normal valve's peak gradient is under 20 mmHg", normal.peakAorticGradient < 20, "\(normal.peakAorticGradient)")
let ar: CardiacCycle.Beat = preset(.aorticRegurgitation)
check("aortic regurgitation widens the pulse pressure", ar.pulsePressure > normal.pulsePressure + 20, "\(ar.pulsePressure)")
check("with a low diastolic pressure", ar.aorticDiastolic < normal.aorticDiastolic - 15)
check("and a bigger ventricle", ar.edv > normal.edv + 15)
check("about half the stroke volume going back", ar.regurgitantFraction > 0.3, "\(ar.regurgitantFraction)")
let ms: CardiacCycle.Beat = preset(.mitralStenosis)
check("mitral stenosis makes a diastolic gradient over 5 mmHg", ms.meanMitralGradient > 5, "\(ms.meanMitralGradient)")
check("and raises left atrial pressure", ms.meanLA > normal.meanLA + 3)
check("and fills the ventricle less", ms.edv < normal.edv)
let mr: CardiacCycle.Beat = preset(.mitralRegurgitation)
check("mitral regurgitation raises the ejection fraction", mr.ejectionFraction > normal.ejectionFraction + 0.1)
check("while forward output falls", mr.cardiacOutput < normal.cardiacOutput - 0.5)
check("and a regurgitant fraction over 30%", mr.regurgitantFraction > 0.3)
let hfref: CardiacCycle.Beat = preset(.systolicFailure)
check("systolic failure: EF under 40%", hfref.ejectionFraction < 0.4, "\(hfref.ejectionFraction)")
check("with a dilated ventricle and a raised filling pressure", hfref.edv > 160 && hfref.lvEndDiastolic > normal.lvEndDiastolic + 3)
let hfpef: CardiacCycle.Beat = preset(.diastolicFailure)
check("a stiff ventricle keeps its EF", hfpef.ejectionFraction > 0.5)
check("but fills at a higher pressure", hfpef.lvEndDiastolic > normal.lvEndDiastolic + 5)
check("and holds less", hfpef.edv < normal.edv)
let htn: CardiacCycle.Beat = preset(.hypertension)
check("raised afterload raises the pressure", htn.aorticSystolic > normal.aorticSystolic + 20)
check("and lowers the stroke volume", htn.strokeVolume < normal.strokeVolume)
let bleed: CardiacCycle.Beat = preset(.haemorrhage)
check("blood loss lowers filling, stroke volume and pressure", bleed.edv < normal.edv - 10
      && bleed.strokeVolume < normal.strokeVolume && bleed.aorticSystolic < normal.aorticSystolic)
let exercise: CardiacCycle.Beat = preset(.exercise)
check("exercise raises the output by half or more", exercise.cardiacOutput > normal.cardiacOutput * 1.5, "\(exercise.cardiacOutput)")
check("every preset says what it changes", CardiacCycle.Preset.allCases.allSatisfy { !$0.change.isEmpty && !$0.name.isEmpty })
check("an open valve passes flow, a shut one only leaks",
      CardiacCycle.valveFlow(10, area: 3, leak: 0) > 0 && CardiacCycle.valveFlow(-10, area: 3, leak: 0) == 0
      && CardiacCycle.valveFlow(-10, area: 3, leak: 0.2) < 0)

// MARK: acid-base

func gas(_ pH: Double, _ co2: Double, _ hco3: Double, na: Double? = nil, cl: Double? = nil, alb: Double? = nil) -> AcidBase.Reading {
    AcidBase.read(AcidBase.Gas(pH: pH, paco2: co2, hco3: hco3, sodium: na, chloride: cl, albumin: alb))
}

let ok: AcidBase.Reading = gas(7.40, 40, 24, na: 140, cl: 104)
check("a normal gas reads normal", ok.isNormal && ok.consistent && ok.anionGap == 12, "\(ok.disorders)")
let dka: AcidBase.Reading = gas(7.15, 18, 6, na: 135, cl: 100)
check("DKA: raised-gap metabolic acidosis, compensated", dka.disorders == [.metabolicAcidosis] && dka.highGap, "\(dka.disorders)")
check("its anion gap is 29", dka.anionGap == 29)
check("its delta ratio is about 0.9 (pure raised gap)", near(dka.deltaRatio, 0.94, 0.05))
let copd: AcidBase.Reading = gas(7.34, 62, 32)
check("COPD: chronic respiratory acidosis", copd.disorders == [.respiratoryAcidosis] && copd.timing == "chronic",
      "\(copd.disorders) \(copd.timing ?? "-")")
let vomiting: AcidBase.Reading = gas(7.50, 45, 34)
check("vomiting: metabolic alkalosis, compensated", vomiting.disorders == [.metabolicAlkalosis], "\(vomiting.disorders)")
let panic: AcidBase.Reading = gas(7.55, 25, 21)
check("panic: acute respiratory alkalosis", panic.disorders == [.respiratoryAlkalosis] && panic.timing == "acute",
      "\(panic.disorders) \(panic.timing ?? "-")")
let salicylate: AcidBase.Reading = gas(7.43, 22, 14, na: 140, cl: 102)
check("salicylate: metabolic acidosis with respiratory alkalosis",
      Set(salicylate.disorders) == [.metabolicAcidosis, .respiratoryAlkalosis], "\(salicylate.disorders)")
let diarrhoea: AcidBase.Reading = gas(7.32, 30, 15, na: 140, cl: 115)
check("diarrhoea: normal-gap metabolic acidosis", diarrhoea.disorders == [.metabolicAcidosis] && !diarrhoea.highGap,
      "\(diarrhoea.disorders) \(diarrhoea.anionGap ?? -1)")
check("and the reading says hyperchloraemic", diarrhoea.steps.contains { $0.contains("hyperchloraemic") })
let tired: AcidBase.Reading = gas(7.25, 50, 21)
check("acidosis with a high PaCO2 and a low HCO3 is mixed", Set(tired.disorders) == [.respiratoryAcidosis, .metabolicAcidosis])
let poorlyCompensated: AcidBase.Reading = gas(7.20, 30, 11)
check("metabolic acidosis with PaCO2 above Winter's adds a respiratory acidosis",
      poorlyCompensated.disorders == [.metabolicAcidosis, .respiratoryAcidosis], "\(poorlyCompensated.disorders)")
let lowAlbumin: AcidBase.Reading = gas(7.30, 30, 15, na: 140, cl: 114, alb: 20)
check("albumin 20 g/L adds 5 to the gap", lowAlbumin.anionGap == 11 && lowAlbumin.correctedGap == 16 && lowAlbumin.highGap)
let wrong: AcidBase.Reading = gas(7.10, 40, 24)
check("numbers that do not belong together are flagged", !wrong.consistent && wrong.steps.first?.hasPrefix("Check") == true)
check("Henderson-Hasselbalch gives 7.40 for 24 and 40", near(AcidBase.predictedPH(hco3: 24, paco2: 40), 7.40, 0.005))

print(failures.isEmpty ? "all passed" : "\(failures.count) failed")
exit(failures.isEmpty ? 0 : 1)
