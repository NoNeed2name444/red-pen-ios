import SwiftUI
#if canImport(LocalAuthentication) && !SWIFT_PACKAGE
import LocalAuthentication
#endif

// MARK: - Face ID app lock
//
// Case content reads like patient notes, so a student can lock the app:
// Settings > Privacy > "Lock with Face ID" (PlatformSettingsSection). While
// the app is in the app switcher a blurred glass shield covers it, and coming
// back asks for Face ID (or the passcode) before the shield lifts.
//
// Xcode build only: Face ID needs NSFaceIDUsageDescription in Info.plist,
// which the Playgrounds package has no way to declare, so there the toggle
// is hidden and the shield never appears.

enum AppLock {
    static let key = "platform.appLock"

    static var supported: Bool {
        #if canImport(LocalAuthentication) && !SWIFT_PACKAGE
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        #else
        return false
        #endif
    }

    static var isOn: Bool {
        supported && UserDefaults.standard.bool(forKey: key)
    }

    /// "Face ID", "Touch ID" or "Optic ID", for the toggle's label.
    static var biometryName: String {
        #if canImport(LocalAuthentication) && !SWIFT_PACKAGE
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "passcode"
        }
        #else
        return "Face ID"
        #endif
    }

    /// Asks once; true when the owner is confirmed.
    static func unlock(reason: String = "Unlock Stethoscore") async -> Bool {
        #if canImport(LocalAuthentication) && !SWIFT_PACKAGE
        let context = LAContext()
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
        #else
        return true
        #endif
    }
}

extension View {
    /// The shield over the app while it is locked (see AppLock).
    func appLockShield() -> some View {
        modifier(AppLockShield())
    }
}

/// Whether the app is locked, shared by every window: unlocking one unlocks
/// them all, and opening a second window does not ask again.
@MainActor
private final class AppLockState: ObservableObject {
    static let shared = AppLockState()
    /// Locked until the owner is confirmed; a cold launch starts locked.
    @Published var locked = true
    @Published var asking = false

    func unlock() async {
        guard locked, !asking else { return }
        asking = true
        let ok: Bool = await AppLock.unlock()
        asking = false
        if ok {
            withAnimation(.easeOut(duration: 0.2)) { locked = false }
        }
    }
}

private struct AppLockShield: ViewModifier {
    @Environment(\.scenePhase) private var phase
    @AppStorage(AppLock.key) private var lockOn = false
    @ObservedObject private var state = AppLockState.shared
    /// This window is in the app switcher (or otherwise not active).
    @State private var covered = false

    private var enabled: Bool { lockOn && AppLock.supported }
    private var locked: Bool { state.locked }
    private var asking: Bool { state.asking }

    func body(content: Content) -> some View {
        content
            .overlay {
                if enabled && (covered || locked) {
                    shield
                        .transition(.opacity)
                }
            }
            .onAppear {
                if enabled && locked { Task { await unlock() } }
            }
            .onChange(of: lockOn) { _, on in
                // turning the lock on in Settings does not lock the app at once
                if on { state.locked = false }
            }
            .onChange(of: phase) { _, now in
                guard enabled else {
                    covered = false
                    return
                }
                switch now {
                case .inactive:
                    covered = true
                case .background:
                    covered = true
                    state.locked = true
                case .active:
                    covered = false
                    if locked { Task { await unlock() } }
                @unknown default:
                    break
                }
            }
    }

    private var shield: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .scaledFont(34, relativeTo: .largeTitle, weight: .semibold, maxSize: 44)
                    .frame(width: 72, height: 72)
                    .liquidGlassChip()
                Text("Stethoscore is locked")
                    .font(.headline)
                if locked && !covered {
                    Button("Unlock") { Task { await unlock() } }
                        .buttonStyle(.glassProminent)
                        .disabled(asking)
                        .accessibilityIdentifier("appLockUnlock")
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
    }

    private func unlock() async {
        await state.unlock()
    }
}
