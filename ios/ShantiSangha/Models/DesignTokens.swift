import SwiftUI

/// Sacred design tokens — single source of truth for colors.
/// Mirrors frontend/tailwind.config.js sacred-* tokens.
extension Color {
    static let sacredGold = Color(hex: "#c4873b")
    static let sacredGoldDark = Color(hex: "#8b5a1b")
    static let sacredText = Color(hex: "#2b1e10")
    static let sacredTextSecondary = Color(hex: "#6b5740")
    static let sacredMuted = Color(hex: "#9a8568")
    static let sacredMutedLight = Color(hex: "#b5996f")
    static let sacredLabel = Color(hex: "#a38d6d")
    static let sacredBg = Color(hex: "#faf5ed")
    static let sacredGreen = Color(hex: "#7aa87a")
    static let sacredGreenDark = Color(hex: "#5a8a5a")
    static let sacredRed = Color(hex: "#b45a3c")

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
