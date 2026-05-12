import SwiftUI

public struct ColorTokens: Sendable, Equatable {
    public let background0: Color
    public let background1: Color
    public let background2: Color
    public let line: Color
    public let lineStrong: Color
    public let text0: Color
    public let text1: Color
    public let text2: Color
    public let text3: Color
    public let accent: Color
    public let accentSoft: Color
    public let adb: Color
    public let mtp: Color
    public let wifi: Color
    public let danger: Color
    public let warning: Color

    public static let dark = ColorTokens(
        background0: Color(red: 0.047, green: 0.051, blue: 0.063),
        background1: Color(red: 0.071, green: 0.075, blue: 0.090),
        background2: Color(red: 0.086, green: 0.094, blue: 0.114),
        line: Color.white.opacity(0.07),
        lineStrong: Color.white.opacity(0.12),
        text0: Color(red: 0.961, green: 0.961, blue: 0.969),
        text1: Color(red: 0.722, green: 0.725, blue: 0.753),
        text2: Color(red: 0.482, green: 0.490, blue: 0.525),
        text3: Color(red: 0.302, green: 0.310, blue: 0.341),
        accent: Color(red: 0.0, green: 0.878, blue: 0.541),
        accentSoft: Color(red: 0.0, green: 0.878, blue: 0.541).opacity(0.16),
        adb: Color(red: 0.0, green: 0.878, blue: 0.541),
        mtp: Color(red: 0.353, green: 0.663, blue: 1.0),
        wifi: Color(red: 0.690, green: 0.486, blue: 1.0),
        danger: Color(red: 1.0, green: 0.365, blue: 0.416),
        warning: Color(red: 1.0, green: 0.741, blue: 0.180)
    )

    public static let light = ColorTokens(
        background0: Color(red: 0.973, green: 0.973, blue: 0.976),
        background1: Color(red: 1.0, green: 1.0, blue: 1.0),
        background2: Color(red: 0.949, green: 0.949, blue: 0.957),
        line: Color.black.opacity(0.08),
        lineStrong: Color.black.opacity(0.14),
        text0: Color(red: 0.059, green: 0.059, blue: 0.078),
        text1: Color(red: 0.298, green: 0.310, blue: 0.341),
        text2: Color(red: 0.467, green: 0.482, blue: 0.518),
        text3: Color(red: 0.659, green: 0.671, blue: 0.706),
        accent: Color(red: 0.0, green: 0.682, blue: 0.420),
        accentSoft: Color(red: 0.0, green: 0.682, blue: 0.420).opacity(0.12),
        adb: Color(red: 0.0, green: 0.682, blue: 0.420),
        mtp: Color(red: 0.149, green: 0.471, blue: 0.851),
        wifi: Color(red: 0.490, green: 0.255, blue: 0.890),
        danger: Color(red: 0.875, green: 0.227, blue: 0.286),
        warning: Color(red: 0.812, green: 0.553, blue: 0.094)
    )
}
