import SwiftUI
import AppKit

struct GeneralScreen: View {
    @EnvironmentObject var settings: QuietLensSettings
    @ObservedObject private var updates = UpdateChecker.shared
    var search: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if search.isEmpty {
                PageHeader("General",
                           subtitle: "How Quiet Lens starts up and lives in your menu bar.")

                if !settings.onboardingDismissed {
                    Callout(
                        title: "New to Quiet Lens?",
                        message: "Set a hotkey in Gestures, then add apps to Rules → Exclude so they stay clear while you work.",
                        systemImage: "sparkles",
                        trailing: AnyView(
                            GhostButton(title: "Got it") { settings.onboardingDismissed = true }
                        )
                    )
                    .padding(.bottom, FL.S.s5)
                }
            }

            if match("startup launch login auto enable focus") {
                SectionLabel(text: "Startup")
                GlassPanel {
                    SettingsRow(icon: "power",
                                title: "Launch at Login",
                                subtitle: "Open Quiet Lens automatically when you sign in.",
                                isFirst: true,
                                trailing: { GlassSwitch(isOn: $settings.launchAtLogin) })

                    SettingsRow(icon: "bolt",
                                title: "Auto-enable on focus",
                                subtitle: "Turn the overlay back on when you switch windows. Pauses after you turn it off manually.",
                                trailing: { GlassSwitch(isOn: $settings.autoEnableOnFocus) })
                }
            }

            if match("menu bar click action indicator dot") {
                SectionLabel(text: "Menu Bar")
                GlassPanel {
                    SettingsRow(icon: "menubar.rectangle",
                                title: "Menu Icon click action",
                                subtitle: "What happens when you click the menu bar icon.",
                                isFirst: true,
                                trailing: {
                        GlassSegmented(selection: $settings.menuBarLeftClick,
                                       items: MenuBarLeftClickAction.allCases,
                                       label: { $0.label })
                    })

                    SettingsRow(icon: "circle.fill",
                                title: "Show indicator dot",
                                subtitle: "Live state on the menu bar icon when the overlay is active.",
                                trailing: { GlassSwitch(isOn: $settings.showIndicatorDot) })
                }
            }

            if match("icloud sync settings cross macs") {
                SectionLabel(text: "Sync")
                GlassPanel {
                    SettingsRow(icon: "icloud",
                                title: "iCloud Settings Sync",
                                subtitle: "Mirror your overlay configuration across Macs. Active on builds signed with the iCloud entitlement.",
                                isFirst: true,
                                trailing: { GlassSwitch(isOn: $settings.iCloudSyncEnabled) })
                }
            }

            if match("appearance theme color scheme dark light") {
                SectionLabel(text: "Appearance")
                GlassPanel {
                    SettingsRow(icon: "sun.max",
                                title: "Color Scheme",
                                subtitle: "Override the system appearance for this app.",
                                isFirst: true,
                                trailing: {
                        GlassSegmented(selection: $settings.colorSchemePref,
                                       items: ColorSchemePref.allCases,
                                       label: { $0.label })
                    })
                }
            }

            if match("updates check version release new") {
                SectionLabel(text: "Updates")
                GlassPanel {
                    SettingsRow(icon: "arrow.down.circle",
                                title: "Check for Updates",
                                subtitle: updatesSubtitle,
                                isFirst: true,
                                trailing: { updatesTrailing })
                }
            }
        }
    }

    private var updatesSubtitle: String {
        switch updates.state {
        case .idle: return "You're on version \(updates.currentVersion)."
        case .checking: return "Checking the latest release on GitHub…"
        case .upToDate: return "You're up to date (\(updates.currentVersion))."
        case .noRelease: return "This fork has no published releases yet."
        case .available(let v, _): return "Version \(v) is available — you're on \(updates.currentVersion)."
        case .failed: return "Couldn't reach GitHub. Check your connection and try again."
        }
    }

    @ViewBuilder
    private var updatesTrailing: some View {
        switch updates.state {
        case .checking:
            ProgressView().controlSize(.small)
        case .available(_, let url):
            PrimaryButton(title: "View Release", icon: "arrow.up.right") {
                NSWorkspace.shared.open(url)
            }
        default:
            GhostButton(title: "Check now") { updates.check() }
        }
    }

    private func match(_ keywords: String) -> Bool {
        settingsSearchMatch(keywords, search: search)
    }
}
