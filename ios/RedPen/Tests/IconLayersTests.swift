// The layered app icon (tools/icon_layers.py): every layer is a 1024 x 1024
// PNG with alpha, the layers stack back to front in IconLayer's order and
// groups, AppIcon.icon's icon.json is valid and names every asset it ships,
// and the in-app view shows the same PNGs. Run from the repository root
// (tools/swift_suites.py does).

import Foundation

var failures = 0
func ok(_ condition: Bool, _ what: String) {
    print((condition ? "ok   " : "FAIL ") + what)
    if !condition { failures += 1 }
}

let fm = FileManager.default
let layersDir = "design/icon/layers"
let bundle = "ios/AppResources/AppIcon.icon"

/// A PNG's width, height, bit depth and colour type, read from its IHDR.
func pngHeader(_ path: String) -> (width: Int, height: Int, depth: Int, colour: Int)? {
    guard let d = fm.contents(atPath: path).map(Array.init), d.count > 33,
          d[0..<8] == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
          String(bytes: d[12..<16], encoding: .ascii) == "IHDR" else { return nil }
    func be(_ i: Int) -> Int { d[i..<i + 4].reduce(0) { $0 << 8 | Int($1) } }
    return (be(16), be(20), Int(d[24]), Int(d[25]))
}

// MARK: the PNGs

let pngs = ((try? fm.contentsOfDirectory(atPath: layersDir)) ?? []).sorted()
ok(pngs == IconLayer.allCases.map(\.asset), "design/icon/layers holds one PNG per layer, numbered back to front: \(pngs)")
for layer in IconLayer.allCases {
    let h = pngHeader("\(layersDir)/\(layer.asset)")
    ok(h?.width == 1024 && h?.height == 1024, "\(layer.asset) is on the 1024 x 1024 canvas")
    ok(h?.depth == 8 && h?.colour == 6, "\(layer.asset) is 8-bit RGBA, so it has alpha")
}

// MARK: AppIcon.icon

let json = fm.contents(atPath: "\(bundle)/icon.json")
let icon = json.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
ok(icon != nil, "icon.json is a JSON object")
let groups = (icon?["groups"] as? [[String: Any]]) ?? []
ok(groups.count <= 4, "at most four groups, as Icon Composer asks (\(groups.count))")
ok(icon?["fill"] is [String: Any], "the icon has a fill behind the background layer")
ok(json.map { !String(decoding: $0, as: UTF8.self).contains("color-space-for-untagged-svg-colors") } ?? false,
   "no color-space-for-untagged-svg-colors (actool on Xcode 26.4-26.6 crashes on it)")

// Icon Composer lists groups, and the layers in each, front first.
var backToFront: [(group: String, name: String, image: String)] = []
for g in groups.reversed() {
    for l in ((g["layers"] as? [[String: Any]]) ?? []).reversed() {
        backToFront.append((g["name"] as? String ?? "", l["name"] as? String ?? "", l["image-name"] as? String ?? ""))
    }
}
let all = IconLayer.allCases
ok(backToFront.map(\.name) == all.map(\.rawValue), "the layers stack back to front: \(backToFront.map(\.name))")
ok(backToFront.map(\.image) == all.map(\.asset), "each layer names its own PNG")
ok(backToFront.map(\.group) == all.map(\.group), "each layer sits in its group")

let assets = ((try? fm.contentsOfDirectory(atPath: "\(bundle)/Assets")) ?? []).sorted()
ok(assets == backToFront.map(\.image).sorted(), "icon.json names every asset in Assets, and no other: \(assets)")
for a in assets {
    ok(fm.contents(atPath: "\(bundle)/Assets/\(a)") == fm.contents(atPath: "\(layersDir)/\(a)"),
       "Assets/\(a) is design/icon/layers/\(a)")
}

// MARK: the in-app view

let swift = fm.contents(atPath: "ios/RedPen/Shared/Brand/IconLayers.swift").flatMap { String(data: $0, encoding: .utf8) } ?? ""
ok(swift.contains("layer.asset") && swift.contains("subdirectory: \"layers\""),
   "IconLayers.swift shows each layer's PNG from the app's layers folder")
let project = fm.contents(atPath: "ios/project.yml").flatMap { String(data: $0, encoding: .utf8) } ?? ""
ok(project.contains("path: ../design/icon/layers"), "project.yml copies design/icon/layers into the app")

print(failures == 0 ? "all icon layer checks passed" : "\(failures) failed")
exit(failures == 0 ? 0 : 1)
