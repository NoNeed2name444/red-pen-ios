import Foundation

/// When coming back to the app asks for Face ID by itself (AppLock).
///
/// Face ID's own sheet makes the app inactive and then active again, so
/// asking on every return asked again the moment the student cancelled,
/// and again, with no way to stop it (audit #8). After a cancel only the
/// Unlock button asks, until the app has been away properly.
enum AppLockRule {
    static func asksOnReturn(locked: Bool, cancelled: Bool) -> Bool {
        locked && !cancelled
    }
}
