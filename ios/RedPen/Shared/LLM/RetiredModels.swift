import Foundation

/// The model files earlier builds downloaded to write on the phone: the
/// offline question writer and its vision projector (about 3.4 GB) under
/// Documents/Models, and the medical writers under Documents/Models/Medical.
/// Nothing writes on the phone any more (the owner, 23 Oct: "Lock it"), so
/// they are only taking space; the app removes them on launch. Nothing else
/// is kept under Documents/Models.
enum RetiredModels {
    static func directory(in documents: URL) -> URL {
        documents.appendingPathComponent("Models", isDirectory: true)
    }

    /// Removes the whole folder, finished downloads and half-finished ones.
    /// Returns whether anything was there.
    @discardableResult
    static func removeAll(in documents: URL? = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first) -> Bool {
        guard let documents else { return false }
        let folder = directory(in: documents)
        guard FileManager.default.fileExists(atPath: folder.path) else { return false }
        try? FileManager.default.removeItem(at: folder)
        return true
    }
}
