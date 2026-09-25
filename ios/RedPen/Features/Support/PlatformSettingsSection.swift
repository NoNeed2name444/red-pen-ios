import AppIntents
import SwiftUI

/// Settings > "iPhone and iPad", as Form sections: Siri and Spotlight, the
/// exam-day Live Activity, Face ID lock and mindful minutes in Health.
///
/// Drop into the settings Form: `PlatformSettingsSection()`. Needs the Store
/// in the environment (the Spotlight toggle re-indexes the library).
///
/// The Playgrounds build has no widgets, Live Activities, Face ID string or
/// Health entitlement, so there it shows the Spotlight toggle and one line
/// saying the rest come with the App Store version.
struct PlatformSettingsSection: View {
    @EnvironmentObject private var store: Store
    @AppStorage(SpotlightIndexer.key) private var spotlight = true
    @AppStorage(GlancePublisher.liveActivityKey) private var liveActivity = true
    @AppStorage(AppLock.key) private var appLock = false
    @AppStorage(MindfulMinutes.key) private var mindful = false
    @State private var healthRefused = false

    private static var isPlaygrounds: Bool {
        #if SWIFT_PACKAGE
        return true
        #else
        return false
        #endif
    }

    var body: some View {
        Section {
            Toggle("Show sets in Spotlight", isOn: $spotlight)
                .accessibilityIdentifier("platformSpotlight")
                .onChange(of: spotlight) { _, on in
                    if on {
                        SpotlightIndexer.shared.update(store.library)
                    } else {
                        SpotlightIndexer.shared.clear()
                    }
                }
            if !Self.isPlaygrounds {
                SiriTipView(intent: ReviewDueIntent())
                ShortcutsLink()
                    .shortcutsLinkStyle(.automaticOutline)
            }
        } header: {
            Text("Siri and Spotlight")
        } footer: {
            Text(siriFooter)
        }

        if !Self.isPlaygrounds {
            Section {
                Toggle("Exam-day Live Activity", isOn: $liveActivity)
                    .accessibilityIdentifier("platformLiveActivity")
            } header: {
                Text("Widgets")
            } footer: {
                Text("From 6 pm the evening before your exam, the Lock Screen shows the countdown and the cards still due. Add the widgets from the Home Screen, and the Review due button from Control Centre.")
            }
        }

        if AppLock.supported || MindfulMinutes.available {
            Section {
                if AppLock.supported {
                    Toggle("Lock with \(AppLock.biometryName)", isOn: $appLock)
                        .accessibilityIdentifier("platformAppLock")
                }
                if MindfulMinutes.available {
                    Toggle("Log focus rounds to Health", isOn: $mindful)
                        .accessibilityIdentifier("platformMindful")
                        .onChange(of: mindful) { _, on in
                            guard on else { return }
                            Task {
                                let ok: Bool = await MindfulMinutes.requestAccess()
                                if !ok {
                                    mindful = false
                                    healthRefused = true
                                }
                            }
                        }
                }
            } header: {
                Text("Privacy and Health")
            } footer: {
                Text(privacyFooter)
            }
        }
    }

    private var siriFooter: String {
        if Self.isPlaygrounds {
            return "Widgets, Live Activities and Siri phrases come with the App Store version."
        }
        return "Say \u{201C}Review my due cards in Stethoscore\u{201D} or \u{201C}Quiz me on cardiology in Stethoscore\u{201D}. Only set names and sizes go into Spotlight, on this device."
    }

    private var privacyFooter: String {
        var parts: [String] = []
        if AppLock.supported {
            parts.append("The lock blurs the app in the app switcher and asks for \(AppLock.biometryName) when you come back.")
        }
        if MindfulMinutes.available {
            let refused: String = healthRefused ? " Health did not allow it; turn it on in the Health app\u{2019}s Sharing settings." : ""
            parts.append("Finished focus rounds are saved as mindful minutes. Nothing is read from Health." + refused)
        }
        return parts.joined(separator: " ")
    }
}
