import Foundation

/// The library's side of syncing.
///
/// Kept apart from Store itself because these are the only methods that write
/// to the library WITHOUT stamping it as a local edit. Mixing them in with the
/// ordinary mutators is how somebody eventually calls the wrong one and has two
/// devices bouncing the same document back and forth for ever.
extension Store {

    // MARK: what sync needs

    /// Puts a set in place exactly as it arrived from another device, keeping
    /// the timestamp that device gave it. Going through `update` instead would
    /// re-stamp it with this device's clock and make the incoming edit look
    /// newer than it is - which is how two devices end up bouncing a document
    /// back and forth for ever.
    func applyFromSync(_ set: StudySet) {
        tombstones[set.id] = nil
        if let idx = library.firstIndex(where: { $0.id == set.id }) {
            library[idx] = set
        } else {
            library.append(set)
        }
        save()
    }

    func applyFromSync(_ folder: StudyFolder) {
        tombstones[folder.id] = nil
        if let idx = folders.firstIndex(where: { $0.id == folder.id }) {
            folders[idx] = folder
        } else {
            folders.append(folder)
        }
        save()
    }

    /// A deletion that happened on another device. Not recorded as a tombstone
    /// of ours: we did not delete it, and the device that did is already
    /// telling everybody.
    func removeFromSync(_ id: UUID) {
        library.removeAll { $0.id == id }
        folders.removeAll { $0.id == id }
        quizProgress[id] = nil
        save()
    }

    /// A conflicting copy kept so that nothing is lost when two devices edited
    /// the same set. It is a NEW set with a new id, which is what makes it
    /// visible in the library rather than silently merged away.
    @discardableResult
    func keepConflictCopy(of set: StudySet, from device: String) -> StudySet {
        var copy = set
        copy.id = UUID()
        copy.name = set.name + " (from " + device + ")"
        copy.updatedAt = Date()
        library.append(copy)
        save()
        return copy
    }

    /// Forgets tombstones every device has already seen, so the list does not
    /// grow for the life of the account.
    func forgetTombstones(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        for id in ids { tombstones[id] = nil }
        save()
    }
}
