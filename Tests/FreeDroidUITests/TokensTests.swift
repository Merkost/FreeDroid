import Testing
import SwiftUI
@testable import FreeDroidUI

@Suite("Tokens")
struct TokensTests {
    @Test func darkAndLightThemesProvideAllRequiredColors() {
        let dark = Theme.dark
        let light = Theme.light
        #expect(dark.colors != light.colors)
        #expect(dark.colorScheme == .dark)
        #expect(light.colorScheme == .light)
    }

    @Test func environmentDefaultIsDark() {
        let env = EnvironmentValues()
        #expect(env.theme.colorScheme == .dark)
    }

    @Test func motionPresetsAreDistinct() {
        #expect(Motion.crisp.response != Motion.smooth.response)
        #expect(Motion.smooth.response != Motion.lazy.response)
    }
}
