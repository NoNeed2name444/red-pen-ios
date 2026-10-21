import Foundation

/// The two things the library store needs to know about a file that a plain
/// `try?` hides: whether a file that could not be read is there at all, and
/// whether a write landed.
///
/// A launch before the first unlock after a restart (iOS prewarms the app)
/// finds the library file still protected: it exists, and cannot be read. A
/// read that fails for that reason must not look like an empty library, or
/// the next save writes an empty library over the real one. And a write that
/// fails (the disk is full, the file is protected) must not look like a save,
/// or sync records the change as safely here and moves on.
enum StoreFiles {
    enum Read {
        /// The file's bytes.
        case data(Data)
        /// Nothing at that path: a fresh install, or a file never written.
        case missing
        /// The file is there and could not be read.
        case unreadable(Error)
    }

    static func read(_ url: URL) -> Read {
        do {
            return .data(try Data(contentsOf: url))
        } catch {
            return isPresent(url) ? .unreadable(error) : .missing
        }
    }

    /// Whether something is at the path, whether or not it can be read.
    static func isPresent(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Writes the bytes atomically; the error when they did not land.
    static func write(_ data: Data, to url: URL) -> Error? {
        do {
            try data.write(to: url, options: .atomic)
            return nil
        } catch {
            return error
        }
    }
}
