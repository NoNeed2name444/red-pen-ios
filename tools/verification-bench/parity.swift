// The app's copy of the sensors (AccuracyRules.swift) on every case the
// server's ran (sensors.mjs wrote cases.json): the hits must be the same,
// case by case, or the phone and the Worker disagree about an item.
//
// Built by tools/verification-bench/parity.sh with the accuracy suite's files.
import Foundation

struct Case: Decodable {
    struct Item: Decodable {
        var kind: String
        var stem: String?
        var options: [String]?
        var key: Int?
        var explanation: String?
        var text: String?
    }
    var id: String
    var item: Item
    var hits: [String]
}

let path: String = CommandLine.arguments.dropFirst().first ?? "cases.json"
let cases: [Case] = try JSONDecoder().decode([Case].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
var differ = 0
for c in cases {
    let kind: AccuracyKind = AccuracyKind(rawValue: c.item.kind) ?? .card
    let item = AccuracyItem(id: c.id, kind: kind, stem: c.item.stem ?? "", options: c.item.options ?? [],
                            key: c.item.key ?? -1, explanation: c.item.explanation ?? "", text: c.item.text ?? "")
    let mine: [String] = AccuracyRules.hits(item).map { $0.rule + ":" + $0.severity }
    if mine.sorted() != c.hits.sorted() {
        differ += 1
        if differ <= 15 { print("DIFFER \(c.id)\n  server: \(c.hits.sorted())\n  app:    \(mine.sorted())") }
    }
}
print("cases \(cases.count), the app agrees on \(cases.count - differ), differs on \(differ)")
exit(differ == 0 ? 0 : 1)
