import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Diagnostic only (T0263): names the collection views the app has while it is
/// being audited. SwiftUI's List is a UICollectionView, and the app has
/// stopped in 2 of 3 Mac runs during the revealed card's accessibility audit,
/// in an assertion under `-[UICollectionView _setNeedsVisibleCellsUpdate:
/// withLayoutAttributes:]`, with no RedPen frame in the stack. Which List that
/// is has never been shown. With `-a11yProbeLists` on the command line the
/// app writes one snapshot of its collection views to `path`, every quarter
/// second, for a UI test to read and print (AccessibilityUITests'
/// testDefaultSizeAuditProbeDiagnostic, on the revealed card). No other test
/// and no production path passes the argument.
///
/// Without the argument (every normal launch) `isOn` is false, `start()`
/// returns at once, and nothing else here ever runs: no timer, no file, no
/// view, no accessibility element.
///
/// The file is replaced whole each tick (written under a temporary name and
/// renamed), so a reader never sees half of one. A simulator process shares
/// the host's /tmp, so the test process reads what the app wrote. Its first
/// line is
///   `t=<seconds since start, 2 decimals> windows=<n> lists=<n>`
/// and then one line per collection view, depth first through every window of
/// every connected scene, up to 40 lists and 4000 views:
///   `L<k> <ClassName> id=<last 6 hex digits of the address> vc=<nearest view
///   controller class up the responder chain, or none> win=<window index>
///   frame=<x,y,w,h in the window> hidden=<0|1> alpha=<0.00>
///   size=<contentSize w,h> offset=<contentOffset x,y> visible=<visible cell
///   count> up=<nearest three superview classes, joined with ">">`
/// All the numbers but alpha are whole. If a cap stopped the walk, a last line
/// `CAP views=<n> lists=<n>` says so.
///
/// It only reads. It never asks a collection view for its sections or items
/// (that reads the data source and could trip the same assertion), adds no
/// view and no accessibility element, and keeps no reference to a view or a
/// window between ticks: each tick walks the live hierarchy and lets go.
///
/// The formatting is Foundation-only; the walk and the timer are fenced to
/// UIKit.
enum A11yProbeLists {
    /// Whether the launch asked for it. Read once, into a static let, as
    /// A11yProbeHide reads its arguments.
    static let isOn: Bool = ProcessInfo.processInfo.arguments.contains("-a11yProbeLists")

    /// Where the snapshot goes. AccessibilityUITests reads the same path.
    static let path = "/tmp/redpen-probe-lists.txt"

    /// The seconds between two snapshots.
    static let interval: TimeInterval = 0.25
    /// The most collection views one snapshot names, and the most views it
    /// looks at to find them.
    static let maxLists = 40
    static let maxViews = 4000

    /// Starts the snapshots, when the launch asked for them. Called once, from
    /// the app's init.
    static func start() {
        guard isOn else { return }
        #if canImport(UIKit)
        let begun = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { A11yProbeLists.tick(since: begun) }
        }
        // common modes: it keeps ticking while a list is being scrolled
        RunLoop.main.add(timer, forMode: .common)
        #endif
    }

    // MARK: - The text (Foundation only)

    /// `t=<seconds, 2 decimals> windows=<n> lists=<n>`.
    static func header(seconds: Double, windows: Int, lists: Int) -> String {
        "t=\(String(format: "%.2f", seconds)) windows=\(windows) lists=\(lists)"
    }

    /// One collection view's line (see the type's comment for what is in it).
    static func line(number: Int, className: String, address: UInt, controller: String,
                     window: Int, frame: (x: Double, y: Double, w: Double, h: Double),
                     hidden: Bool, alpha: Double, size: (w: Double, h: Double),
                     offset: (x: Double, y: Double), visible: Int, above: String) -> String {
        var text = "L\(number) \(className) id=\(shortID(address)) vc=\(controller) win=\(window)"
        text += " frame=\(whole(frame.x)),\(whole(frame.y)),\(whole(frame.w)),\(whole(frame.h))"
        text += " hidden=\(hidden ? 1 : 0) alpha=\(String(format: "%.2f", alpha))"
        text += " size=\(whole(size.w)),\(whole(size.h))"
        text += " offset=\(whole(offset.x)),\(whole(offset.y))"
        text += " visible=\(visible) up=\(above)"
        return text
    }

    /// The last six hex digits of an address, so two lines name the same view
    /// when their ids match.
    static func shortID(_ address: UInt) -> String {
        let digits = String(address & 0xFF_FFFF, radix: 16)
        return String(repeating: "0", count: max(0, 6 - digits.count)) + digits
    }

    /// A number as a whole one. A number that is not finite (a broken layout
    /// can give one) must not stop the app, so it reads as -999999999, and a
    /// huge one is held to a billion.
    static func whole(_ value: Double) -> Int {
        guard value.isFinite else { return -999_999_999 }
        return Int(max(-999_999_999, min(999_999_999, value.rounded())))
    }

    // MARK: - The walk (UIKit)

    #if canImport(UIKit)
    /// What one walk has counted and written so far.
    private struct Walk {
        var visited = 0
        var lists = 0
        var windowIndex = 0
        var capped = false
        var body = ""
    }

    /// One snapshot, written over the last. Anything that fails is ignored.
    @MainActor
    private static func tick(since begun: TimeInterval) {
        var walk = Walk()
        var windows = 0
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                walk.windowIndex = windows
                windows += 1
                visit(window, in: window, walk: &walk)
            }
        }
        var text = header(seconds: ProcessInfo.processInfo.systemUptime - begun,
                          windows: windows, lists: walk.lists) + "\n" + walk.body
        if walk.capped { text += "CAP views=\(walk.visited) lists=\(walk.lists)\n" }
        try? text.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// `view` and everything under it, depth first, a line for each collection
    /// view. Stops at once when a cap is reached.
    @MainActor
    private static func visit(_ view: UIView, in window: UIWindow, walk: inout Walk) {
        if walk.capped { return }
        if walk.visited >= maxViews {
            walk.capped = true
            return
        }
        walk.visited += 1
        if let list = view as? UICollectionView {
            if walk.lists >= maxLists {
                walk.capped = true
                return
            }
            walk.lists += 1
            walk.body += describe(list, number: walk.lists, in: window, windowIndex: walk.windowIndex) + "\n"
        }
        for child in view.subviews { visit(child, in: window, walk: &walk) }
    }

    @MainActor
    private static func describe(_ list: UICollectionView, number: Int, in window: UIWindow,
                                 windowIndex: Int) -> String {
        let frame = list.convert(list.bounds, to: window)
        return line(number: number,
                    className: String(describing: type(of: list)),
                    address: UInt(bitPattern: ObjectIdentifier(list)),
                    controller: controllerName(of: list),
                    window: windowIndex,
                    frame: (Double(frame.origin.x), Double(frame.origin.y),
                            Double(frame.size.width), Double(frame.size.height)),
                    hidden: list.isHidden,
                    alpha: Double(list.alpha),
                    size: (Double(list.contentSize.width), Double(list.contentSize.height)),
                    offset: (Double(list.contentOffset.x), Double(list.contentOffset.y)),
                    visible: list.visibleCells.count,
                    above: superviews(of: list))
    }

    /// The class of the nearest view controller up the responder chain.
    @MainActor
    private static func controllerName(of view: UIView) -> String {
        var next: UIResponder? = view.next
        while let responder = next {
            if responder is UIViewController { return String(describing: type(of: responder)) }
            next = responder.next
        }
        return "none"
    }

    /// The classes of the nearest three superviews, nearest first.
    @MainActor
    private static func superviews(of view: UIView) -> String {
        var names: [String] = []
        var up = view.superview
        while let above = up, names.count < 3 {
            names.append(String(describing: type(of: above)))
            up = above.superview
        }
        return names.isEmpty ? "none" : names.joined(separator: ">")
    }
    #endif
}
