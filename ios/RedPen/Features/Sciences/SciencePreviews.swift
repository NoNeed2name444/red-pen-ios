import SwiftUI

/// The Sciences as the screenshots open them (`-uiPreviewScreen science-<name>`,
/// through PreviewExtras): straight onto a page, with nothing to tap first.
/// SciencesUITests photographs each on an iPhone and an iPad.
struct SciencePreviewScreen: View {
    let name: String

    static let names: [String] = [
        "science-hub", "science-subject", "science-system", "science-topic",
        "science-cardiac", "science-action", "science-oxygen", "science-acidbase",
        "science-enzyme", "science-punnett", "science-microbes", "science-shock",
        "science-tests", "science-atlas", "science-atlas-heart", "science-atlas-female",
        "science-atlas-skull", "science-atlas-pelvis", "science-atlas-hip",
    ]

    var body: some View {
        NavigationStack {
            page
        }
    }

    @ViewBuilder
    private var page: some View {
        switch name {
        case "science-subject": ScienceSubjectView(subject: .physiology)
        case "science-system": BodySystemView(system: .cardiovascular)
        case "science-topic":
            if let topic = ScienceCatalog.topic("phys-cardiac-cycle") { ScienceTopicView(topic: topic) }
        case "science-cardiac": CardiacCycleTool()
        case "science-action": ActionPotentialTool()
        case "science-oxygen": OxygenCurveTool()
        case "science-acidbase": AcidBaseTool()
        case "science-enzyme": EnzymeKineticsTool()
        case "science-punnett": PunnettTool()
        case "science-microbes": MicrobesTool()
        case "science-shock": ShockTool()
        case "science-tests": DiagnosticTestsTool()
        case "science-atlas": AnatomyAtlasView()
        case "science-atlas-heart":
            AnatomyAtlasView(focus: ["heart", "vessels"], title: "The heart", choosing: "heart/VH_M_heart_left_ventricle")
        case "science-atlas-female":
            AnatomyAtlasView(focus: ["uterus", "ovaries", "uterine-tubes", "vagina", "uterine-ligaments"],
                             title: "The female pelvic organs", choosing: "uterus/VH_F_body_of_uterus")
        // close up, for the bone's and the muscle's surfaces
        case "science-atlas-skull": AnatomyAtlasView(focus: ["skull"], title: "The skull")
        case "science-atlas-pelvis": AnatomyAtlasView(focus: ["pelvis"], title: "The pelvis")
        case "science-atlas-hip": AnatomyAtlasView(focus: ["hip-muscles", "pelvis"], title: "The hip muscles")
        default: SciencesView()
        }
    }
}
