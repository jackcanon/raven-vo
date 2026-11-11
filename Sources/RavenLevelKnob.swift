import SwiftUI
import AppKit

/// The face runs from 0 to 11; the binding retains the parameter's actual units.
struct RavenLevelKnob: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    var accent: Color = RavenBrand.headphoneAmber
    var resetValue: Double? = nil
    var onEditingChanged: ((Bool) -> Void)? = nil
    @State private var dragStart: Double?
    @State private var fineAdjustment = false
    @Environment(\.isEnabled) private var enabled
    private var fraction: Double { min(1, max(0, (value - range.lowerBound) / (range.upperBound - range.lowerBound))) }
    private var angle: Double { -135 + fraction * 270 }
    private func set(_ next: Double) { if enabled && next.isFinite { value = min(range.upperBound, max(range.lowerBound, next)) } }
    private func step(_ direction: Double) {
        set(value + direction * (range.upperBound - range.lowerBound) / ((fineAdjustment || NSEvent.modifierFlags.contains(.shift)) ? 1100 : 110))
    }
    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    for tick in 0...11 {
                        let degrees = -225 + Double(tick) / 11 * 270
                        let radians = degrees * .pi / 180
                        let outer = size.width * 0.45, inner = size.width * 0.40
                        var path = Path()
                        path.move(to: CGPoint(x: center.x + cos(radians) * inner, y: center.y + sin(radians) * inner))
                        path.addLine(to: CGPoint(x: center.x + cos(radians) * outer, y: center.y + sin(radians) * outer))
                        context.stroke(path, with: .color(tick == 11 ? RavenBrand.recordRed : tick <= Int((fraction * 11).rounded(.down)) ? accent : Color.secondary.opacity(0.5)), lineWidth: tick == 11 ? 3 : 2)
                    }
                }
                Circle()
                    .fill(LinearGradient(colors: [Color(white: 0.29), Color(white: 0.09)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay { Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1) }
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
                    .frame(width: 60, height: 60)
                Capsule().fill(accent).frame(width: 3, height: 20).offset(y: -15).rotationEffect(.degrees(angle))
                Text("0").font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary).offset(x: -32, y: 35)
                Text("11").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(RavenBrand.recordRed).offset(x: 31, y: 35)
            }
            .frame(width: 100, height: 94)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    if dragStart == nil { onEditingChanged?(true); dragStart = value }
                    let sensitivity = (fineAdjustment || NSEvent.modifierFlags.contains(.shift)) ? 0.1 : 1.0
                    set((dragStart ?? value) - gesture.translation.height / 160 * (range.upperBound - range.lowerBound) * sensitivity)
                }.onEnded { _ in dragStart = nil; onEditingChanged?(false) })
            .simultaneousGesture(TapGesture(count: 2).onEnded { set(resetValue ?? range.lowerBound) })
            .focusable(enabled)
            .onKeyPress(.upArrow) { step(1); return .handled }
            .onKeyPress(.rightArrow) { step(1); return .handled }
            .onKeyPress(.downArrow) { step(-1); return .handled }
            .onKeyPress(.leftArrow) { step(-1); return .handled }
            .accessibilityRepresentation {
                Slider(value: Binding(get: { value }, set: { set($0) }), in: range)
                    .accessibilityLabel(title).accessibilityValue(String(format: format, value))
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%04.1f", fraction * 11))
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .foregroundStyle(accent)
                Text("/11").font(.system(size: 9, design: .monospaced)).foregroundStyle(.white.opacity(0.55))
            }
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Color(white: 0.055), in: .rect(cornerRadius: 4))
            .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(0.12)) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title) dial position \(String(format: "%.1f", fraction * 11)) out of eleven")
            Text(String(format: format, value)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Button(fineAdjustment ? "Fine: On" : "Fine: Off") { fineAdjustment.toggle() }
                .accessibilityLabel("\(title) fine adjustment")
                .accessibilityValue(fineAdjustment ? "On" : "Off")
            Button("Reset") { set(resetValue ?? range.lowerBound) }
                .accessibilityLabel("Reset \(title)")
        }
        .opacity(enabled ? 1 : 0.45)
        .buttonStyle(RavenTouchButtonStyle())
        .help("Drag up or down. Tap Fine for precise touch adjustment; tap Reset to restore the default. Shift-drag for fine adjustment. Arrow keys adjust; Shift makes finer steps. Double-click to reset. The 0–11 scale maps to the actual value shown below.")
    }
}

/// Shared studio actions remain finger-sized without relying on hover or a keyboard.
struct RavenTouchButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .frame(minWidth: 44, minHeight: 44)
            .background(Color.primary.opacity(configuration.isPressed ? 0.16 : 0.07), in: .rect(cornerRadius: 8))
            .contentShape(Rectangle())
            .opacity(enabled ? 1 : 0.45)
    }
}
