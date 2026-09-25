# CI only (swiftpm-launch.yml): adds a simulator-only hook to a made package so
# a launch can start signed in on this device only - as the owner's phone is -
# and reach the library and everything it starts, not just the sign-in screen.
# The package in the zip for the phone never gets this; neither does ios/RedPen.
import os, sys
root = sys.argv[1]
open(os.path.join(root, "LaunchTestHook.swift"), "w").write('''#if targetEnvironment(simulator)
import Foundation

/// `-launchTestSignedIn`: a this-device-only session, the recording terms
/// agreed and the exam question answered, before any store is made.
enum LaunchTestHook {
    static func prepare() {
        guard ProcessInfo.processInfo.arguments.contains("-launchTestSignedIn") else { return }
        let id = "local-launchtest"
        if Keychain.session() == nil {
            Keychain.save(Session(account: Account(id: id, provider: .email, email: nil, displayName: "Me"),
                                  token: Session.localToken, refreshToken: nil, expiresAt: .distantFuture))
        }
        let signedIn = Keychain.session()?.account.id ?? id
        RecordingTerms.accept(for: signedIn)
        UserDefaults.standard.set(true, forKey: "exam.asked")
        UserDefaults.standard.synchronize()
        print("LaunchTestHook: signed in as", signedIn, "keychain:", Keychain.session() != nil)
    }
}
#endif
''')
p = os.path.join(root, "RedPenApp.swift")
s = open(p).read()
marker = "    init() {\n"
assert marker in s, "RedPenApp.init() not found"
s = s.replace(marker, marker + "        #if targetEnvironment(simulator)\n        LaunchTestHook.prepare()\n        #endif\n", 1)
open(p, "w").write(s)
print("hook added to", root)
