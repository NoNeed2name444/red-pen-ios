import SwiftUI
import WidgetKit

// The widget extension (Xcode build only - see project.yml's
// StethoscoreWidgets target; the Playgrounds package never sees this folder).
//
// Every widget reads the one small digest the app writes into the App Group
// (GlanceDigest, compiled in from ios/RedPen/Shared/Platform). None opens the
// library or the schedule, none uses the network, and a tap only opens the
// app at the right place (AppLink).

@main
struct StethoscoreWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DueCardsWidget()
        ExamCountdownWidget()
        TodayStreakWidget()
        ReviewDueControl()
        ExamDayLiveActivity()
    }
}
