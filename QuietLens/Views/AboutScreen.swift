import SwiftUI

struct AboutScreen: View {
    @Environment(\.colorScheme) var scheme

    private var appVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = (info["CFBundleShortVersionString"] as? String) ?? "—"
        let build = (info["CFBundleVersion"] as? String) ?? "—"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader("About", subtitle: "Version, license, and credits.")

            GlassPanel {
                VStack(spacing: FL.S.s4) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable().interpolation(.high)
                        .frame(width: 120, height: 120)
                        .shadow(color: .black.opacity(0.3), radius: 24, y: 12)
                    Text("Quiet Lens")
                        .font(.system(size: 24, weight: .semibold))
                    Text("Maintained by Daniel Baker")
                        .font(FL.T.bodyR())
                        .foregroundStyle(FL.C.text2(scheme))
                    HStack(spacing: 6) {
                        Circle().fill(FL.C.green).frame(width: 8, height: 8)
                            .shadow(color: FL.C.green.opacity(0.6), radius: 4)
                        Text(appVersion)
                            .font(FL.T.mono())
                            .foregroundStyle(FL.C.text2(scheme))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(FL.C.control(scheme)))
                    .overlay(Capsule().strokeBorder(FL.C.edgeRing(scheme), lineWidth: 0.5))

                    Text("Dim everything except your active window.")
                        .font(FL.T.bodyR())
                        .foregroundStyle(FL.C.text2(scheme))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, FL.S.s7)
            }

            SectionLabel(text: "Links")
            GlassPanel {
                LinkRow(icon: "globe", title: "Source",
                        urlString: "https://github.com/dr-baker/QuietLens",
                        cta: "Open", isFirst: true)
                LinkRow(icon: "doc.text", title: "License MIT",
                        urlString: "https://opensource.org/licenses/MIT",
                        cta: "View")
                LinkRow(icon: "ant", title: "Report an issue",
                        urlString: "https://github.com/dr-baker/QuietLens/issues",
                        cta: "GitHub")
            }

            SectionLabel(text: "Credits")
            GlassPanel {
                Text("Fork of Quiet Lens by Parth Thummar and Quiet Apps. Inspired by Monocle. Built with Swift, SwiftUI, and AppKit.")
                    .font(FL.T.bodyR())
                    .foregroundStyle(FL.C.text2(scheme))
                    .padding(FL.S.s4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct LinkRow: View {
    let icon: String
    let title: String
    let urlString: String
    let cta: String
    var isFirst: Bool = false

    var body: some View {
        SettingsRow(icon: icon, title: title, isFirst: isFirst, trailing: {
            if let url = URL(string: urlString) {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Text(cta).font(FL.T.body())
                        Image(systemName: "arrow.up.right.square").font(.system(size: 10))
                    }
                }
            }
        })
    }
}
