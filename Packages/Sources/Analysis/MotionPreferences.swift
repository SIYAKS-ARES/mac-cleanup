import Foundation

/// Decorative-motion gates. Progress bars, apply I/O, and the 50 ms ApplyBox poll are not gated.
public struct MotionPreferences: Equatable, Sendable {
    public let reduceMotion: Bool
    public let reduceTransparency: Bool
    public let isLowPower: Bool
    public let windowIsKey: Bool
    public let isAppActive: Bool
    public let thermalSeriousOrWorse: Bool

    /// TimelineView / Canvas / glow / particles. Not ProgressView. Not apply I/O.
    public var allowsDecoration: Bool {
        reduceMotion == false
            && reduceTransparency == false
            && isLowPower == false
            && windowIsKey
            && isAppActive
            && thermalSeriousOrWorse == false
    }

    /// Apply byte `numericText`. Reduce Motion only — unkey / Low Power must not freeze the count.
    public var usesNumericText: Bool {
        reduceMotion == false
    }

    public init(
        reduceMotion: Bool,
        reduceTransparency: Bool,
        isLowPower: Bool,
        windowIsKey: Bool,
        isAppActive: Bool,
        thermalSeriousOrWorse: Bool
    ) {
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        self.isLowPower = isLowPower
        self.windowIsKey = windowIsKey
        self.isAppActive = isAppActive
        self.thermalSeriousOrWorse = thermalSeriousOrWorse
    }

    public static let unrestricted = MotionPreferences(
        reduceMotion: false,
        reduceTransparency: false,
        isLowPower: false,
        windowIsKey: true,
        isAppActive: true,
        thermalSeriousOrWorse: false
    )

    public static func thermalSeriousOrWorse(_ state: ProcessInfo.ThermalState) -> Bool {
        state.rawValue >= ProcessInfo.ThermalState.serious.rawValue
    }
}
