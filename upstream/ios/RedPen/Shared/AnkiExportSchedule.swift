import Foundation

/// A card's schedule as a row of Anki's `cards` table, so an exported deck
/// keeps where each card stood (audit #21: every card went out new, with no
/// interval, and a student moving a reviewed deck to Anki started again).
struct AnkiScheduleRow: Equatable {
    /// 0 new, 2 review.
    var type: Int
    /// 0 new, 2 review, -1 suspended.
    var queue: Int
    /// A new card's place in line; a review card's day, counted from the
    /// exported collection's first day.
    var due: Int
    /// Days.
    var interval: Int
    /// Ease in thousandths: 2500 is Anki's starting 2.5x.
    var factor: Int
    var reps: Int
    var lapses: Int

    /// No record, or one never rated: a new card at `position`. Otherwise a
    /// review card due on the day it is due here, counted from `dayZero` (the
    /// collection's creation). A card still in its learning steps (under a
    /// day) goes as a review card with a one-day interval: Anki's steps
    /// cannot be written without its own step state, and a review card keeps
    /// the history a reset would throw away.
    static func of(_ record: ReviewRecord?, position: Int, dayZero: Date) -> AnkiScheduleRow {
        let suspended: Bool = record?.suspended == true
        guard let record, record.reviews > 0 || record.intervalMin >= 1_440 else {
            return AnkiScheduleRow(type: 0, queue: suspended ? -1 : 0, due: position,
                                   interval: 0, factor: 0, reps: 0, lapses: 0)
        }
        let days: Int = Int((record.due.timeIntervalSince(dayZero) / 86_400).rounded(.down))
        let interval: Int = max(1, Int((record.intervalMin / 1_440).rounded()))
        return AnkiScheduleRow(type: 2, queue: suspended ? -1 : 2, due: days, interval: interval,
                               factor: 2_500, reps: max(record.reviews, 0), lapses: max(record.lapses, 0))
    }
}

/// A picture as an Anki media file: the name it goes by (one per set and
/// picture, so cards sharing a picture share the file) and its type, read
/// from its first bytes.
enum AnkiExportPicture {
    static func fileName(set: UUID, index: Int, data: Data) -> String {
        "pic_\(set.uuidString.prefix(8))_\(index).\(fileExtension(data))"
    }

    static func fileExtension(_ data: Data) -> String {
        let head: [UInt8] = Array(data.prefix(12))
        if head.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if head.starts(with: [0x47, 0x49, 0x46, 0x38]) { return "gif" }
        if head.count >= 12, head.starts(with: [0x52, 0x49, 0x46, 0x46]),
           Array(head[8..<12]) == [0x57, 0x45, 0x42, 0x50] { return "webp" }
        return "jpg"
    }

    /// The note's fields with the picture put on its side: before the
    /// question on the front, or at the top of the answer.
    static func fields(_ fields: [String], picture: String, onBack: Bool) -> [String] {
        guard !fields.isEmpty else { return fields }
        var out = fields
        let tag: String = "<img src=\"\(picture)\">"
        if onBack && out.count > 1 { out[out.count - 1] = tag + out[out.count - 1] } else { out[0] = tag + out[0] }
        return out
    }
}
