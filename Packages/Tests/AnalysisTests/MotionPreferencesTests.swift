import Analysis
import Foundation
import Testing

struct MotionPreferencesTests {
    @Test func unrestrictedAllowsDecorationAndNumericText() {
        let motion = MotionPreferences.unrestricted
        #expect(motion.allowsDecoration)
        #expect(motion.usesNumericText)
    }

    @Test func reduceMotionCutsDecorationAndNumericText() {
        let motion = gated(reduceMotion: true)
        #expect(motion.allowsDecoration == false)
        #expect(motion.usesNumericText == false)
    }

    @Test func reduceTransparencyCutsDecorationNotNumericText() {
        let motion = gated(reduceTransparency: true)
        #expect(motion.allowsDecoration == false)
        #expect(motion.usesNumericText)
    }

    @Test func lowPowerCutsDecorationNotNumericText() {
        let motion = gated(isLowPower: true)
        #expect(motion.allowsDecoration == false)
        #expect(motion.usesNumericText)
    }

    @Test func unkeyCutsDecorationNotNumericText() {
        let motion = gated(windowIsKey: false)
        #expect(motion.allowsDecoration == false)
        #expect(motion.usesNumericText)
    }

    @Test func inactiveAppCutsDecorationNotNumericText() {
        let motion = gated(isAppActive: false)
        #expect(motion.allowsDecoration == false)
        #expect(motion.usesNumericText)
    }

    @Test func thermalSeriousCutsDecorationNotNumericText() {
        let motion = gated(thermalSeriousOrWorse: true)
        #expect(motion.allowsDecoration == false)
        #expect(motion.usesNumericText)
        #expect(MotionPreferences.thermalSeriousOrWorse(.serious))
        #expect(MotionPreferences.thermalSeriousOrWorse(.critical))
        #expect(MotionPreferences.thermalSeriousOrWorse(.fair) == false)
        #expect(MotionPreferences.thermalSeriousOrWorse(.nominal) == false)
    }

    @Test func anyClosedGateBlocksDecoration() {
        let motion = gated(isLowPower: true, windowIsKey: false)
        #expect(motion.allowsDecoration == false)
        #expect(motion.usesNumericText)
    }

    private func gated(
        reduceMotion: Bool = false,
        reduceTransparency: Bool = false,
        isLowPower: Bool = false,
        windowIsKey: Bool = true,
        isAppActive: Bool = true,
        thermalSeriousOrWorse: Bool = false
    ) -> MotionPreferences {
        MotionPreferences(
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency,
            isLowPower: isLowPower,
            windowIsKey: windowIsKey,
            isAppActive: isAppActive,
            thermalSeriousOrWorse: thermalSeriousOrWorse
        )
    }
}
