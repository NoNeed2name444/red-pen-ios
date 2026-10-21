import SwiftUI

/// Study Lens's answer sheet for the "lens" preview screen: a sample
/// multiple-choice question, already answered, so the Ward preview can show
/// how its option rows are marked (the right one in the mode's colour, the
/// others faded, by the owner's rule of 15 Oct) with the explanation under
/// them.
///
/// The answer is put straight into the model, so nothing reads the camera,
/// asks for an answer or waits, and the picture is the same on every run.
/// The sheet is drawn at full height rather than over the live view, where
/// its first stop would hide the explanation.
struct LensSheetPreview: View {
    @StateObject private var model: LensModel

    private let question: DetectedQuestion

    init() {
        let question: DetectedQuestion = Self.question
        let model = LensModel(smooth: true)
        model.setPreviewAnswer(Self.answer, for: question)
        self.question = question
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        LensAnswerSheet(question: question, model: model)
    }

    // MARK: the sample

    private static let optionTexts: [String] = [
        "Effacement of podocyte foot processes",
        "Subepithelial immune deposits with basement membrane spikes",
        "Mesangial IgA deposits",
        "Splitting and lamination of the glomerular basement membrane",
        "Subendothelial deposits with a tram-track basement membrane",
    ]

    static var question: DetectedQuestion {
        let stem: String = "Sample question. A 6-year-old boy has periorbital oedema and heavy proteinuria "
            + "a week after a cold. His blood pressure and complement levels are normal. "
            + "What is electron microscopy of a renal biopsy most likely to show?"
        let options: [LensOption] = optionTexts.enumerated().map { pair in
            LensOption(marker: LensHash.letter(pair.offset), text: pair.element)
        }
        return DetectedQuestion(type: .mcq, number: "12", stem: stem, options: options,
                                box: CGRect(x: 0.1, y: 0.2, width: 0.8, height: 0.5),
                                key: LensHash.key(stem: stem, options: optionTexts))
    }

    static let answer = LensAnswer(
        type: .mcq,
        correctIndex: 0,
        answer: optionTexts[0],
        explanation: "Nephrotic syndrome in a young child with normal blood pressure and complement is "
            + "minimal change disease until shown otherwise. Light microscopy looks normal; electron "
            + "microscopy shows the podocyte foot processes effaced.",
        optionNotes: [
            "Minimal change disease: foot process effacement is its only finding.",
            "Membranous nephropathy, a cause of nephrotic syndrome in adults.",
            "IgA nephropathy, which presents with haematuria days after an infection.",
            "Alport syndrome, with haematuria and hearing loss.",
            "Membranoproliferative disease, which lowers complement.",
        ],
        keyPoints: [
            "Most nephrotic children respond to steroids, so biopsy is kept for those who do not.",
            "Normal complement points away from post-infectious and membranoproliferative disease.",
        ]
    )
}
