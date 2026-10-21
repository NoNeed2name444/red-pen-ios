// The app icon in layers (tools/icon_layers.py): every layer is a 1024 x 1024
// PNG with alpha, light and dark, stacked back to front in IconLayer's order,
// and the in-app view shows them; and the app icon itself
// (AppIcon.icon, from tools/make_icon.py) is valid, names every asset it
// ships, and has its dark and tinted looks. Run from the repository root
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
ok(pngs == IconLayer.assets.sorted(), "design/icon/layers holds one PNG per layer and look, numbered back to front: \(pngs)")
for asset in IconLayer.assets {
    let h = pngHeader("\(layersDir)/\(asset)")
    ok(h?.width == 1024 && h?.height == 1024, "\(asset) is on the 1024 x 1024 canvas")
    ok(h?.depth == 8 && h?.colour == 6, "\(asset) is 8-bit RGBA, so it has alpha")
}

// MARK: back to front

// IconLayer's order is the stacking order: the base at the back, the
// stethoscope in front. Each look's PNGs are numbered 0, 1, ... in that
// order, tools/icon_layers.py cuts them so, and the in-app view stacks
// them first to last (a ZStack puts its first view at the back).
let order = IconLayer.allCases
ok(order == [.background, .stethoscope], "the layers stack back to front, base then stethoscope: \(order.map(\.rawValue))")
ok(Set(IconLayer.assets).count == IconLayer.assets.count && IconLayer.assets.count == order.count * 2,
   "one PNG per layer and look, none twice: \(IconLayer.assets)")
for dark in [false, true] {
    let look = IconLayer.assets.filter { $0.hasSuffix("-dark.png") == dark }
    ok(look == order.map { $0.asset(dark: dark) }, "the \(dark ? "dark" : "light") look lists its layers back to front: \(look)")
    ok(look.map { Int($0.prefix { $0.isNumber }) ?? -1 } == Array(order.indices),
       "the \(dark ? "dark" : "light") look's PNGs are numbered back to front from 0: \(look)")
}
let cutter = fm.contents(atPath: "tools/icon_layers.py").flatMap { String(data: $0, encoding: .utf8) } ?? ""
ok(cutter.contains("(f\"0-background{suffix}.png\", bg), (f\"1-stethoscope{suffix}.png\", fg)"),
   "tools/icon_layers.py writes the base as 0 and the stethoscope over it as 1")

// MARK: AppIcon.icon (tools/make_icon.py, the owner's icon since 14 Oct)

let json = fm.contents(atPath: "\(bundle)/icon.json")
let icon = json.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
ok(icon != nil, "icon.json is a JSON object")
let groups = (icon?["groups"] as? [[String: Any]]) ?? []
ok(groups.count >= 1 && groups.count <= 4, "one to four groups, as Icon Composer asks (\(groups.count))")
ok(icon?["fill"] is [String: Any], "the icon has a fill behind its layers")
let fills = (icon?["fill-specializations"] as? [[String: Any]]) ?? []
ok(fills.contains { $0["appearance"] as? String == "dark" }, "the fill has a dark appearance")
ok(json.map { !String(decoding: $0, as: UTF8.self).contains("color-space-for-untagged-svg-colors") } ?? false,
   "no color-space-for-untagged-svg-colors (actool on Xcode 26.4-26.6 crashes on it)")
var named = Set<String>()
var appearances = Set<String>()
for g in groups {
    for l in (g["layers"] as? [[String: Any]]) ?? [] {
        if let n = l["image-name"] as? String { named.insert(n) }
        for sp in (l["image-name-specializations"] as? [[String: Any]]) ?? [] {
            if let n = sp["value"] as? String { named.insert(n) }
            if let a = sp["appearance"] as? String { appearances.insert(a) }
        }
    }
}
ok(appearances.isSuperset(of: ["dark", "tinted"]), "the picture has dark and tinted versions: \(appearances.sorted())")
let assets = ((try? fm.contentsOfDirectory(atPath: "\(bundle)/Assets")) ?? []).sorted()
ok(assets == named.sorted(), "icon.json names every asset in Assets, and no other: \(assets) vs \(named.sorted())")
for a in assets {
    let h = pngHeader("\(bundle)/Assets/\(a)")
    ok(h?.width == 1024 && h?.height == 1024, "Assets/\(a) is 1024 x 1024")
}
let setJSON = fm.contents(atPath: "ios/RedPen/Assets.xcassets/AppIcon.appiconset/Contents.json")
    .flatMap { String(data: $0, encoding: .utf8) } ?? ""
ok(setJSON.contains("\"dark\"") && setJSON.contains("\"tinted\""), "the icon set has dark and tinted appearances")

// MARK: the in-app view

let swift = fm.contents(atPath: "ios/RedPen/Shared/Brand/IconLayers.swift").flatMap { String(data: $0, encoding: .utf8) } ?? ""
ok(swift.contains("layer.asset(dark: scheme == .dark)") && swift.contains("subdirectory: \"layers\""),
   "IconLayers.swift shows each layer's PNG, light or dark, from the app's layers folder")
ok(swift.contains("var layers: [IconLayer] = IconLayer.allCases")
   && swift.contains("ZStack { ForEach(layers, id: \\.self) { IconLayerView(layer: $0) } }"),
   "IconLayersView stacks the layers in IconLayer's order, the first at the back")
let project = fm.contents(atPath: "ios/project.yml").flatMap { String(data: $0, encoding: .utf8) } ?? ""
ok(project.contains("path: ../design/icon/layers"), "project.yml copies design/icon/layers into the app")

print(failures == 0 ? "all icon layer checks passed" : "\(failures) failed")
exit(failures == 0 ? 0 : 1)
