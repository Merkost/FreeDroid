import SwiftUI

public enum Typography {
    public static let display = Font.system(size: 26, weight: .semibold, design: .default)
    public static let title = Font.system(size: 18, weight: .semibold, design: .default)
    public static let bodyEmphasized = Font.system(size: 13, weight: .semibold)
    public static let body = Font.system(size: 13, weight: .regular)
    public static let callout = Font.system(size: 12, weight: .regular)
    public static let caption = Font.system(size: 11, weight: .regular)
    public static let captionEmphasized = Font.system(size: 11, weight: .semibold)
    public static let label = Font.system(size: 10, weight: .semibold).smallCaps()
    public static let numeral = Font.system(size: 13, weight: .medium, design: .rounded).monospacedDigit()
    public static let monoCaption = Font.system(size: 10, weight: .medium, design: .monospaced)
}
