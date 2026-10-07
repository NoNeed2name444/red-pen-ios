import Foundation

/// Decoded pictures, kept between redraws.
///
/// A set holds its pictures as base64 text. Turning one back into an image
/// on every SwiftUI body pass meant decoding megabytes each time an
/// occlusion card's covers moved (audit #67). This keeps what it decoded:
/// the same text gives back the same picture without decoding again.
///
/// The key is a cheap fingerprint (length and the two ends), and a hit is
/// confirmed against the full text. That check costs almost nothing while
/// the set is unchanged, since both strings share one buffer.
final class PictureCache<Picture: AnyObject>: @unchecked Sendable {
    private final class Entry {
        let stored: String
        let picture: Picture
        init(stored: String, picture: Picture) { self.stored = stored; self.picture = picture }
    }

    private let cache = NSCache<NSString, Entry>()

    init(limit: Int = 24) { cache.countLimit = limit }

    /// The picture for a stored image (bare base64 or a data: URI), decoded
    /// once. `make` turns the bytes into a picture; nil when either fails.
    func picture(for stored: String, make: (Data) -> Picture?) -> Picture? {
        let key = Self.fingerprint(stored) as NSString
        if let hit = cache.object(forKey: key), hit.stored == stored { return hit.picture }
        guard let data = Data(base64Encoded: Self.payload(stored), options: .ignoreUnknownCharacters),
              let picture = make(data) else { return nil }
        cache.setObject(Entry(stored: stored, picture: picture), forKey: key)
        return picture
    }

    static func fingerprint(_ stored: String) -> String {
        let utf8 = stored.utf8
        return "\(utf8.count):" + String(decoding: utf8.prefix(48), as: UTF8.self)
            + "|" + String(decoding: utf8.suffix(48), as: UTF8.self)
    }

    /// The base64 itself, with any `data:...;base64,` prefix taken off.
    static func payload(_ stored: String) -> String {
        guard stored.hasPrefix("data:"), let comma = stored.firstIndex(of: ",") else { return stored }
        return String(stored[stored.index(after: comma)...])
    }
}
