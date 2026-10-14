#if canImport(ActivityKit) && !SWIFT_PACKAGE
import ActivityKit
import Foundation

/// The exam-day Live Activity: from the evening before until the end of the
/// day (ExamDayWindow), on the Lock Screen and in the Dynamic Island.
///
/// Xcode build only (Live Activities need NSSupportsLiveActivities in
/// Info.plist and the widget extension to draw them). Compiled into the app,
/// which starts and ends it (ExamDayActivity), and the extension, which
/// draws it (StethoscoreWidgets/ExamDayLiveActivity.swift).
struct ExamDayAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Cards still due - the last look before the paper.
        var dueNow: Int
        /// When the paper starts, if the student gave a time; nil for a
        /// date with no time.
        var startsAt: Date?
    }

    var examName: String
    var examDay: Date
}
#endif
