import QuartzCore

/// Owns only the animation settings, so unrelated appearance changes preserve
/// the running animation's phase.
final class OverlayShader {
    private struct Configuration: Equatable {
        let mode: ShaderMode
        let speed: Double
        let reduceMotion: Bool
    }

    private var configuration: Configuration?
    private weak var appliedLayer: CALayer?

    @discardableResult
    func apply(mode: ShaderMode, speed: Double, reduceMotion: Bool, to layer: CALayer) -> Bool {
        let normalizedSpeed = speed.isFinite ? max(0.1, speed) : 1
        let next = Configuration(mode: mode, speed: normalizedSpeed, reduceMotion: reduceMotion)
        let animated = !reduceMotion && mode != .staticMode
        guard appliedLayer !== layer || configuration != next
                || (animated && layer.animation(forKey: "shader") == nil) else { return false }
        appliedLayer = layer
        configuration = next

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAnimation(forKey: "shader")
        layer.opacity = 1
        layer.transform = CATransform3DIdentity
        defer { CATransaction.commit() }
        guard animated else { return true }

        switch mode {
        case .staticMode:
            break
        case .breathing:
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = 0.75
            animation.toValue = 1.0
            animation.duration = 3.0 / normalizedSpeed
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(animation, forKey: "shader")
        case .pulse:
            let animation = CABasicAnimation(keyPath: "transform.scale")
            animation.fromValue = 1.0
            animation.toValue = 1.015
            animation.duration = 1.4 / normalizedSpeed
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(animation, forKey: "shader")
        case .drift:
            let group = CAAnimationGroup()
            let horizontal = CAKeyframeAnimation(keyPath: "transform.translation.x")
            horizontal.values = [0, 8, 0, -8, 0]
            let vertical = CAKeyframeAnimation(keyPath: "transform.translation.y")
            vertical.values = [0, -6, 0, 6, 0]
            group.animations = [horizontal, vertical]
            group.duration = 7.0 / normalizedSpeed
            group.repeatCount = .infinity
            layer.add(group, forKey: "shader")
        }
        return true
    }
}
