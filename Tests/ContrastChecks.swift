import AppKit
import SwiftUI

@main struct ContrastChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        func rgb(_ color: NSColor, over background: NSColor = .white) -> [Double] {
            let c = color.usingColorSpace(.sRGB)!, b = background.usingColorSpace(.sRGB)!
            let a = Double(c.alphaComponent)
            return zip([c.redComponent,c.greenComponent,c.blueComponent], [b.redComponent,b.greenComponent,b.blueComponent]).map { Double($0) * a + Double($1) * (1-a) }
        }
        func luminance(_ values: [Double]) -> Double {
            zip(values, [0.2126,0.7152,0.0722]).map { value, weight in
                (value <= 0.04045 ? value / 12.92 : pow((value + 0.055)/1.055, 2.4)) * weight
            }.reduce(0,+)
        }
        func contrast(_ a: [Double], _ b: [Double]) -> Double {
            let x=luminance(a), y=luminance(b)
            return (max(x,y)+0.05)/(min(x,y)+0.05)
        }
        for name in [NSAppearance.Name.aqua,.darkAqua,.accessibilityHighContrastAqua,.accessibilityHighContrastDarkAqua] {
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                let background = NSColor.windowBackgroundColor
                let support = contrast(rgb(NSColor(RavenBrand.secondaryText), over: background), rgb(background))
                let primary = contrast(rgb(NSColor(RavenBrand.primaryActionText)), rgb(NSColor(RavenBrand.headphoneAmber)))
                precondition(support >= 4.5, "Supporting text contrast failed: \(support)")
                precondition(primary >= 4.5, "Primary button text contrast failed: \(primary)")
                print("PASS", name.rawValue, "supporting", String(format:"%.2f",support), "primary", String(format:"%.2f",primary))
            }
        }
    }
}
