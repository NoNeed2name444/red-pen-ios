// The owner's logo lookup (BrandLogo): added to the root of the built app's
// bundle after build (stethoscore-logo.png for day, stethoscore-logo-dark.png
// for night) and never kept in the repository. Tested across the three bundle
// states: no file, the day file only, and both.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

func makeBundleDir(_ files: [String]) -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("brandlogo-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for name in files {
        let url = dir.appendingPathComponent(name, isDirectory: false)
        try? Data([0x89, 0x50, 0x4E, 0x47]).write(to: url)
    }
    return dir
}

// MARK: - Case 1: no file

do {
    let dir = makeBundleDir([])
    defer { try? FileManager.default.removeItem(at: dir) }
    check("no file: day returns nil",
          BrandLogo.fileName(dark: false, hasDay: false, hasNight: false) == nil
          && BrandLogo.url(dark: false, in: dir) == nil)
    check("no file: night returns nil",
          BrandLogo.fileName(dark: true, hasDay: false, hasNight: false) == nil
          && BrandLogo.url(dark: true, in: dir) == nil)
}

// MARK: - Case 2: the day file only

do {
    let dir = makeBundleDir([BrandLogo.dayFile])
    defer { try? FileManager.default.removeItem(at: dir) }
    check("day file only: day picks stethoscore-logo.png",
          BrandLogo.fileName(dark: false, hasDay: true, hasNight: false) == BrandLogo.dayFile
          && BrandLogo.url(dark: false, in: dir)?.lastPathComponent == BrandLogo.dayFile)
    check("day file only: night falls back to stethoscore-logo.png",
          BrandLogo.fileName(dark: true, hasDay: true, hasNight: false) == BrandLogo.dayFile
          && BrandLogo.url(dark: true, in: dir)?.lastPathComponent == BrandLogo.dayFile)
}

// MARK: - Case 3: both files

do {
    let dir = makeBundleDir([BrandLogo.dayFile, BrandLogo.nightFile])
    defer { try? FileManager.default.removeItem(at: dir) }
    check("both files: day picks stethoscore-logo.png",
          BrandLogo.fileName(dark: false, hasDay: true, hasNight: true) == BrandLogo.dayFile
          && BrandLogo.url(dark: false, in: dir)?.lastPathComponent == BrandLogo.dayFile)
    check("both files: night picks stethoscore-logo-dark.png",
          BrandLogo.fileName(dark: true, hasDay: true, hasNight: true) == BrandLogo.nightFile
          && BrandLogo.url(dark: true, in: dir)?.lastPathComponent == BrandLogo.nightFile)
}

// MARK: - Aspect and box bounds (1449 x 447, 72 pt default within 56...112)

let defaultBox = BrandLogo.boxSize(forHeight: 72)
check("default height is 72 pt at 1449:447 aspect",
      defaultBox.height == 72 && abs(defaultBox.width - 72 * 1449.0 / 447.0) < 1e-9,
      "\(defaultBox)")
check("scaled height is kept within 56 to 112 pt",
      BrandLogo.clampedHeight(40) == 56 && BrandLogo.clampedHeight(72) == 72 && BrandLogo.clampedHeight(140) == 112)
let narrowed = BrandLogo.boxSize(forHeight: 112, availableWidth: 180)
check("a narrow line scales the box down at the same aspect",
      narrowed.width == 180 && abs(narrowed.height - 180 / BrandLogo.aspect) < 1e-9,
      "\(narrowed)")

print(failures.isEmpty ? "\nALL BRAND LOGO TESTS PASS"
                       : "\n\(failures.count) BRAND LOGO TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
