// The layered app icon (tools/icon_layers.py): every layer's SVG parses, the
// layers stack back to front in IconLayer's order, AppIcon.icon's icon.json is
// valid and names every asset it ships, and the SwiftUI drawing has every layer.
// Run from the repository root (tools/swift_suites.py does).

import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

var failures = 0
func ok(_ condition: Bool, _ what: String) {
    print((condition ? "ok   " : "FAIL ") + what)
    if !condition { failures += 1 }
}

let fm = FileManager.default
let layersDir = "design/icon/layers"
let bundle = "ios/AppResources/AppIcon.icon"

/// The root element's name and attributes, or nil if the file is not XML.
final class Root: NSObject, XMLParserDelegate {
    var name: String?, attributes: [String: String] = [:], elements = 0
    func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?,
                attributes a: [String: String]) {
        if name == nil { name = e; attributes = a }
        elements += 1
    }
}
func parseSVG(_ path: String) -> Root? {
    guard let data = fm.contents(atPath: path) else { return nil }
    let parser = XMLParser(data: data), root = Root()
    parser.delegate = root
    return parser.parse() ? root : nil
}

// MARK: the SVGs

let svgs = ((try? fm.contentsOfDirectory(atPath: layersDir)) ?? []).filter { $0.hasSuffix(".svg") }.sorted()
ok(svgs == IconLayer.allCases.map(\.asset), "design/icon/layers holds one SVG per layer, numbered back to front: \(svgs)")
for layer in IconLayer.allCases {
    let root = parseSVG("\(layersDir)/\(layer.asset)")
    ok(root?.name == "svg", "\(layer.asset) parses and is an <svg>")
    ok(root?.attributes["viewBox"] == "0 0 1024 1024", "\(layer.asset) is on the 1024-point canvas")
    ok(root?.attributes["id"] == layer.rawValue, "\(layer.asset) is the \(layer.rawValue) layer")
    ok((root?.elements ?? 0) > 1, "\(layer.asset) draws something")
}

// MARK: AppIcon.icon

let json = fm.contents(atPath: "\(bundle)/icon.json")
let icon = json.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
ok(icon != nil, "icon.json is a JSON object")
let groups = (icon?["groups"] as? [[String: Any]]) ?? []
ok(groups.count <= 4, "at most four groups, as Icon Composer asks (\(groups.count))")
ok(icon?["fill"] is [String: Any], "the background tile is the icon's fill")

// Icon Composer lists groups, and the layers in each, front first.
var backToFront: [(group: String, name: String, image: String)] = []
for g in groups.reversed() {
    for l in ((g["layers"] as? [[String: Any]]) ?? []).reversed() {
        backToFront.append((g["name"] as? String ?? "", l["name"] as? String ?? "", l["image-name"] as? String ?? ""))
    }
}
let artwork = IconLayer.allCases.filter { $0.group != nil }
ok(backToFront.map(\.name) == artwork.map(\.rawValue), "the layers stack back to front: \(backToFront.map(\.name))")
ok(backToFront.map(\.image) == artwork.map(\.asset), "each layer names its own SVG")
ok(backToFront.map(\.group) == artwork.map { $0.group! }, "each layer sits in its group")

let assets = ((try? fm.contentsOfDirectory(atPath: "\(bundle)/Assets")) ?? []).sorted()
ok(assets == backToFront.map(\.image).sorted(), "icon.json names every asset in Assets, and no other: \(assets)")
for a in assets {
    ok(parseSVG("\(bundle)/Assets/\(a)")?.name == "svg", "Assets/\(a) parses")
    ok(fm.contents(atPath: "\(bundle)/Assets/\(a)") == fm.contents(atPath: "\(layersDir)/\(a)"),
       "Assets/\(a) is design/icon/layers/\(a)")
}

// MARK: the SwiftUI drawing

let swift = (fm.contents(atPath: "ios/RedPen/Shared/Brand/IconLayers.swift")).flatMap { String(data: $0, encoding: .utf8) } ?? ""
for layer in IconLayer.allCases {
    let name = "\(layer)"
    ok(swift.contains("case .\(name):"), "IconLayers.swift draws \(name)")
}

print(failures == 0 ? "all icon layer checks passed" : "\(failures) failed")
exit(failures == 0 ? 0 : 1)
