import SwiftUI
import AppKit

private let APPEARANCE_TINTS: [(label: String, hex: String)] = [
    // Brights
    ("Purple", "#8B5CF6"),
    ("Cyan", "#3DDBD9"),
    ("Magenta", "#FF5F6D"),
    ("Orange", "#FF8A3D"),
    ("Yellow", "#FFC93D"),
    ("Green", "#4ADE80"),
    ("Blue", "#4D8DF6"),
    // Darks
    ("Indigo", "#312E81"),
    ("Navy", "#0F2540"),
    ("Forest", "#0F2A1F"),
    ("Crimson", "#5B1F2E"),
    ("Slate", "#1F2937"),
    ("Charcoal", "#0B0B12"),
    // Neutrals
    ("White", "#E5E7EB"),
    ("Black", "#000000")
]

struct AppearanceScreen: View {
    @EnvironmentObject var settings: QuietLensSettings
    @Environment(\.colorScheme) var scheme
    var search: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if search.isEmpty {
                PageHeader("Appearance",
                           subtitle: "Tune how the overlay looks and moves.") {
                    GhostButton(title: "Reset", icon: "arrow.counterclockwise") { resetAppearance() }
                }

                // Live preview
                LivePreview()
                    .frame(height: 200)
                    .padding(.bottom, FL.S.s5)
            }

            if match("mode deep ambient tinted") {
                SectionLabel(text: "Mode")
                GlassPanel {
                    HStack(spacing: 12) {
                        ForEach(OverlayMode.allCases) { mode in
                            modeTile(mode)
                        }
                    }
                    .padding(12)
                }
            }

            if match("blur opacity strength") {
                SectionLabel(text: "Blur & Opacity")
                GlassPanel {
                    SettingsRow(icon: "drop", title: "Blur strength", isFirst: true,
                                trailing: {
                        Text("\(Int(round(settings.blurRadius * 2)))%")
                            .font(FL.T.mono())
                            .foregroundStyle(FL.C.text2(scheme))
                    },
                                below: {
                        GlassSlider(value: $settings.blurRadius, range: 0...50, a11yLabel: "Blur strength")
                            .padding(.top, 6)
                    })

                    SettingsRow(icon: "sun.max", title: "Opacity",
                                trailing: {
                        Text("\(Int(round(settings.overlayOpacity * 100)))%")
                            .font(FL.T.mono())
                            .foregroundStyle(FL.C.text2(scheme))
                    },
                                below: {
                        GlassSlider(value: $settings.overlayOpacity, range: 0.1...1.0, a11yLabel: "Overlay opacity")
                            .padding(.top, 6)
                    })
                }
            }

            if match("tint color system accent gradient secondary") {
                SectionLabel(text: "Tint")
                GlassPanel {
                    // Primary swatches
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Primary").font(FL.T.body()).foregroundStyle(FL.C.text1(scheme))
                            Spacer()
                            Button {
                                settings.useSystemTint.toggle()
                            } label: {
                                Text("As System")
                                    .font(FL.T.bodyR())
                                    .foregroundStyle(settings.useSystemTint ? FL.C.accent : FL.C.text2(scheme))
                            }
                            .buttonStyle(.plain)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 36, maximum: 40), spacing: 6)], spacing: 10) {
                            ColorSwatch(color: .clear, isSelected: settings.useSystemTint, rainbow: true) {
                                settings.useSystemTint = true
                            }
                            ForEach(APPEARANCE_TINTS, id: \.hex) { t in
                                ColorSwatch(color: Color(hex: t.hex) ?? .black,
                                            isSelected: !settings.useSystemTint && settings.tintColorHex.uppercased() == t.hex.uppercased(),
                                            label: t.label) {
                                    settings.useSystemTint = false
                                    settings.tintColorHex = t.hex
                                }
                            }
                        }
                    }
                    .padding(FL.S.s4)

                    SettingsRow(icon: "square.grid.2x2",
                                title: "Gradient",
                                subtitle: "Blend a second color across the overlay.",
                                trailing: { GlassSwitch(isOn: $settings.gradientEnabled) })

                    if settings.gradientEnabled {
                        SettingsRow(title: "Secondary color",
                                    trailing: {
                            HStack(spacing: 6) {
                                ForEach(APPEARANCE_TINTS.prefix(7), id: \.hex) { t in
                                    ColorSwatch(color: Color(hex: t.hex) ?? .black,
                                                isSelected: settings.tintColor2Hex.uppercased() == t.hex.uppercased(),
                                                label: t.label) {
                                        settings.tintColor2Hex = t.hex
                                    }
                                }
                            }
                        })

                        SettingsRow(icon: "arrow.up.right", title: "Angle",
                                    trailing: {
                            Text("\(Int(settings.gradientAngle))°")
                                .font(FL.T.mono()).foregroundStyle(FL.C.text2(scheme))
                        },
                                    below: {
                            GlassSlider(value: $settings.gradientAngle, range: 0...360, a11yLabel: "Gradient angle")
                                .padding(.top, 6)
                        })
                    }
                }
            }

            if match("texture grain grayscale") {
                SectionLabel(text: "Texture")
                GlassPanel {
                    SettingsRow(icon: "waveform", title: "Film grain", isFirst: true,
                                trailing: {
                        Text("\(Int(round(settings.grainIntensity * 100)))%")
                            .font(FL.T.mono()).foregroundStyle(FL.C.text2(scheme))
                    },
                                below: {
                        GlassSlider(value: $settings.grainIntensity, range: 0...1, a11yLabel: "Film grain")
                            .padding(.top, 6)
                    })

                    SettingsRow(icon: "paintbrush",
                                title: "Grayscale background",
                                subtitle: "Strip color from everything that isn't focused.",
                                trailing: { GlassSwitch(isOn: $settings.grayscale) })
                }
            }

            if match("shader static breathing drift pulse animation") {
                SectionLabel(text: "Shader")
                GlassPanel {
                    HStack {
                        Spacer()
                        GlassSegmented(selection: $settings.shaderMode,
                                       items: ShaderMode.allCases,
                                       label: { $0.label.capitalized },
                                       accent: true)
                        Spacer()
                    }
                    .padding(FL.S.s4)

                    if settings.shaderMode != .staticMode {
                        SettingsRow(icon: "speedometer", title: "Animation speed",
                                    trailing: {
                            Text(String(format: "%.1fx", settings.animationSpeed))
                                .font(FL.T.mono()).foregroundStyle(FL.C.text2(scheme))
                        },
                                    below: {
                            GlassSlider(value: $settings.animationSpeed, range: 0.25...3.0, a11yLabel: "Animation speed")
                                .padding(.top, 6)
                        })
                    }
                }
            }

            if match("active window glow halo edge") {
                SectionLabel(text: "Active Window Glow")
                GlassPanel {
                    SettingsRow(icon: "sparkles",
                                title: "Edge glow",
                                subtitle: "Soft halo around the focused window.",
                                isFirst: true,
                                trailing: { GlassSwitch(isOn: $settings.edgeGlowEnabled) })

                    if settings.edgeGlowEnabled {
                        SettingsRow(icon: "scope", title: "Halo intensity",
                                    trailing: {
                            Text("\(Int(round(settings.edgeGlowRadius)))px")
                                .font(FL.T.mono()).foregroundStyle(FL.C.text2(scheme))
                        },
                                    below: {
                            GlassSlider(value: $settings.edgeGlowRadius, range: 2...30, a11yLabel: "Halo intensity")
                                .padding(.top, 6)
                        })
                    }
                }
            }

            if match("backdrop image wallpaper") {
                SectionLabel(text: "Backdrop")
                GlassPanel {
                    HStack {
                        Spacer()
                        GlassSegmented(selection: $settings.backdropMode,
                                       items: BackdropMode.allCases,
                                       label: { $0.label },
                                       accent: true)
                        Spacer()
                    }
                    .padding(FL.S.s4)

                    if settings.backdropMode == .image {
                        SettingsRow(icon: "photo", title: "Custom Image",
                                    subtitle: settings.backdropImagePath ?? "None selected",
                                    trailing: {
                            HStack(spacing: 6) {
                                GhostButton(title: "Choose…") { pickImage() }
                                if settings.backdropImagePath != nil {
                                    DangerCircleButton(icon: "trash") { settings.backdropImagePath = nil }
                                }
                            }
                        })
                    }
                }
            }

            if match("transitions fade duration") {
                SectionLabel(text: "Transitions")
                GlassPanel {
                    SettingsRow(icon: "timer", title: "Fade duration", isFirst: true,
                                trailing: {
                        Text("\(Int(settings.fadeDuration * 1000))ms")
                            .font(FL.T.mono()).foregroundStyle(FL.C.text2(scheme))
                    },
                                below: {
                        GlassSlider(value: $settings.fadeDuration, range: 0.05...1.0, a11yLabel: "Fade duration")
                            .padding(.top, 6)
                    })
                }
            }
        }
    }

    private func modeTile(_ mode: OverlayMode) -> some View {
        let isSel = settings.overlayMode == mode
        return Button {
            withAnimation(FL.M.glass) { settings.overlayMode = mode }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(Color(nsColor: mode.dotColor))
                        .frame(width: 8, height: 8)
                        .shadow(color: Color(nsColor: mode.dotColor).opacity(0.7), radius: isSel ? 8 : 0)
                    Text(mode.label).font(FL.T.title()).foregroundStyle(FL.C.text1(scheme))
                }
                Text(mode.summary).font(FL.T.bodyR()).foregroundStyle(FL.C.text2(scheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSel ? FL.C.accentSoft : (scheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.025)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSel ? FL.C.accent : FL.C.edgeRing(scheme), lineWidth: isSel ? 1 : 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func match(_ keywords: String) -> Bool {
        settingsSearchMatch(keywords, search: search)
    }

    private func resetAppearance() {
        settings.overlayMode = .deep
        settings.blurRadius = 20
        settings.overlayOpacity = 0.7
        settings.gradientEnabled = false
        settings.grainIntensity = 0
        settings.grayscale = false
        settings.shaderMode = .staticMode
        settings.edgeGlowEnabled = false
        settings.backdropMode = .blur
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.backdropImagePath = url.path
        }
    }
}
