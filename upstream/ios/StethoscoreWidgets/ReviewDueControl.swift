import AppIntents
import SwiftUI
import WidgetKit

/// Control Centre, the Lock Screen's controls and the Action button:
/// "Review due" opens the app on every card due today.
struct ReviewDueControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "stethoscore.control.reviewDue") {
            ControlWidgetButton(action: ReviewDueIntent()) {
                Label("Review due", systemImage: "rectangle.stack.badge.play")
            }
        }
        .displayName("Review due cards")
        .description("Opens Stethoscore on the cards due today.")
    }
}
