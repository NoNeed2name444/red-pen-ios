import SwiftUI
import UIKit

// MARK: - A set in a window of its own (iPad)
//
// A lecture on one side and its questions on the other: the Xcode build
// declares UIApplicationSupportsMultipleScenes (project.yml), and a set can
// be opened in a second window - ⌘⇧N for the last set, or
// `SetWindow.openButton(for:)` in a set's menu. The Playgrounds build has no
// Info.plist to declare it in, so `supportsMultipleScenes` is false there and
// every way in is hidden.
//
// Two windows would draw two moving skies. Whichever window is not the key
// window draws a still one (stillWhenNotKey), so a second window costs
// almost nothing while the student works in the first.

enum SetWindow {
    /// The WindowGroup's id in RedPenApp.
    static let sceneID = "study-set"

    static var available: Bool { UIApplication.shared.supportsMultipleScenes }
}

/// "Open in New Window", for a set's context menu. Nothing on a phone or in
/// the Playgrounds build.
struct OpenInNewWindowButton: View {
    let setID: UUID
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if SetWindow.available {
            Button {
                openWindow(id: SetWindow.sceneID, value: setID)
            } label: {
                Label("Open in New Window", systemImage: "macwindow.badge.plus")
            }
        }
    }
}

/// The second window's content: the set, as the library would open it.
struct SetWindowRoot: View {
    let setID: UUID?
    @EnvironmentObject private var store: Store

    var body: some View {
        NavigationStack {
            if let set = store.library.first(where: { $0.id == setID }) {
                StudySetScreen(set: set)
                    .navigationTitle(set.name)
            } else {
                ContentUnavailableView("This set is no longer in your library",
                                       systemImage: "rectangle.stack.badge.minus")
            }
        }
        .stillWhenNotKey()
    }
}

// MARK: - A still sky in the window not being used

extension View {
    /// The sky holds still while another of the app's windows is the key
    /// window. With one window (every iPhone) nothing changes.
    func stillWhenNotKey() -> some View {
        modifier(StillWhenNotKey())
    }
}

private struct StillWhenNotKey: ViewModifier {
    @Environment(\.spaceQuality) private var inherited
    @State private var isKey = true

    func body(content: Content) -> some View {
        let level: SpaceQuality = isKey ? inherited : .still
        return content
            .environment(\.spaceQuality, level)
            .background(KeyWindowProbe(isKey: $isKey).allowsHitTesting(false))
    }
}

/// Tells whether the window it is in is the key window.
struct KeyWindowProbe: UIViewRepresentable {
    @Binding var isKey: Bool

    func makeUIView(context: Context) -> KeyWindowProbeView {
        let view = KeyWindowProbeView()
        view.isUserInteractionEnabled = false
        view.onChange = { key in
            if isKey != key { isKey = key }
        }
        return view
    }

    func updateUIView(_ view: KeyWindowProbeView, context: Context) {
        view.onChange = { key in
            if isKey != key { isKey = key }
        }
    }
}

final class KeyWindowProbeView: UIView {
    var onChange: ((Bool) -> Void)?
    private var observers: [NSObjectProtocol] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            UIWindow.didBecomeKeyNotification,
            UIWindow.didResignKeyNotification,
            UIScene.didActivateNotification,
            UIScene.willDeactivateNotification,
            UIScene.didDisconnectNotification,
        ]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.report() }
            }
            observers.append(token)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    deinit {
        for token in observers { NotificationCenter.default.removeObserver(token) }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        report()
    }

    /// Key, or the only window on screen.
    private func report() {
        guard let window else { return }
        let showing: Int = UIApplication.shared.connectedScenes.filter { scene in
            scene is UIWindowScene && (scene.activationState == .foregroundActive
                                       || scene.activationState == .foregroundInactive)
        }.count
        let key: Bool = showing <= 1 || window.isKeyWindow
        // never while SwiftUI is updating the view that holds the state
        DispatchQueue.main.async { [weak self] in self?.onChange?(key) }
    }
}
