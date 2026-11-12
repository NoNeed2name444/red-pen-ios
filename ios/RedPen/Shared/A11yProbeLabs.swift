import Foundation

/// Diagnostic only (T0241): picks the accessibility shape of the chart quiz's
/// lab table (ChartLabsTable), so one UI test can audit the same screen once per
/// shape and print what each one leaves flagged. `-a11yProbeLabs <name>` on the
/// command line picks the shape; A11yLabsProbeUITests passes it, once per shape.
/// No other test and no production path passes it.
///
/// Without the argument (every normal launch) `variant` is nil and
/// ChartLabsTable draws the shape it has always had (V0, below). The name
/// `V0-present` is not a case: it is that shape, so the test's baseline launch
/// is made the same way as the others and the app takes no variant from it. A
/// name the app does not know also gives nil, so the test reads each variant's
/// `nodes` against the baseline's: a name that changed nothing shows at once.
///
/// The shapes (V1 to V8 change only accessibility modifiers, the child
/// structure of the table or the weight of its font; no word, colour or space):
/// - V0 `V0-present`: the table as one element, `.ignore` and the results'
///   ChartQuiz.spoken joined by ". " (T0223).
/// - V1 `V1-name-cell`: the shape before T0223: the name cell carries the
///   result's spoken words, the other cells are hidden (a grid row), the
///   stacked result is one `.ignore` element with that label.
/// - V2 `V2-combine-table`: `.combine` on the whole table, no label override.
/// - V3 `V3-combine-rows`: `.combine` and the spoken label on each result
///   (on the GridRow in the wide layout, on the stack in the stacked one).
/// - V4 `V4-grid-only`: V0 with the grid alone, no ViewThatFits.
/// - V5 `V5-stack-only`: V0 with the stacked layout alone, no ViewThatFits.
/// - V6 `V6-single-text`: one Text per result, built from its words, no child
///   nodes and no label override.
/// - V7 `V7-static-text-trait`: V0 and `.isStaticText` on the table's element.
/// - V8 `V8-font-no-weight`: V0 with the table's font set without the
///   `.regular` weight modifier (`WardType.mono` adds one).
enum A11yProbeLabs {
    enum Variant: String {
        case nameCell = "V1-name-cell"
        case combineTable = "V2-combine-table"
        case combineRows = "V3-combine-rows"
        case gridOnly = "V4-grid-only"
        case stackOnly = "V5-stack-only"
        case singleText = "V6-single-text"
        case staticTextTrait = "V7-static-text-trait"
        case fontNoWeight = "V8-font-no-weight"
    }

    /// The shape named on the command line, or nil for a normal launch (and
    /// for V0, and for a name that is not one). Read once, into a static let,
    /// as A11yProbeHide reads its argument.
    static let variant: Variant? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-a11yProbeLabs"), i + 1 < args.count else { return nil }
        return Variant(rawValue: args[i + 1])
    }()
}
