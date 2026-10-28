import SwiftUI

struct AudioTransportView: View {
    let waveform: WaveformModel
    let position: Double
    let duration: Double
    let isPlaying: Bool
    let disabled: Bool
    let volume: Double
    let playPause: @MainActor @Sendable () -> Void
    let seek: @MainActor @Sendable (Double) -> Void
    let setVolume: @MainActor @Sendable (Double) -> Void
    private var fraction: Double { duration > 0 ? min(1, max(0, position / duration)) : 0 }
    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                Canvas { context, size in
                    guard !waveform.peaks.isEmpty else {
                        var line = Path(); line.move(to: CGPoint(x: 0, y: size.height / 2)); line.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                        context.stroke(line, with: .color(.secondary), lineWidth: 1)
                        return
                    }
                    let count = min(waveform.peaks.count, max(1, Int(size.width / 3)))
                    let stride = size.width / CGFloat(count)
                    var played = Path(), upcoming = Path()
                    for index in 0..<count {
                        let first = index * waveform.peaks.count / count
                        let last = max(first + 1, (index + 1) * waveform.peaks.count / count)
                        let peak = waveform.peaks[first..<last].max() ?? 0
                        let height = max(2, CGFloat(sqrt(peak)) * (size.height - 8))
                        let rect = CGRect(x: CGFloat(index) * stride, y: (size.height - height) / 2, width: max(1, stride - 1), height: height)
                        if Double(index) / Double(count) < fraction { played.addRoundedRect(in: rect, cornerSize: CGSize(width: 1, height: 1)) }
                        else { upcoming.addRoundedRect(in: rect, cornerSize: CGSize(width: 1, height: 1)) }
                    }
                    context.fill(upcoming, with: .color(.primary.opacity(0.5)))
                    context.fill(played, with: .color(.primary))
                    let x = size.width * fraction
                    var cursor = Path(); cursor.move(to: CGPoint(x: x, y: 0)); cursor.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(cursor, with: .color(.primary), lineWidth: 2)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    guard !disabled, duration > 0, geometry.size.width > 0 else { return }
                    seek(min(1, max(0, value.location.x / geometry.size.width)) * duration)
                })
            }.frame(height: 64).accessibilityHidden(true)
                .overlay { if waveform.loading { ProgressView("Loading waveform…").controlSize(.small) } }
            Slider(value: Binding(get: { position }, set: seek), in: 0...max(duration, 0.01))
                .accessibilityLabel("Playback position")
                .accessibilityValue("\(clock(position)) of \(clock(duration))")
                .disabled(disabled || duration == 0)
            HStack(spacing: 14) {
                Text(clock(position)).monospacedDigit().font(.caption).frame(width: 45, alignment: .leading)
                Spacer()
                Button { seek(max(0, position - 5)) } label: { Image(systemName: "gobackward.5") }
                    .accessibilityLabel("Skip back five seconds").help("Back 5 seconds")
                Button(action: playPause) { Image(systemName: isPlaying ? "pause.fill" : "play.fill").font(.title3).frame(width: 30, height: 26) }
                    .accessibilityLabel(isPlaying ? "Pause audio" : "Play audio").help(isPlaying ? "Pause" : "Play")
                Button { seek(min(duration, position + 5)) } label: { Image(systemName: "goforward.5") }
                    .accessibilityLabel("Skip forward five seconds").help("Forward 5 seconds")
                Spacer()
                Image(systemName: "speaker.wave.2").accessibilityHidden(true)
                Slider(value: Binding(get: { volume }, set: setVolume), in: 0...1)
                    .frame(width: 85).accessibilityLabel("Playback volume")
                Text("−" + clock(max(0, duration - position))).monospacedDigit().font(.caption).frame(width: 52, alignment: .trailing)
                    .accessibilityLabel("\(clock(max(0, duration - position))) remaining")
            }.buttonStyle(.borderless).disabled(disabled || duration == 0)
            if let error = waveform.error { Text(error).font(.caption).foregroundStyle(RavenBrand.secondaryText) }
        }
    }
    private func clock(_ seconds: Double) -> String {
        let value = seconds.isFinite ? Int(max(0, seconds)) : 0
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
