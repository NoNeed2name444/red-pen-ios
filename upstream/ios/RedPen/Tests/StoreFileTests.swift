// A library file that is there but cannot be read is not an empty library,
// and a write that did not land is not a save.

import Foundation

var failures = 0
func ok(_ condition: Bool, _ what: String) {
    print((condition ? "ok   " : "FAIL ") + what)
    if !condition { failures += 1 }
}

let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("storefiles-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
// chmod means nothing to root, which can read anything
let canRefuse: Bool = getuid() != 0

// MARK: reading

let missing = root.appendingPathComponent("never-written.json")
if case .missing = StoreFiles.read(missing) {
    ok(true, "a file that was never written is missing")
} else {
    ok(false, "a file that was never written is missing")
}
ok(!StoreFiles.isPresent(missing), "and is not present")

let library = root.appendingPathComponent("redpen-library.json")
let bytes = Data("{\"library\":[]}".utf8)
ok(StoreFiles.write(bytes, to: library) == nil, "a write to a fresh folder lands")
if case .data(let read) = StoreFiles.read(library) {
    ok(read == bytes, "and reads back the same bytes")
} else {
    ok(false, "and reads back the same bytes")
}

// the file is there, and the process may not read it: what a launch before
// the first unlock sees
try! FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: library.path)
if canRefuse {
    if case .unreadable = StoreFiles.read(library) {
        ok(true, "a file that is there but cannot be read is unreadable, not missing")
    } else {
        ok(false, "a file that is there but cannot be read is unreadable, not missing")
    }
    ok(StoreFiles.isPresent(library), "and is still present")
} else {
    print("skip  running as root: nothing is unreadable here")
}
try! FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: library.path)

// MARK: writing

let locked = root.appendingPathComponent("locked")
try! FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
try! FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: locked.path)
let inside = locked.appendingPathComponent("redpen-library.json")
if canRefuse {
    ok(StoreFiles.write(bytes, to: inside) != nil, "a write that cannot land says so")
    ok(!StoreFiles.isPresent(inside), "and leaves nothing behind")
} else {
    print("skip  running as root: every write lands")
}
try! FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path)

// an existing file is replaced whole: a write that fails part way leaves the
// old bytes, never a torn file
let older = Data("{\"library\":[1]}".utf8)
ok(StoreFiles.write(older, to: library) == nil, "a second write replaces the first")
if case .data(let read) = StoreFiles.read(library) {
    ok(read == older, "whole")
} else {
    ok(false, "whole")
}

try? FileManager.default.removeItem(at: root)
exit(failures == 0 ? 0 : 1)
