import QuartzCore
import UIKit

enum KeyboardVoiceActivityPhase: Equatable {
    case ready
    case listening
    case recognizing
}

/// UIKit counterpart of the containing app's Voice activity artwork.
final class KeyboardVoiceActivityIndicatorView: UIView {
    private let contentView = UIView()
    private let orbitView = UIView()
    private let coreImageView = UIImageView()
    private var accessibilityObservers: [NSObjectProtocol] = []
    private(set) var phase: KeyboardVoiceActivityPhase = .ready
    private var renderedPhase: KeyboardVoiceActivityPhase?
    private var renderedOrbitLayout: OrbitLayout?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureHierarchy()
        configureAccessibilityObservers()
        registerForTraitChanges([
            UITraitUserInterfaceStyle.self,
            UITraitAccessibilityContrast.self,
        ]) { (view: KeyboardVoiceActivityIndicatorView, _) in
            view.applyAppearance()
        }
        render(.ready)
    }

    isolated deinit {
        for observer in accessibilityObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentView.frame = bounds
        orbitView.frame = contentView.bounds
        coreImageView.frame = contentView.bounds
        let orbitLayout = OrbitLayout(size: bounds.size, phase: phase)
        guard renderedOrbitLayout != orbitLayout else { return }
        renderedOrbitLayout = orbitLayout
        rebuildOrbit()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        restartAnimations()
    }

    func render(_ phase: KeyboardVoiceActivityPhase) {
        guard renderedPhase != phase else { return }
        self.phase = phase
        renderedPhase = phase
        coreImageView.image = UIImage(named: phase.coreAssetName)
        accessibilityValue = phase.accessibilityValue
        applyAppearance()
        setNeedsLayout()
        layoutIfNeeded()
        restartAnimations()
    }

    private func configureHierarchy() {
        isAccessibilityElement = false
        isUserInteractionEnabled = false
        layer.masksToBounds = false

        contentView.isUserInteractionEnabled = false
        orbitView.isUserInteractionEnabled = false
        coreImageView.isUserInteractionEnabled = false
        coreImageView.contentMode = .scaleAspectFit

        addSubview(contentView)
        contentView.addSubview(orbitView)
        contentView.addSubview(coreImageView)
    }

    private func configureAccessibilityObservers() {
        accessibilityObservers.append(
            NotificationCenter.default.addObserver(
                forName: UIAccessibility.reduceMotionStatusDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.restartAnimations()
                }
            }
        )
        accessibilityObservers.append(
            NotificationCenter.default.addObserver(
                forName:
                    UIAccessibility.reduceTransparencyStatusDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.applyAppearance()
                }
            }
        )
    }

    private func rebuildOrbit() {
        orbitView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        guard bounds.width > 0, bounds.height > 0 else { return }

        switch phase {
        case .ready, .listening:
            addListeningOrbit()
        case .recognizing:
            addRecognizingOrbit()
        }
    }

    private func addListeningOrbit() {
        addRing(
            diameter: scaled(66),
            lineWidth: scaled(1.35),
            opacity: 0.82
        )
        addRing(
            diameter: scaled(58),
            lineWidth: scaled(1.15),
            opacity: 0.58
        )

        let diameter = scaled(7)
        let dot = CAShapeLayer()
        dot.path = UIBezierPath(
            ovalIn: CGRect(
                x: bounds.midX - diameter / 2,
                y: bounds.midY - scaled(33) - diameter / 2,
                width: diameter,
                height: diameter
            )
        ).cgPath
        dot.fillColor = phase.accent.withAlphaComponent(1).cgColor
        dot.shadowColor = phase.accent.withAlphaComponent(0.8).cgColor
        dot.shadowOpacity = 1
        dot.shadowRadius = scaled(4)
        dot.shadowOffset = .zero
        orbitView.layer.addSublayer(dot)
    }

    private func addRecognizingOrbit() {
        addRing(
            diameter: scaled(62),
            lineWidth: scaled(1.15),
            opacity: 0.68
        )

        let radius = scaled(33)
        for index in 0..<24 {
            let angle = Double(index) * .pi / 12 - .pi / 2
            let diameter = scaled(index.isMultiple(of: 4) ? 4.8 : 3.2)
            let center = CGPoint(
                x: bounds.midX + CGFloat(cos(angle)) * radius,
                y: bounds.midY + CGFloat(sin(angle)) * radius
            )
            let particle = CAShapeLayer()
            particle.path = UIBezierPath(
                ovalIn: CGRect(
                    x: center.x - diameter / 2,
                    y: center.y - diameter / 2,
                    width: diameter,
                    height: diameter
                )
            ).cgPath
            particle.fillColor = phase.accent.withAlphaComponent(
                index.isMultiple(of: 3) ? 0.9 : 0.48
            ).cgColor
            orbitView.layer.addSublayer(particle)
        }
    }

    private func addRing(
        diameter: CGFloat,
        lineWidth: CGFloat,
        opacity: CGFloat
    ) {
        let ring = CAShapeLayer()
        ring.path = UIBezierPath(
            ovalIn: CGRect(
                x: bounds.midX - diameter / 2,
                y: bounds.midY - diameter / 2,
                width: diameter,
                height: diameter
            )
        ).cgPath
        ring.fillColor = UIColor.clear.cgColor
        ring.strokeColor = phase.accent.withAlphaComponent(opacity).cgColor
        ring.lineWidth = lineWidth
        orbitView.layer.addSublayer(ring)
    }

    private func applyAppearance() {
        layer.shadowColor = phase.accent.cgColor
        layer.shadowOpacity = UIAccessibility.isReduceTransparencyEnabled
            ? 0
            : (traitCollection.userInterfaceStyle == .dark ? 0.28 : 0.16)
        layer.shadowOffset = .zero
        layer.shadowRadius = scaled(5)
    }

    private func restartAnimations() {
        contentView.layer.removeAllAnimations()
        orbitView.layer.removeAllAnimations()
        coreImageView.layer.removeAllAnimations()

        guard window != nil,
              !UIAccessibility.isReduceMotionEnabled,
              phase != .ready else {
            return
        }

        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0
        rotation.toValue = Double.pi * 2
        rotation.duration = phase.rotationDuration
        rotation.repeatCount = .infinity
        rotation.isRemovedOnCompletion = false
        orbitView.layer.add(rotation, forKey: "keyboard.voice.orbit")

        addPulse(
            to: coreImageView.layer,
            scale: phase.corePulseScale,
            key: "keyboard.voice.core-pulse"
        )
        addPulse(
            to: contentView.layer,
            scale: phase.containerPulseScale,
            key: "keyboard.voice.container-pulse"
        )
    }

    private func addPulse(
        to layer: CALayer,
        scale: CGFloat,
        key: String
    ) {
        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = 1
        animation.toValue = scale
        animation.duration = phase.pulseDuration
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(
            name: .easeInEaseOut
        )
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: key)
    }

    private func scaled(_ value: CGFloat) -> CGFloat {
        value * min(bounds.width, bounds.height) / Self.sourceSize
    }

    private static let sourceSize: CGFloat = 72
}

private struct OrbitLayout: Equatable {
    let size: CGSize
    let phase: KeyboardVoiceActivityPhase
}

private extension KeyboardVoiceActivityPhase {
    var coreAssetName: String {
        switch self {
        case .ready, .listening:
            "ActivityRecordingCoreLight"
        case .recognizing:
            "ActivityTranscribingCoreLight"
        }
    }

    var accessibilityValue: String {
        switch self {
        case .ready:
            "Ready"
        case .listening:
            "Listening"
        case .recognizing:
            "Recognizing"
        }
    }

    var accent: UIColor {
        switch self {
        case .ready, .listening:
            UIColor(red: 0.031, green: 0.545, blue: 0.941, alpha: 1)
        case .recognizing:
            UIColor(red: 0.388, green: 0.078, blue: 0.894, alpha: 1)
        }
    }

    var pulseDuration: CFTimeInterval {
        switch self {
        case .ready:
            0
        case .listening:
            0.78
        case .recognizing:
            1.05
        }
    }

    var rotationDuration: CFTimeInterval {
        switch self {
        case .ready:
            0
        case .listening:
            1.8
        case .recognizing:
            2.4
        }
    }

    var corePulseScale: CGFloat {
        switch self {
        case .ready:
            1
        case .listening:
            1.035
        case .recognizing:
            1.02
        }
    }

    var containerPulseScale: CGFloat {
        switch self {
        case .ready:
            1
        case .listening:
            1.025
        case .recognizing:
            1.015
        }
    }
}
