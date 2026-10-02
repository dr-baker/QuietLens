enum ShaderMode: String, CaseIterable, Identifiable {
    case staticMode = "static", breathing, drift, pulse
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}
