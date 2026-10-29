import Foundation

/// The recorder's state in a small shared file, `recorder-state.json`, next
/// to glance-digest.json in the App Group, so widgets, controls and the
/// watch can show it (T0146 item 1). Android keeps the same file, in the
/// same shape, in filesDir.
///
/// It holds the phase and its clock and nothing else: no lecture or set
/// name, so a lock-screen surface reading it has nothing private to show.
/// A missing, garbled or newer file reads as idle, never as a crash.
enum RecorderShelf {
    static let fileName = "recorder-state.json"
    static let currentVersion = 1
    /// The App Group's name, from Info.plist as GlanceShelf reads it.
    static let infoKey = "RedPenAppGroup"

    static var fileURL: URL? {
        let manager = FileManager.default
        #if canImport(Darwin)
        let group: String? = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String
        if let group, !group.isEmpty, !group.hasPrefix("$("),
           let shared = manager.containerURL(forSecurityApplicationGroupIdentifier: group) {
            return shared.appendingPathComponent(fileName)
        }
        #endif
        return manager.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent(fileName)
    }

    // MARK: the file's shape: {"v":1,"phase":"recording","startedAt":…,"banked":…,"reason":…}

    static func encode(_ state: RecorderState) -> Data {
        var object: [String: Any] = ["v": currentVersion, "phase": state.phase]
        switch state {
        case .recording(let startedAt, let banked):
            object["startedAt"] = startedAt
            object["banked"] = banked
        case .paused(let banked, let reason):
            object["banked"] = banked
            if let reason { object["reason"] = reason }
        case .failed(let reason):
            object["reason"] = reason
        default: break
        }
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }

    static func decode(_ data: Data) -> RecorderState {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let version = (object["v"] as? NSNumber)?.intValue, version <= currentVersion,
              let phase = object["phase"] as? String else { return .idle }
        let banked = (object["banked"] as? NSNumber)?.doubleValue
        let reason = object["reason"] as? String
        switch phase {
        case "asking": return .asking
        case "recording":
            guard let startedAt = (object["startedAt"] as? NSNumber)?.doubleValue, let banked else { return .idle }
            return .recording(startedAt: startedAt, banked: banked)
        case "paused":
            guard let banked else { return .idle }
            return .paused(banked: banked, reason: reason)
        case "saving": return .saving
        case "failed": return .failed(reason: reason ?? "")
        default: return .idle
        }
    }

    static func read(from url: URL? = fileURL) -> RecorderState {
        guard let url, let data = try? Data(contentsOf: url) else { return .idle }
        return decode(data)
    }

    @discardableResult
    static func write(_ state: RecorderState, to url: URL? = fileURL) -> Bool {
        guard let url else { return false }
        do {
            try encode(state).write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - A recording cut off by the app being killed

/// At launch, with nothing recording in this process, a shared file still
/// saying recording, paused or saving means a recording was left behind
/// (T0146 repair; Android RecorderRecovery). The newest `lecture-*` file in
/// the folder is offered to keep or discard, and the shared file goes back to
/// idle. The live .caf is readable up to its last packet, so it is offered
/// as it is.
enum RecorderRecovery {
    private static let open: Set<String> = ["recording", "paused", "saving"]
    private static let live: Set<String> = ["aac", "caf"]

    static func recover(shelf: URL?, folder: URL) -> URL? {
        let left = RecorderShelf.read(from: shelf)
        guard left != .idle else { return nil }
        RecorderShelf.write(.idle, to: shelf)
        guard open.contains(left.phase) else { return nil }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        guard let name = leftover(names) else { return nil }
        let url = folder.appendingPathComponent(name)
        let attributes = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        return size > 0 ? url : nil
    }

    /// The newest `lecture-…` stem, its live recording before a finished
    /// export of it.
    static func leftover(_ names: [String]) -> String? {
        let ours = names.filter { $0.hasPrefix("lecture-") && $0.contains(".") }
        func stem(_ name: String) -> String { (name as NSString).deletingPathExtension }
        guard let newest = ours.map(stem).max() else { return nil }
        let same = ours.filter { stem($0) == newest }.sorted()
        return same.first { live.contains(($0 as NSString).pathExtension) } ?? same.first
    }
}
