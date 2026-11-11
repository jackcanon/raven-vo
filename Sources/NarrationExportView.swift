import SwiftUI

struct NarrationExportView: View {
    @Bindable var model: NarrationStudioModel
    let close: () -> Void
    private var scale: Double {
        guard let levels = model.exportLevels else { return 1 }
        return (try? NarrationExport.gain(levels: levels, gainDB: model.exportGainDB, ceiling: model.exportCeiling)) ?? 1
    }
    private var clips: Bool { (model.exportLevels?.peak ?? 0) * scale >= 1 }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Export Voice-over").font(.title2.bold()); Spacer(); Button("Done", action: close).disabled(model.busy) }
            Text(model.exportSummary).font(.callout)
            if let levels = model.exportLevels {
                Text(String(format: "%.3f seconds · %.0f Hz · %d channel(s)", Double(levels.frames) / levels.sampleRate, levels.sampleRate, levels.channels)).monospacedDigit()
                Picker("WAV format", selection: $model.exportEncoding) {
                    ForEach(NarrationExportEncoding.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                HStack {
                    Text("Output Gain")
                    Slider(value: $model.exportGainDB, in: -24...12, step: 0.1).accessibilityLabel("Export output gain in decibels").frame(minHeight: 44)
                    Text(String(format: "%+.1f dB", model.exportGainDB)).monospacedDigit().frame(width: 75)
                    Button("Reset") { model.exportGainDB = 0 }
                }
                Toggle("Keep sample peaks at or below −1 dBFS", isOn: $model.exportCeiling).toggleStyle(.switch).frame(minHeight: 44)
                Text("The peak ceiling reduces the whole file's gain when needed. It does not compress or raise quiet audio.").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 24) {
                    Text(String(format: "Output sample peak: %.1f dBFS", levels.peak > 0 ? levels.peakDB + 20 * log10(scale) : -Double.infinity))
                    Text(String(format: "Average RMS: %.1f dBFS", levels.rms > 0 ? levels.rmsDB + 20 * log10(scale) : -Double.infinity))
                }.font(.callout.monospacedDigit())
                if clips { Text(model.exportEncoding == .float32 ? "Samples reach or exceed 0 dBFS. Float preserves them, but playback or conversion may clip." : "PCM would clip. Lower gain or turn on the peak ceiling.").foregroundStyle(.orange) }
                Text("Sample peak and RMS are measured after edits, cleanup and AU effects. They are not true-peak or LUFS measurements. Preview Volume and Hear Original do not change this export.").font(.caption).foregroundStyle(.secondary)
                Button("Save WAV…") { model.exportAudio() }.disabled(model.busy || (clips && model.exportEncoding != .float32))
            } else if model.busy {
                ProgressView("Rendering effects and measuring levels…")
            } else {
                Button("Retry Preparation") { model.prepareExport() }
            }
            Text(model.status).font(.callout).textSelection(.enabled)
        }
        .disabled(model.busy && model.exportLevels != nil)
        .buttonStyle(RavenTouchButtonStyle())
        .padding(24).frame(width: 680)
        .interactiveDismissDisabled(model.busy)
    }
}
