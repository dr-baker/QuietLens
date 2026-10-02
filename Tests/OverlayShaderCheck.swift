import QuartzCore

@main
struct OverlayShaderCheck {
    static func main() {
        // Keep the transaction open while inspecting unhosted layers. A final
        // commit discards animations with no render tree to display them.
        CATransaction.begin()
        defer { CATransaction.commit() }
        let shader = OverlayShader()
        let layer = CALayer()
        precondition(shader.apply(mode: .breathing, speed: 1, reduceMotion: false, to: layer))
        precondition(layer.animation(forKey: "shader")?.duration == 3)
        guard let running = layer.animation(forKey: "shader")?.copy() as? CAAnimation else {
            fatalError("Expected a breathing animation")
        }
        running.beginTime = 42
        layer.add(running, forKey: "shader")
        precondition(!shader.apply(mode: .breathing, speed: 1, reduceMotion: false, to: layer))
        precondition(layer.animation(forKey: "shader")?.beginTime == 42)
        precondition(shader.apply(mode: .breathing, speed: 2, reduceMotion: false, to: layer))
        precondition(layer.animation(forKey: "shader")?.duration == 1.5)
        precondition(shader.apply(mode: .breathing, speed: 2, reduceMotion: true, to: layer))
        precondition(layer.animation(forKey: "shader") == nil && layer.opacity == 1)
        precondition(CATransform3DIsIdentity(layer.transform))

        for mode in [ShaderMode.pulse, .drift] {
            precondition(shader.apply(mode: mode, speed: 1, reduceMotion: false, to: layer))
            precondition(layer.animation(forKey: "shader") != nil)
            precondition(!shader.apply(mode: mode, speed: 1, reduceMotion: false, to: layer))
        }
        precondition(shader.apply(mode: .staticMode, speed: 1, reduceMotion: false, to: layer))
        precondition(layer.animation(forKey: "shader") == nil)
        let replacement = CALayer()
        precondition(shader.apply(mode: .breathing, speed: .nan, reduceMotion: false, to: replacement))
        precondition(replacement.animation(forKey: "shader")?.duration == 3)
        replacement.removeAllAnimations()
        precondition(shader.apply(mode: .breathing, speed: .nan, reduceMotion: false, to: replacement))
        print("Overlay shader phase, configuration, Reduce Motion, and layer replacement: passed")
    }
}
