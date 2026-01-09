import Foundation
import UIKit
import Flutter

/// Handler for iOS 26 Liquid Glass effects and native theming.
///
/// Liquid Glass is Apple's translucent design material introduced in iOS 26
/// that creates a glass-like appearance with dynamic environmental reflections.
///
/// This handler provides:
/// - Method channel communication with Flutter
/// - Native Liquid Glass effect application
/// - System accent color extraction
/// - Accessibility support (reduced transparency)
class LiquidGlassHandler: NSObject {

    // MARK: - Constants

    static let channelName = "com.project_flutter/liquid_glass"
    static let eventChannelName = "com.project_flutter/liquid_glass_events"

    // MARK: - Properties

    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?

    // Track applied effects
    private var appliedEffects: [String: LiquidGlassEffect] = [:]

    // Global configuration
    private var globalConfig: LiquidGlassConfig = LiquidGlassConfig()

    // MARK: - Singleton

    static let shared = LiquidGlassHandler()

    private override init() {
        super.init()
        setupAccessibilityObservers()
    }

    // MARK: - Setup

    /// Setup Flutter channels with the given binary messenger
    func setup(binaryMessenger: FlutterBinaryMessenger) {
        // Method channel for commands
        methodChannel = FlutterMethodChannel(
            name: LiquidGlassHandler.channelName,
            binaryMessenger: binaryMessenger
        )
        methodChannel?.setMethodCallHandler(handleMethodCall)

        // Event channel for theme change notifications
        eventChannel = FlutterEventChannel(
            name: LiquidGlassHandler.eventChannelName,
            binaryMessenger: binaryMessenger
        )
        eventChannel?.setStreamHandler(self)

        print("LiquidGlassHandler: Channels setup complete")
    }

    private func setupAccessibilityObservers() {
        // Listen for reduced transparency changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessibilitySettingsChanged),
            name: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            object: nil
        )

        // Listen for reduce motion changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessibilitySettingsChanged),
            name: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil
        )
    }

    @objc private func accessibilitySettingsChanged() {
        // Notify Flutter about accessibility changes
        sendEvent(type: "accessibilityChanged", data: [
            "reduceTransparency": UIAccessibility.isReduceTransparencyEnabled,
            "reduceMotion": UIAccessibility.isReduceMotionEnabled
        ])

        // Update all applied effects if reduce transparency is enabled
        if UIAccessibility.isReduceTransparencyEnabled {
            for (elementId, _) in appliedEffects {
                removeLiquidGlassEffect(elementId: elementId)
            }
        }
    }

    // MARK: - Method Channel Handler

    private func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getCapabilities":
            result(getCapabilities())

        case "applyLiquidGlass":
            guard let args = call.arguments as? [String: Any],
                  let elementId = args["elementId"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing elementId", details: nil))
                return
            }
            let intensity = args["intensity"] as? Double ?? 0.8
            let tintColor = args["tintColor"] as? Int
            let blurRadius = args["blurRadius"] as? Double ?? 20.0

            let success = applyLiquidGlassEffect(
                elementId: elementId,
                intensity: intensity,
                tintColor: tintColor,
                blurRadius: blurRadius
            )
            result(success)

        case "removeLiquidGlass":
            guard let args = call.arguments as? [String: Any],
                  let elementId = args["elementId"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing elementId", details: nil))
                return
            }
            let success = removeLiquidGlassEffect(elementId: elementId)
            result(success)

        case "applyGlobalLiquidGlassConfig":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing config", details: nil))
                return
            }
            let success = applyGlobalConfig(args)
            result(success)

        case "isReducedTransparencyEnabled":
            result(UIAccessibility.isReduceTransparencyEnabled)

        case "getSystemAccentColor":
            result(getSystemAccentColor())

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Capabilities

    private func getCapabilities() -> [String: Any] {
        // Check iOS version for Liquid Glass support
        // Liquid Glass requires iOS 26+
        let isLiquidGlassSupported: Bool
        if #available(iOS 26.0, *) {
            isLiquidGlassSupported = true
        } else {
            // For development/testing, we can simulate on iOS 15+
            isLiquidGlassSupported = false
        }

        return [
            "liquidGlassSupported": isLiquidGlassSupported,
            "materialYouSupported": false, // Android only
            "systemAccentColor": getSystemAccentColor() as Any,
            "reduceTransparencyEnabled": UIAccessibility.isReduceTransparencyEnabled,
            "reduceMotionEnabled": UIAccessibility.isReduceMotionEnabled
        ]
    }

    // MARK: - Liquid Glass Effects

    private func applyLiquidGlassEffect(
        elementId: String,
        intensity: Double,
        tintColor: Int?,
        blurRadius: Double
    ) -> Bool {
        // Don't apply if reduced transparency is enabled
        if UIAccessibility.isReduceTransparencyEnabled {
            print("LiquidGlassHandler: Skipping effect due to reduced transparency")
            return false
        }

        // Create effect configuration
        let effect = LiquidGlassEffect(
            elementId: elementId,
            intensity: intensity,
            tintColor: tintColor,
            blurRadius: blurRadius
        )

        // Apply based on element type
        DispatchQueue.main.async { [weak self] in
            self?.applyEffectToElement(effect)
        }

        // Track the effect
        appliedEffects[elementId] = effect

        print("LiquidGlassHandler: Applied Liquid Glass to '\(elementId)' with intensity \(intensity)")
        return true
    }

    private func applyEffectToElement(_ effect: LiquidGlassEffect) {
        guard let window = UIApplication.shared.windows.first else { return }

        switch effect.elementId {
        case "navbar":
            applyToNavigationBar(effect, in: window)
        case "tabbar":
            applyToTabBar(effect, in: window)
        case "toolbar":
            applyToToolbar(effect, in: window)
        case "background":
            applyToBackground(effect, in: window)
        case "sheet":
            applyToSheet(effect)
        default:
            // Custom element - try to find by accessibility identifier
            if let view = findViewByIdentifier(effect.elementId, in: window) {
                applyBlurEffect(to: view, effect: effect)
            }
        }
    }

    private func applyToNavigationBar(_ effect: LiquidGlassEffect, in window: UIWindow) {
        // iOS 15+ navigation bar appearance
        if #available(iOS 15.0, *) {
            let appearance = UINavigationBarAppearance()

            // Configure for Liquid Glass effect
            appearance.configureWithTransparentBackground()

            // Apply blur effect
            let blurEffect = UIBlurEffect(style: effect.intensity > 0.5 ? .systemMaterial : .systemUltraThinMaterial)
            appearance.backgroundEffect = blurEffect

            // Apply tint if specified
            if let tintColor = effect.tintColor {
                appearance.backgroundColor = UIColor(argb: tintColor).withAlphaComponent(CGFloat(effect.intensity * 0.3))
            }

            // Apply to all navigation bars
            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
            UINavigationBar.appearance().compactAppearance = appearance
        }
    }

    private func applyToTabBar(_ effect: LiquidGlassEffect, in window: UIWindow) {
        if #available(iOS 15.0, *) {
            let appearance = UITabBarAppearance()

            appearance.configureWithTransparentBackground()

            let blurEffect = UIBlurEffect(style: effect.intensity > 0.5 ? .systemMaterial : .systemUltraThinMaterial)
            appearance.backgroundEffect = blurEffect

            if let tintColor = effect.tintColor {
                appearance.backgroundColor = UIColor(argb: tintColor).withAlphaComponent(CGFloat(effect.intensity * 0.3))
            }

            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }

    private func applyToToolbar(_ effect: LiquidGlassEffect, in window: UIWindow) {
        if #available(iOS 15.0, *) {
            let appearance = UIToolbarAppearance()

            appearance.configureWithTransparentBackground()

            let blurEffect = UIBlurEffect(style: .systemMaterial)
            appearance.backgroundEffect = blurEffect

            UIToolbar.appearance().standardAppearance = appearance
            UIToolbar.appearance().compactAppearance = appearance
        }
    }

    private func applyToBackground(_ effect: LiquidGlassEffect, in window: UIWindow) {
        // Apply a subtle blur to the root view
        if let rootView = window.rootViewController?.view {
            // Remove existing blur if any
            rootView.subviews.filter { $0.tag == 999 }.forEach { $0.removeFromSuperview() }

            // Create blur view
            let blurEffect = UIBlurEffect(style: effect.intensity > 0.6 ? .systemThinMaterial : .systemUltraThinMaterial)
            let blurView = UIVisualEffectView(effect: blurEffect)
            blurView.tag = 999
            blurView.frame = rootView.bounds
            blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            blurView.alpha = CGFloat(effect.intensity * 0.5)

            rootView.insertSubview(blurView, at: 0)
        }
    }

    private func applyToSheet(_ effect: LiquidGlassEffect) {
        // Configure sheet presentation for Liquid Glass
        if #available(iOS 15.0, *) {
            // This will be applied when sheets are presented
            // Store configuration for use in sheet presentation
            globalConfig.sheetIntensity = effect.intensity
        }
    }

    private func applyBlurEffect(to view: UIView, effect: LiquidGlassEffect) {
        // Remove existing blur
        view.subviews.filter { $0 is UIVisualEffectView && $0.tag == 998 }.forEach { $0.removeFromSuperview() }

        // Create new blur
        let blurEffect = UIBlurEffect(style: .systemMaterial)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.tag = 998
        blurView.frame = view.bounds
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blurView.alpha = CGFloat(effect.intensity)

        view.insertSubview(blurView, at: 0)
    }

    private func findViewByIdentifier(_ identifier: String, in view: UIView) -> UIView? {
        if view.accessibilityIdentifier == identifier {
            return view
        }
        for subview in view.subviews {
            if let found = findViewByIdentifier(identifier, in: subview) {
                return found
            }
        }
        return nil
    }

    private func removeLiquidGlassEffect(elementId: String) -> Bool {
        appliedEffects.removeValue(forKey: elementId)

        DispatchQueue.main.async {
            guard let window = UIApplication.shared.windows.first else { return }

            switch elementId {
            case "navbar":
                UINavigationBar.appearance().standardAppearance = UINavigationBarAppearance()
                UINavigationBar.appearance().scrollEdgeAppearance = nil
            case "tabbar":
                UITabBar.appearance().standardAppearance = UITabBarAppearance()
                UITabBar.appearance().scrollEdgeAppearance = nil
            case "toolbar":
                UIToolbar.appearance().standardAppearance = UIToolbarAppearance()
            case "background":
                window.rootViewController?.view.subviews.filter { $0.tag == 999 }.forEach { $0.removeFromSuperview() }
            default:
                if let view = self.findViewByIdentifier(elementId, in: window) {
                    view.subviews.filter { $0.tag == 998 }.forEach { $0.removeFromSuperview() }
                }
            }
        }

        print("LiquidGlassHandler: Removed Liquid Glass from '\(elementId)'")
        return true
    }

    private func applyGlobalConfig(_ args: [String: Any]) -> Bool {
        globalConfig.enabled = args["enabled"] as? Bool ?? true
        globalConfig.defaultIntensity = args["defaultIntensity"] as? Double ?? 0.8
        globalConfig.adaptToEnvironment = args["adaptToEnvironment"] as? Bool ?? true
        globalConfig.reduceMotion = args["reduceMotion"] as? Bool ?? false

        if let elements = args["elements"] as? [String: Double] {
            for (elementId, intensity) in elements {
                _ = applyLiquidGlassEffect(
                    elementId: elementId,
                    intensity: intensity,
                    tintColor: nil,
                    blurRadius: 20.0
                )
            }
        }

        return true
    }

    // MARK: - System Colors

    private func getSystemAccentColor() -> Int? {
        // Get the system tint color
        if let tintColor = UIApplication.shared.windows.first?.tintColor {
            return tintColor.toARGB()
        }
        return UIColor.systemBlue.toARGB()
    }

    // MARK: - Events

    private func sendEvent(type: String, data: [String: Any]) {
        eventSink?(["type": type, "data": data])
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - FlutterStreamHandler

extension LiquidGlassHandler: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}

// MARK: - Supporting Types

struct LiquidGlassEffect {
    let elementId: String
    let intensity: Double
    let tintColor: Int?
    let blurRadius: Double
}

class LiquidGlassConfig {
    var enabled: Bool = true
    var defaultIntensity: Double = 0.8
    var adaptToEnvironment: Bool = true
    var reduceMotion: Bool = false
    var sheetIntensity: Double = 0.8
}

// MARK: - UIColor Extensions

extension UIColor {
    convenience init(argb: Int) {
        let alpha = CGFloat((argb >> 24) & 0xFF) / 255.0
        let red = CGFloat((argb >> 16) & 0xFF) / 255.0
        let green = CGFloat((argb >> 8) & 0xFF) / 255.0
        let blue = CGFloat(argb & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }

    func toARGB() -> Int {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        let a = Int(alpha * 255) << 24
        let r = Int(red * 255) << 16
        let g = Int(green * 255) << 8
        let b = Int(blue * 255)

        return a | r | g | b
    }
}
