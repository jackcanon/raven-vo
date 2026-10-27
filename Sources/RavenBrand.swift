import SwiftUI
import AppKit

// RavenMix Brand Guide v1.0, September 22, 2026: shared Raven family tokens.
enum RavenBrand {
    // Opaque supporting text avoids low-contrast tertiary text on desktop materials.
    static let secondaryText = Color(nsColor: NSColor(name: "RavenVOSecondaryText") { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let level: CGFloat = dark ? 0.72 : 0.35
        return NSColor(srgbRed: level, green: level, blue: level, alpha: 1)
    })
    static let primaryActionText = Color(red: 17 / 255.0, green: 17 / 255.0, blue: 17 / 255.0)
    static let recordRed = Color(red: 198 / 255.0, green: 40 / 255.0, blue: 40 / 255.0)
    static let headphoneAmber = Color(red: 242 / 255.0, green: 173 / 255.0, blue: 50 / 255.0)
    static let previewGreen = Color(red: 33 / 255.0, green: 163 / 255.0, blue: 102 / 255.0)
}
