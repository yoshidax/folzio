import Testing
@testable import FolzioCore

@Suite("SlideshowTransitionEffect")
struct SlideshowTransitionEffectTests {
    @Test("Replacement with a saved value and Reduce Motion enabled")
    func effects() {
        #expect(SlideshowTransitionEffect.allCases.map(\.rawValue) == ["none", "crossfade", "slide", "zoom"])
        for effect in SlideshowTransitionEffect.allCases {
            #expect(effect.effective(reduceMotion: false) == effect)
            let expected: SlideshowTransitionEffect = effect == .slide || effect == .zoom ? .crossfade : effect
            #expect(effect.effective(reduceMotion: true) == expected)
        }
    }
}
