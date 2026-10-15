import XCTest

extension XCUIApplication {
    /// Keeps XCTest's own trace of each query out of the app's console.
    /// Every UI test calls it before launch().
    ///
    /// xcodebuild starts the app with stdout and stderr on a terminal that
    /// only it drains, and XCTest evaluates each query inside the app, on its
    /// main thread, logging a line there for every accessibility lookup. When
    /// xcodebuild falls behind, the terminal fills and the main thread waits
    /// on each line. On 15 Oct (App build 38684974986) the design tour wrote
    /// 52 MB of trace, its query on Ideas > Space outlasted its 30 s three
    /// times, and the next two tests could neither end nor launch the app
    /// until xcodebuild caught up. With os_log off (OS_ACTIVITY_MODE) and not
    /// copied to stderr (OS_ACTIVITY_DT_MODE), the trace never reaches the
    /// terminal; what the app prints itself still does.
    func keepTraceOffConsole() {
        launchEnvironment["OS_ACTIVITY_MODE"] = "disable"
        launchEnvironment["OS_ACTIVITY_DT_MODE"] = "NO"
    }
}
