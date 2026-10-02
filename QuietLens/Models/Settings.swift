import SwiftUI
import AppKit
import Combine

enum MenuBarLeftClickAction: String, CaseIterable, Identifiable {
    case toggleOverlay
    case openSettings
    var id: String { rawValue }
    var label: String {
        switch self {
        case .toggleOverlay: return "Toggle Overlay"
        case .openSettings: return "Open Settings"
        }
    }
}

enum TintPreset: String, CaseIterable, Identifiable {
    case midnight, charcoal, paper, warm, sunset, forest, ocean, magenta, amber, cosmic, matrix, custom
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var hex: String {
        switch self {
        case .midnight: return "#0A0A14"
        case .charcoal: return "#1C1C1E"
        case .paper:    return "#F5F2E8"
        case .warm:     return "#3A2418"
        case .sunset:   return "#5B1F2E"
        case .forest:   return "#0F2A1F"
        case .ocean:    return "#0A2540"
        case .magenta:  return "#3D0A2E"
        case .amber:    return "#4A2A0F"
        case .cosmic:   return "#1A0F3D"
        case .matrix:   return "#001A0F"
        case .custom:   return "#000000"
        }
    }
    var hex2: String {
        switch self {
        case .midnight: return "#1A1A2E"
        case .charcoal: return "#2C2C2E"
        case .paper:    return "#E8E2D0"
        case .warm:     return "#6B3A24"
        case .sunset:   return "#8A2E45"
        case .forest:   return "#1F4A3A"
        case .ocean:    return "#0F3D6B"
        case .magenta:  return "#6B1A4F"
        case .amber:    return "#8A4A1F"
        case .cosmic:   return "#3D1A6B"
        case .matrix:   return "#003D24"
        case .custom:   return "#000000"
        }
    }
}

enum OverlayMode: String, CaseIterable, Identifiable {
    case deep, ambient, tinted
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var summary: String {
        switch self {
        case .deep: return "Full coverage"
        case .ambient: return "Subtle gradient"
        case .tinted: return "Color wash"
        }
    }
    var dotColor: NSColor {
        switch self {
        case .deep: return .systemBlue
        case .ambient: return .systemPurple
        case .tinted: return .systemPink
        }
    }
}

enum ColorSchemePref: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum AutoDisableAfter: String, CaseIterable, Identifiable {
    case never, fiveMin = "5min", tenMin = "10min", thirtyMin = "30min", oneHour = "1h"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .never: return "Never"
        case .fiveMin: return "5 min"
        case .tenMin: return "10 min"
        case .thirtyMin: return "30 min"
        case .oneHour: return "1 hour"
        }
    }
    var seconds: TimeInterval? {
        switch self {
        case .never: return nil
        case .fiveMin: return 300
        case .tenMin: return 600
        case .thirtyMin: return 1800
        case .oneHour: return 3600
        }
    }
}

enum BackdropMode: String, CaseIterable, Identifiable {
    case blur, image, wallpaper
    var id: String { rawValue }
    var label: String {
        switch self {
        case .blur: return "Blur"
        case .image: return "Image"
        case .wallpaper: return "Wallpaper"
        }
    }
}

enum ShakeModifier: String, CaseIterable, Identifiable {
    case none, shift, option, command
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var flags: NSEvent.ModifierFlags {
        switch self {
        case .none: return []
        case .shift: return .shift
        case .option: return .option
        case .command: return .command
        }
    }
}

@MainActor
final class QuietLensSettings: ObservableObject {
    static let shared = QuietLensSettings()
    private let defaults = UserDefaults.standard

    @Published var launchAtLogin: Bool { didSet { set(launchAtLogin, "launchAtLogin"); applyLaunchAtLogin() } }
    @Published var menuBarLeftClick: MenuBarLeftClickAction { didSet { set(menuBarLeftClick.rawValue, "menuBarLeftClick") } }
    @Published var autoEnableOnFocus: Bool { didSet { set(autoEnableOnFocus, "autoEnableOnFocus") } }
    @Published var showIndicatorDot: Bool { didSet { set(showIndicatorDot, "showIndicatorDot") } }
    @Published var colorSchemePref: ColorSchemePref { didSet { set(colorSchemePref.rawValue, "colorSchemePref") } }
    @Published var cursorHalo: Bool { didSet { set(cursorHalo, "cursorHalo") } }
    @Published var focusOnHover: Bool { didSet { set(focusOnHover, "focusOnHover") } }
    @Published var autoDisableAfter: AutoDisableAfter { didSet { set(autoDisableAfter.rawValue, "autoDisableAfter") } }
    @Published var pinShortcutKey: UInt16? { didSet { defaults.set(pinShortcutKey.map { Int($0) }, forKey: "pinShortcutKey") } }
    @Published var pinShortcutMods: UInt { didSet { defaults.set(pinShortcutMods, forKey: "pinShortcutMods") } }

    @Published var overlayMode: OverlayMode { didSet { set(overlayMode.rawValue, "overlayMode") } }
    @Published var tintPreset: TintPreset { didSet { set(tintPreset.rawValue, "tintPreset"); applyPreset() } }
    @Published var useSystemTint: Bool { didSet { set(useSystemTint, "useSystemTint") } }
    @Published var blurIntensity: Double { didSet { set(blurIntensity, "blurIntensity") } }
    @Published var blurRadius: Double { didSet { set(blurRadius, "blurRadius") } }
    @Published var overlayOpacity: Double { didSet { set(overlayOpacity, "overlayOpacity") } }
    @Published var tintColorHex: String { didSet { set(tintColorHex, "tintColorHex") } }
    @Published var tintColor2Hex: String { didSet { set(tintColor2Hex, "tintColor2Hex") } }
    @Published var gradientEnabled: Bool { didSet { set(gradientEnabled, "gradientEnabled") } }
    @Published var gradientAngle: Double { didSet { set(gradientAngle, "gradientAngle") } }
    @Published var grainIntensity: Double { didSet { set(grainIntensity, "grainIntensity") } }
    @Published var grayscale: Bool { didSet { set(grayscale, "grayscale") } }
    @Published var fadeDuration: Double { didSet { set(fadeDuration, "fadeDuration") } }
    @Published var shaderMode: ShaderMode { didSet { set(shaderMode.rawValue, "shaderMode") } }
    @Published var animationSpeed: Double { didSet { set(animationSpeed, "animationSpeed") } }

    @Published var shakeEnabled: Bool { didSet { set(shakeEnabled, "shakeEnabled") } }
    @Published var shakeSensitivity: Double { didSet { set(shakeSensitivity, "shakeSensitivity") } }
    @Published var shakeModifier: ShakeModifier { didSet { set(shakeModifier.rawValue, "shakeModifier") } }

    @Published var toggleShortcutKey: UInt16? { didSet { defaults.set(toggleShortcutKey.map { Int($0) }, forKey: "toggleShortcutKey") } }
    @Published var toggleShortcutMods: UInt { didSet { defaults.set(toggleShortcutMods, forKey: "toggleShortcutMods") } }
    @Published var settingsShortcutKey: UInt16? { didSet { defaults.set(settingsShortcutKey.map { Int($0) }, forKey: "settingsShortcutKey") } }
    @Published var settingsShortcutMods: UInt { didSet { defaults.set(settingsShortcutMods, forKey: "settingsShortcutMods") } }
    @Published var excludeAppShortcutKey: UInt16? { didSet { defaults.set(excludeAppShortcutKey.map { Int($0) }, forKey: "excludeAppShortcutKey") } }
    @Published var excludeAppShortcutMods: UInt { didSet { defaults.set(excludeAppShortcutMods, forKey: "excludeAppShortcutMods") } }
    @Published var onboardingDismissed: Bool { didSet { set(onboardingDismissed, "onboardingDismissed") } }

    @Published var excludedBundleIDs: [String] { didSet { set(excludedBundleIDs, "excludedBundleIDs") } }
    @Published var pinnedBundleIDs: [String] { didSet { set(pinnedBundleIDs, "pinnedBundleIDs") } }
    @Published var highlightSameAppWindows: Bool { didSet { set(highlightSameAppWindows, "highlightSameAppWindows") } }
    @Published var autoHideDock: Bool { didSet { set(autoHideDock, "autoHideDock") } }
    @Published var autoHideMenuBar: Bool { didSet { set(autoHideMenuBar, "autoHideMenuBar") } }
    @Published var iCloudSyncEnabled: Bool { didSet { set(iCloudSyncEnabled, "iCloudSyncEnabled") } }
    @Published var edgeGlowEnabled: Bool { didSet { set(edgeGlowEnabled, "edgeGlowEnabled") } }
    @Published var edgeGlowRadius: Double { didSet { set(edgeGlowRadius, "edgeGlowRadius") } }
    @Published var backdropMode: BackdropMode { didSet { set(backdropMode.rawValue, "backdropMode") } }
    @Published var backdropImagePath: String? { didSet { defaults.set(backdropImagePath, forKey: "backdropImagePath") } }

    private init() {
        let d = UserDefaults.standard
        launchAtLogin = d.bool(forKey: "launchAtLogin")
        menuBarLeftClick = MenuBarLeftClickAction(rawValue: d.string(forKey: "menuBarLeftClick") ?? "") ?? .toggleOverlay
        autoEnableOnFocus = d.bool(forKey: "autoEnableOnFocus")
        showIndicatorDot = d.object(forKey: "showIndicatorDot") as? Bool ?? true
        colorSchemePref = ColorSchemePref(rawValue: d.string(forKey: "colorSchemePref") ?? "") ?? .system
        cursorHalo = d.bool(forKey: "cursorHalo")
        focusOnHover = d.bool(forKey: "focusOnHover")
        autoDisableAfter = AutoDisableAfter(rawValue: d.string(forKey: "autoDisableAfter") ?? "") ?? .never
        pinShortcutKey = (d.object(forKey: "pinShortcutKey") as? Int).flatMap { UInt16(exactly: $0) }
        pinShortcutMods = UInt(d.integer(forKey: "pinShortcutMods"))
        overlayMode = OverlayMode(rawValue: d.string(forKey: "overlayMode") ?? "") ?? .deep
        tintPreset = TintPreset(rawValue: d.string(forKey: "tintPreset") ?? "") ?? .midnight
        useSystemTint = d.bool(forKey: "useSystemTint")
        blurIntensity = d.object(forKey: "blurIntensity") as? Double ?? 0.6
        blurRadius = d.object(forKey: "blurRadius") as? Double ?? 20
        overlayOpacity = d.object(forKey: "overlayOpacity") as? Double ?? 0.7
        tintColorHex = d.string(forKey: "tintColorHex") ?? "#000000"
        tintColor2Hex = d.string(forKey: "tintColor2Hex") ?? "#1A1A2E"
        gradientEnabled = d.bool(forKey: "gradientEnabled")
        gradientAngle = d.object(forKey: "gradientAngle") as? Double ?? 90
        grainIntensity = d.object(forKey: "grainIntensity") as? Double ?? 0.0
        grayscale = d.bool(forKey: "grayscale")
        fadeDuration = d.object(forKey: "fadeDuration") as? Double ?? 0.25
        shaderMode = ShaderMode(rawValue: d.string(forKey: "shaderMode") ?? "") ?? .staticMode
        animationSpeed = d.object(forKey: "animationSpeed") as? Double ?? 1.0
        shakeEnabled = d.object(forKey: "shakeEnabled") as? Bool ?? true
        shakeSensitivity = d.object(forKey: "shakeSensitivity") as? Double ?? 0.5
        shakeModifier = ShakeModifier(rawValue: d.string(forKey: "shakeModifier") ?? "") ?? .none
        toggleShortcutKey = (d.object(forKey: "toggleShortcutKey") as? Int).flatMap { UInt16(exactly: $0) }
        toggleShortcutMods = UInt(d.integer(forKey: "toggleShortcutMods"))
        settingsShortcutKey = (d.object(forKey: "settingsShortcutKey") as? Int).flatMap { UInt16(exactly: $0) }
        settingsShortcutMods = UInt(d.integer(forKey: "settingsShortcutMods"))
        excludeAppShortcutKey = (d.object(forKey: "excludeAppShortcutKey") as? Int).flatMap { UInt16(exactly: $0) }
        excludeAppShortcutMods = UInt(d.integer(forKey: "excludeAppShortcutMods"))
        onboardingDismissed = d.bool(forKey: "onboardingDismissed")
        if d.object(forKey: "excludedBundleIDs") == nil {
            excludedBundleIDs = ["com.apple.finder"]
            d.set(["com.apple.finder"], forKey: "excludedBundleIDs")
        } else {
            excludedBundleIDs = d.stringArray(forKey: "excludedBundleIDs") ?? []
        }
        pinnedBundleIDs = d.stringArray(forKey: "pinnedBundleIDs") ?? []
        highlightSameAppWindows = d.bool(forKey: "highlightSameAppWindows")
        autoHideDock = d.bool(forKey: "autoHideDock")
        autoHideMenuBar = d.bool(forKey: "autoHideMenuBar")
        iCloudSyncEnabled = d.bool(forKey: "iCloudSyncEnabled")
        edgeGlowEnabled = d.bool(forKey: "edgeGlowEnabled")
        edgeGlowRadius = d.object(forKey: "edgeGlowRadius") as? Double ?? 12
        backdropMode = BackdropMode(rawValue: d.string(forKey: "backdropMode") ?? "") ?? .blur
        backdropImagePath = d.string(forKey: "backdropImagePath")
    }

    func reload() {
        let d = defaults
        launchAtLogin = d.bool(forKey: "launchAtLogin")
        menuBarLeftClick = MenuBarLeftClickAction(rawValue: d.string(forKey: "menuBarLeftClick") ?? "") ?? .toggleOverlay
        autoEnableOnFocus = d.bool(forKey: "autoEnableOnFocus")
        showIndicatorDot = d.object(forKey: "showIndicatorDot") as? Bool ?? true
        colorSchemePref = ColorSchemePref(rawValue: d.string(forKey: "colorSchemePref") ?? "") ?? .system
        cursorHalo = d.bool(forKey: "cursorHalo")
        focusOnHover = d.bool(forKey: "focusOnHover")
        autoDisableAfter = AutoDisableAfter(rawValue: d.string(forKey: "autoDisableAfter") ?? "") ?? .never
        pinShortcutKey = (d.object(forKey: "pinShortcutKey") as? Int).flatMap { UInt16(exactly: $0) }
        pinShortcutMods = UInt(d.integer(forKey: "pinShortcutMods"))
        overlayMode = OverlayMode(rawValue: d.string(forKey: "overlayMode") ?? "") ?? .deep
        tintPreset = TintPreset(rawValue: d.string(forKey: "tintPreset") ?? "") ?? .midnight
        useSystemTint = d.bool(forKey: "useSystemTint")
        blurIntensity = d.object(forKey: "blurIntensity") as? Double ?? 0.6
        blurRadius = d.object(forKey: "blurRadius") as? Double ?? 20
        overlayOpacity = d.object(forKey: "overlayOpacity") as? Double ?? 0.7
        tintColorHex = d.string(forKey: "tintColorHex") ?? "#000000"
        tintColor2Hex = d.string(forKey: "tintColor2Hex") ?? "#1A1A2E"
        gradientEnabled = d.bool(forKey: "gradientEnabled")
        gradientAngle = d.object(forKey: "gradientAngle") as? Double ?? 90
        grainIntensity = d.object(forKey: "grainIntensity") as? Double ?? 0.0
        grayscale = d.bool(forKey: "grayscale")
        fadeDuration = d.object(forKey: "fadeDuration") as? Double ?? 0.25
        shaderMode = ShaderMode(rawValue: d.string(forKey: "shaderMode") ?? "") ?? .staticMode
        animationSpeed = d.object(forKey: "animationSpeed") as? Double ?? 1.0
        shakeEnabled = d.object(forKey: "shakeEnabled") as? Bool ?? true
        shakeSensitivity = d.object(forKey: "shakeSensitivity") as? Double ?? 0.5
        shakeModifier = ShakeModifier(rawValue: d.string(forKey: "shakeModifier") ?? "") ?? .none
        onboardingDismissed = d.bool(forKey: "onboardingDismissed")
        excludedBundleIDs = d.stringArray(forKey: "excludedBundleIDs") ?? excludedBundleIDs
        pinnedBundleIDs = d.stringArray(forKey: "pinnedBundleIDs") ?? []
        highlightSameAppWindows = d.bool(forKey: "highlightSameAppWindows")
        autoHideDock = d.bool(forKey: "autoHideDock")
        autoHideMenuBar = d.bool(forKey: "autoHideMenuBar")
        iCloudSyncEnabled = d.bool(forKey: "iCloudSyncEnabled")
        edgeGlowEnabled = d.bool(forKey: "edgeGlowEnabled")
        edgeGlowRadius = d.object(forKey: "edgeGlowRadius") as? Double ?? 12
        backdropMode = BackdropMode(rawValue: d.string(forKey: "backdropMode") ?? "") ?? .blur
        backdropImagePath = d.string(forKey: "backdropImagePath")
    }

    private func set(_ v: Any?, _ k: String) { defaults.set(v, forKey: k) }

    private func applyPreset() {
        guard tintPreset != .custom else { return }
        tintColorHex = tintPreset.hex
        tintColor2Hex = tintPreset.hex2
    }

    var effectiveTintColor: NSColor {
        if useSystemTint { return NSColor.controlAccentColor }
        return NSColor(hex: tintColorHex) ?? .black
    }
    var effectiveTintColor2: NSColor {
        if useSystemTint { return NSColor.controlAccentColor.blended(withFraction: 0.3, of: .black) ?? .black }
        return NSColor(hex: tintColor2Hex) ?? .black
    }

    var tintColor: NSColor {
        get { NSColor(hex: tintColorHex) ?? .black }
        set { tintColorHex = newValue.toHex() }
    }

    private func applyLaunchAtLogin() {
        #if canImport(ServiceManagement)
        if #available(macOS 13.0, *) {
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("Launch at login error: \(error)")
            }
        }
        #endif
    }
}

import ServiceManagement

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        let r = CGFloat((v >> 16) & 0xff) / 255
        let g = CGFloat((v >> 8) & 0xff) / 255
        let b = CGFloat(v & 0xff) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
    func toHex() -> String {
        guard let c = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int(round(c.redComponent * 255))
        let g = Int(round(c.greenComponent * 255))
        let b = Int(round(c.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
