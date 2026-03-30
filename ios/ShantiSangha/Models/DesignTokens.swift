import SwiftUI

/// Sacred design tokens — single source of truth for colors.
/// Supports both light and dark mode.
extension Color {
    static let sacredGold = Color(hex: "#c4873b")
    static let sacredGoldDark = Color(hex: "#8b5a1b")
    static let sacredGoldLight = Color(hex: "#d4a054")

    static let sacredText = Color.adaptive(light: "#2b1e10", dark: "#f5ebe0")
    static let sacredTextSecondary = Color.adaptive(light: "#6b5740", dark: "#c4a882")
    static let sacredMuted = Color.adaptive(light: "#9a8568", dark: "#8a7a64")
    static let sacredMutedLight = Color.adaptive(light: "#b5996f", dark: "#7a6a54")
    static let sacredLabel = Color.adaptive(light: "#a38d6d", dark: "#b5996f")
    static let sacredBg = Color.adaptive(light: "#faf5ed", dark: "#1a1410")
    static let sacredBgCard = Color.adaptive(light: "#f5ebe0", dark: "#2a2018")
    static let sacredGreen = Color(hex: "#7aa87a")
    static let sacredGreenDark = Color(hex: "#5a8a5a")
    static let sacredRed = Color(hex: "#b45a3c")

    // MARK: - Helpers

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    static func adaptive(light: String, dark: String) -> Color {
        Color(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            var int: UInt64 = 0
            Scanner(string: h).scanHexInt64(&int)
            return UIColor(
                red: CGFloat((int >> 16) & 0xFF) / 255,
                green: CGFloat((int >> 8) & 0xFF) / 255,
                blue: CGFloat(int & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}
