import SwiftUI
import AppKit

// MARK: - Settings search

/// Token match: every whitespace-separated token typed in the search field
/// must appear somewhere in the keyword string. "blur dock" matches a section
/// whose keywords contain both words anywhere, not just as one phrase.
func settingsSearchMatch(_ keywords: String, search: String) -> Bool {
    guard !search.isEmpty else { return true }
    let hay = keywords.lowercased()
    return search.lowercased()
        .split(whereSeparator: { $0.isWhitespace })
        .allSatisfy { hay.contains($0) }
}

// MARK: - Visual Effect Backgrounds

struct GlassMaterial: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blending
    }
}

// MARK: - Wallpaper background (decorative)

struct WallpaperBackground: View {
    @Environment(\.colorScheme) var scheme
    var body: some View {
        ZStack {
            LinearGradient(
                colors: scheme == .dark
                    ? [Color(hue: 0.78, saturation: 0.30, brightness: 0.18),
                       Color(hue: 0.85, saturation: 0.32, brightness: 0.14),
                       Color(hue: 0.69, saturation: 0.20, brightness: 0.14)]
                    : [Color(hue: 0.78, saturation: 0.18, brightness: 0.96),
                       Color(hue: 0.88, saturation: 0.20, brightness: 0.94),
                       Color(hue: 0.69, saturation: 0.18, brightness: 0.92)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            // Accent orb top-left
            Circle()
                .fill(FL.C.accent.opacity(scheme == .dark ? 0.40 : 0.55))
                .frame(width: 360, height: 360)
                .blur(radius: 60)
                .offset(x: -120, y: -200)
            // Complementary orb bottom-right
            Circle()
                .fill((Color(hex: "#F472B6") ?? .pink).opacity(scheme == .dark ? 0.35 : 0.45))
                .frame(width: 420, height: 420)
                .blur(radius: 60)
                .offset(x: 180, y: 220)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Glass Panel

struct GlassPanel<Content: View>: View {
    @Environment(\.colorScheme) var scheme
    let radius: CGFloat
    @ViewBuilder var content: Content
    init(radius: CGFloat = FL.R.card, @ViewBuilder content: () -> Content) {
        self.radius = radius
        self.content = content()
    }
    var body: some View {
        VStack(spacing: 0) { content }
            .background(
                ZStack {
                    // Real backdrop blur — lets wallpaper show through
                    Rectangle().fill(.ultraThinMaterial)
                    // Subtle tint layer for depth (very low opacity)
                    Rectangle().fill(scheme == .dark
                        ? Color.white.opacity(0.04)
                        : Color.white.opacity(0.10))
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(FL.C.edgeRing(scheme), lineWidth: 0.5)
            )
            .overlay(
                // Specular top edge highlight
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [FL.C.edgeTop(scheme), .clear],
                            startPoint: .top, endPoint: .center
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.10), radius: 18, y: 8)
    }
}

// MARK: - Section label

struct SectionLabel: View {
    @Environment(\.colorScheme) var scheme
    let text: String
    var body: some View {
        Text(text)
            .font(FL.T.caption())
            .tracking(0.9)
            .foregroundStyle(FL.C.text3(scheme))
            .textCase(.uppercase)
            .padding(.top, FL.S.s6)
            .padding(.bottom, FL.S.s3)
            .padding(.horizontal, FL.S.s2)
    }
}

// MARK: - Page header

struct PageHeader<Trailing: View>: View {
    @Environment(\.colorScheme) var scheme
    let title: String
    let subtitle: String?
    @ViewBuilder var trailing: Trailing
    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }
    var body: some View {
        HStack(alignment: .bottom, spacing: FL.S.s4) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 28, weight: .semibold))
                    .tracking(-0.4)
                    .foregroundStyle(FL.C.text1(scheme))
                if let subtitle {
                    Text(subtitle)
                        .font(FL.T.bodyR())
                        .foregroundStyle(FL.C.text2(scheme))
                }
            }
            Spacer()
            trailing
        }
        .padding(.bottom, FL.S.s6)
    }
}

// MARK: - Icon tile

struct IconTile: View {
    let systemName: String
    var tint: Tint = .accent
    enum Tint { case accent, neutral, danger }
    @Environment(\.colorScheme) var scheme
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .medium))
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(bg)
            )
            .foregroundStyle(fg)
    }
    private var bg: Color {
        switch tint {
        case .accent: return FL.C.accentSoft
        case .neutral: return scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05)
        case .danger: return FL.C.red.opacity(0.12)
        }
    }
    private var fg: Color {
        switch tint {
        case .accent: return FL.C.accent
        case .neutral: return FL.C.text2(scheme)
        case .danger: return FL.C.red
        }
    }
}

// MARK: - Settings row

private struct RowDividerKey: PreferenceKey {
    static var defaultValue: Int = 0
    static func reduce(value: inout Int, nextValue: () -> Int) {}
}

/// Row with icon + title (+ optional subtitle) + trailing. Optional content below body.
struct SettingsRow<Trailing: View, Below: View>: View {
    @Environment(\.colorScheme) var scheme
    let icon: String?
    let iconTint: IconTile.Tint
    let title: String
    let subtitle: String?
    let isFirst: Bool
    let comingSoon: Bool
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var below: Below

    init(icon: String? = nil,
         iconTint: IconTile.Tint = .accent,
         title: String,
         subtitle: String? = nil,
         isFirst: Bool = false,
         comingSoon: Bool = false,
         @ViewBuilder trailing: () -> Trailing = { EmptyView() },
         @ViewBuilder below: () -> Below = { EmptyView() }) {
        self.icon = icon
        self.iconTint = iconTint
        self.title = title
        self.subtitle = subtitle
        self.isFirst = isFirst
        self.comingSoon = comingSoon
        self.trailing = trailing()
        self.below = below()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top hairline for non-first rows (design says ::before sits at top:0 left:56px)
            if !isFirst {
                HStack(spacing: 0) {
                    Color.clear.frame(width: 56)
                    Rectangle().fill(FL.C.hairline(scheme))
                        .frame(height: 0.5)
                }
            }
            HStack(alignment: .center, spacing: FL.S.s3) {
                if let icon { IconTile(systemName: icon, tint: iconTint) }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(FL.T.title())
                            .foregroundStyle(comingSoon ? FL.C.text2(scheme) : FL.C.text1(scheme))
                        if comingSoon { ComingSoonBadge() }
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(FL.T.bodyR())
                            .foregroundStyle(FL.C.text2(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: FL.S.s3)
                trailing
                    .opacity(comingSoon ? 0.4 : 1)
                    .allowsHitTesting(!comingSoon)
            }
            .padding(.horizontal, FL.S.s4)
            .padding(.vertical, FL.S.s3)
            .frame(minHeight: 52)

            // Optional content below (e.g. slider)
            if !(below is EmptyView) {
                below
                    .opacity(comingSoon ? 0.4 : 1)
                    .allowsHitTesting(!comingSoon)
                    .padding(.leading, 56)
                    .padding(.trailing, FL.S.s4)
                    .padding(.bottom, FL.S.s3)
            }
        }
        // Rows without extra below-content read as one VoiceOver element
        // ("Launch at Login, …, On, button"). Rows with a slider below keep
        // their children separate so the slider's adjustable action works.
        .accessibilityElement(children: below is EmptyView ? .combine : .contain)
    }
}

struct ComingSoonBadge: View {
    @Environment(\.colorScheme) var scheme
    var body: some View {
        Text("COMING SOON")
            .font(.system(size: 9, weight: .bold))
            .tracking(0.6)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(FL.C.accent)
            .background(
                Capsule().fill(FL.C.accent.opacity(0.12))
            )
            .overlay(
                Capsule().strokeBorder(FL.C.accent.opacity(0.30), lineWidth: 0.5)
            )
    }
}

// MARK: - Glass Switch

struct GlassSwitch: View {
    @Binding var isOn: Bool
    @Environment(\.colorScheme) var scheme
    var body: some View {
        Button { withAnimation(FL.M.glass) { isOn.toggle() } } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? FL.C.accent : (scheme == .dark ? Color.white.opacity(0.20) : Color.black.opacity(0.18)))
                    .frame(width: 44, height: 26)
                    .shadow(color: isOn ? FL.C.accentGlow : .clear, radius: 8, x: 0, y: 0)
                    .overlay(
                        Capsule().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                    )
                Circle()
                    .fill(Color.white)
                    .frame(width: 22, height: 22)
                    .padding(2)
                    .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
                    .overlay(
                        Circle().strokeBorder(Color.black.opacity(0.10), lineWidth: 0.5).padding(2)
                    )
            }
            .frame(width: 44, height: 26)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

// MARK: - Glass Slider (working drag)

struct GlassSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    var a11yLabel: String = "Slider"
    @Environment(\.colorScheme) var scheme
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let pct = CGFloat((value - range.lowerBound) / max(0.0001, range.upperBound - range.lowerBound))
            let clampedPct = min(1, max(0, pct))
            let thumbX = clampedPct * w
            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(scheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.12))
                    .frame(height: 4)
                // Fill
                Capsule()
                    .fill(FL.C.accent)
                    .frame(width: thumbX, height: 4)
                    .shadow(color: FL.C.accentGlow, radius: 6, y: 0)
                // Thumb
                Circle()
                    .fill(Color.white)
                    .frame(width: 18, height: 18)
                    .overlay(
                        Circle().strokeBorder(Color.black.opacity(0.10), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    .offset(x: max(0, min(w - 18, thumbX - 9)))
            }
            .frame(height: 22)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        isDragging = true
                        updateValue(at: g.location.x, width: w)
                    }
                    .onEnded { _ in isDragging = false }
            )
        }
        .frame(height: 22)
        .accessibilityElement()
        .accessibilityLabel(a11yLabel)
        .accessibilityValue("\(Int(round(normalized * 100))) percent")
        .accessibilityAdjustableAction { direction in
            let delta = step ?? (range.upperBound - range.lowerBound) / 20
            switch direction {
            case .increment: value = min(range.upperBound, value + delta)
            case .decrement: value = max(range.lowerBound, value - delta)
            @unknown default: break
            }
        }
    }

    private var normalized: Double {
        let span = max(0.0001, range.upperBound - range.lowerBound)
        return min(1, max(0, (value - range.lowerBound) / span))
    }

    private func updateValue(at x: CGFloat, width w: CGFloat) {
        guard w > 0 else { return }
        let pct = max(0, min(1, x / w))
        var newValue = range.lowerBound + Double(pct) * (range.upperBound - range.lowerBound)
        if let step {
            newValue = (newValue / step).rounded() * step
        }
        value = max(range.lowerBound, min(range.upperBound, newValue))
    }
}

// MARK: - Segmented Control

struct GlassSegmented<T: Hashable & Identifiable>: View {
    @Binding var selection: T
    let items: [T]
    let label: (T) -> String
    var accent: Bool = false
    @Environment(\.colorScheme) var scheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let isSel = selection == item
                Button {
                    withAnimation(FL.M.quick) { selection = item }
                } label: {
                    Text(label(item))
                        .font(FL.T.body())
                        .foregroundStyle(isSel ? (accent ? Color.white : FL.C.text1(scheme)) : FL.C.text2(scheme))
                        .padding(.horizontal, FL.S.s4)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(
                            ZStack {
                                if isSel {
                                    if accent {
                                        Capsule().fill(FL.C.accent)
                                            .shadow(color: FL.C.accentGlow, radius: 8)
                                    } else {
                                        Capsule()
                                            .fill(.ultraThinMaterial)
                                            .overlay(
                                                Capsule().strokeBorder(FL.C.edgeTop(scheme).opacity(0.4), lineWidth: 0.5)
                                            )
                                            .shadow(color: .black.opacity(scheme == .dark ? 0.25 : 0.08), radius: 3, y: 1)
                                    }
                                }
                            }
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSel ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .opacity(0.35)
        )
        .overlay(
            Capsule().strokeBorder(FL.C.edgeRing(scheme), lineWidth: 0.5)
        )
    }
}

// MARK: - Kbd chip

struct Kbd: View {
    let text: String
    @Environment(\.colorScheme) var scheme
    var body: some View {
        Text(text.isEmpty ? "Not set" : text)
            .font(FL.T.mono())
            .foregroundStyle(text.isEmpty ? FL.C.text3(scheme) : FL.C.text1(scheme))
            .italic(text.isEmpty)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(FL.C.control(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(FL.C.edgeRing(scheme), lineWidth: 0.5)
            )
    }
}

// MARK: - Buttons (full hit area)

struct GhostButton: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void
    @Environment(\.colorScheme) var scheme
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 12, weight: .medium)) }
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 32)
            .background(
                RoundedRectangle(cornerRadius: FL.R.control, style: .continuous)
                    .fill(hover ? FL.C.controlHover(scheme) : FL.C.control(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: FL.R.control, style: .continuous)
                    .strokeBorder(FL.C.edgeRing(scheme), lineWidth: 0.5)
            )
            .foregroundStyle(FL.C.text1(scheme))
            .contentShape(RoundedRectangle(cornerRadius: FL.R.control))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 12, weight: .medium)) }
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: 32)
            .background(
                RoundedRectangle(cornerRadius: FL.R.control, style: .continuous)
                    .fill(FL.C.accent)
                    .shadow(color: FL.C.accentGlow, radius: 12, x: 0, y: 4)
            )
            .foregroundStyle(.white)
            .contentShape(RoundedRectangle(cornerRadius: FL.R.control))
        }
        .buttonStyle(.plain)
    }
}

struct DangerCircleButton: View {
    let icon: String
    let action: () -> Void
    @Environment(\.colorScheme) var scheme
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(Circle().fill(hover ? FL.C.red.opacity(0.16) : Color.clear))
                .overlay(Circle().strokeBorder(FL.C.hairline(scheme), lineWidth: 0.5))
                .foregroundStyle(FL.C.red)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Callout

struct Callout: View {
    let title: String
    let message: String
    let systemImage: String
    var trailing: AnyView? = nil
    @Environment(\.colorScheme) var scheme

    var body: some View {
        HStack(alignment: .top, spacing: FL.S.s3) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(FL.C.accent))
                .foregroundStyle(.white)
                .shadow(color: FL.C.accentGlow, radius: 8)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FL.C.text1(scheme))
                Text(message)
                    .font(FL.T.bodyR())
                    .foregroundStyle(FL.C.text2(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: FL.S.s3)
            if let trailing { trailing }
        }
        .padding(FL.S.s4)
        .background(
            RoundedRectangle(cornerRadius: FL.R.cardSm, style: .continuous).fill(FL.C.accentSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: FL.R.cardSm, style: .continuous)
                .strokeBorder(FL.C.accent.opacity(0.30), lineWidth: 0.5)
        )
    }
}

// MARK: - Color swatch (proper offset selection ring)

struct ColorSwatch: View {
    let color: Color
    let isSelected: Bool
    var rainbow: Bool = false
    var label: String? = nil
    var action: () -> Void
    @Environment(\.colorScheme) var scheme
    var body: some View {
        Button(action: action) {
            ZStack {
                if rainbow {
                    Circle().fill(AngularGradient(
                        gradient: Gradient(colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .red]),
                        center: .center))
                } else {
                    Circle().fill(color)
                }
            }
            .frame(width: 28, height: 28)
            .overlay(
                Circle().strokeBorder(FL.C.edgeRing(scheme), lineWidth: 0.5)
            )
            .padding(4)
            .background(
                Circle().strokeBorder(
                    isSelected ? FL.C.text1(scheme) : .clear,
                    lineWidth: 1.5
                )
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label ?? (rainbow ? "System accent color" : "Color swatch"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Pretty Picker (dropdown look)

struct GlassPicker<T: Hashable & Identifiable>: View {
    @Binding var selection: T
    let items: [T]
    let label: (T) -> String
    @Environment(\.colorScheme) var scheme
    var body: some View {
        Menu {
            ForEach(items) { item in
                Button(label(item)) { selection = item }
            }
        } label: {
            HStack(spacing: 6) {
                Text(label(selection)).font(FL.T.body())
                VStack(spacing: 0) {
                    Image(systemName: "chevron.up").font(.system(size: 7, weight: .bold))
                    Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
                }
                .foregroundStyle(FL.C.text3(scheme))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: FL.R.control).fill(FL.C.control(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: FL.R.control).strokeBorder(FL.C.edgeRing(scheme), lineWidth: 0.5)
            )
            .foregroundStyle(FL.C.text1(scheme))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
