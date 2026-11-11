import SwiftUI

struct NarrationCleanupControls: View {
    @Bindable var model: NarrationStudioModel
    @State private var advanced = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Magic", systemImage: "wand.and.stars") { model.magicCleanup() }
                    .buttonStyle(.borderedProminent).tint(RavenBrand.headphoneAmber).foregroundStyle(RavenBrand.primaryActionText)
                    .disabled(model.locked || model.roomToneURL == nil)
                Button("Suggest Settings", systemImage: "waveform.path") { model.suggestCleanupSettings() }
                    .disabled(model.locked || model.roomToneURL == nil)
                Menu("Starting Presets") {
                    Button("A · Smoother AC Reduction") { model.cleanupSettings = .referenceA }
                    Button("B · Stronger AC Reduction") { model.cleanupSettings = .referenceB }
                    Button("Gentle") { model.cleanupSettings = .gentle }
                    Button("Fan / AC") { model.cleanupSettings = .fan }
                    Button("Hiss") { model.cleanupSettings = .hiss }
                }.disabled(model.locked)
                Spacer()
                Button("Save Cleanup") { model.applyNoiseCleanup() }.disabled(model.locked || model.edit == nil || model.roomToneURL == nil)
            }
            HStack {
                Button("Undo Control", systemImage: "arrow.uturn.backward") { model.undoCleanupControl() }.disabled(model.locked || model.cleanupControlUndo.isEmpty)
                Button("Redo Control", systemImage: "arrow.uturn.forward") { model.redoCleanupControl() }.disabled(model.locked || model.cleanupControlRedo.isEmpty)
                Text("One knob turn = one undo step").font(.caption).foregroundStyle(.secondary)
            }
            if let choice = model.magicChoice { Text("Magic chose: \(choice)").font(.caption).foregroundStyle(RavenBrand.headphoneAmber) }
            if let analysis = model.noiseAnalysis {
                NoiseProfileChart(spectrum: analysis.spectrum)
                Text(analysis.explanation).font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Sample room noise, then Suggest Settings. Adjust by ear to balance remaining noise and natural speech.").font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 20) {
                CleanupDial(title: "Strength", detail: "Noise sensitivity", value: $model.cleanupSettings.strength, range: 0...8, format: "%.1f strength", resetValue: 2.5, onEditingChanged: model.cleanupEditingChanged)
                CleanupDial(title: "Noise Reduction", detail: "Maximum attenuation", value: $model.cleanupSettings.maximumReductionDB, range: 0...48, format: "%.0f dB", resetValue: 40, onEditingChanged: model.cleanupEditingChanged)
                CleanupDial(title: "Smoothness", detail: "Softer noise residue", value: $model.cleanupSettings.smoothing, range: 0...1, format: "%.2f smoothing", resetValue: 0.5, onEditingChanged: model.cleanupEditingChanged)
            }
            Text("Frequency Focus · 0 = less focus · 1 = normal · 2 = stronger").font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 16) {
                BandDial(title: "Low · Rumble", subtitle: "Below 250 Hz", value: $model.cleanupSettings.low, onEditingChanged: model.cleanupEditingChanged)
                BandDial(title: "Mid · Room / AC", subtitle: "250 Hz–4 kHz", value: $model.cleanupSettings.mid, onEditingChanged: model.cleanupEditingChanged)
                BandDial(title: "High · Hiss", subtitle: "Above 4 kHz", value: $model.cleanupSettings.high, onEditingChanged: model.cleanupEditingChanged)
                VStack(spacing: 3) {
                    Text("Preview Volume").font(.subheadline.bold())
                    Text("Monitor only").font(.caption).foregroundStyle(.secondary)
                    RavenLevelKnob(title: "Preview volume in decibels", value: $model.monitorGainDB, range: -24...18, format: "%+.0f dB", accent: RavenBrand.previewGreen, resetValue: 0, onEditingChanged: model.cleanupEditingChanged)
                }.frame(maxWidth: .infinity)
            }
            DisclosureGroup("Advanced", isExpanded: $advanced) {
                CleanupDial(title: "Processed Mix", detail: "0 = original · 1 = fully processed", value: $model.cleanupSettings.mix, range: 0...1, format: "%.2f", resetValue: 1, onEditingChanged: model.cleanupEditingChanged)
                Text("Frequency controls change noise suppression with smooth crossovers; they do not apply EQ gain. Noise Reduction caps attenuation, while Strength controls the noise estimate used by the processor.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Toggle("Use Cleaned Audio", isOn: Binding(get: { model.edit?.useCleanedAudio == true }, set: { model.toggleCleanup($0) }))
                    .disabled(model.locked || model.edit?.cleanedSourceName == nil)
                Button(model.cleanupPreviewRunning ? "Stop Live Preview" : "Start Live Preview", systemImage: model.cleanupPreviewRunning ? "stop.fill" : "play.fill") { model.toggleLiveCleanupPreview() }
                    .disabled(model.locked || model.edit == nil || model.roomToneURL == nil || model.edit?.outputDuration == 0)
                Toggle("Hear Original", isOn: $model.previewOriginal)
                Button("Reset Volume") { model.monitorGainDB = 0 }
            }
            if model.previewLevelHigh { Text("Preview level is too high · reduce preview volume").font(.caption).foregroundStyle(.red) }
            Text("Volume affects monitoring only. Live cleanup preview loops the edit and bypasses AU effects. Save Cleanup stores a processed version; normal playback/export also render pending cleanup settings when Use Cleaned Audio is selected.")
                .font(.caption).foregroundStyle(.secondary)
            if model.cleanupNeedsRender {
                Text("Settings not saved · live preview uses these controls").font(.caption).foregroundStyle(.orange)
            }
        }.disabled(model.locked)
    }
}
private struct CleanupDial: View {
    let title: String
    let detail: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    var resetValue: Double? = nil
    var onEditingChanged: ((Bool) -> Void)? = nil
    var body: some View {
        VStack(spacing: 3) {
            Text(title).font(.subheadline.bold())
            Text(detail).font(.caption).foregroundStyle(.secondary)
            RavenLevelKnob(title: title, value: $value, range: range, format: format, resetValue: resetValue, onEditingChanged: onEditingChanged)
        }.frame(maxWidth: .infinity)
    }
}
private struct BandDial: View {
    let title: String
    let subtitle: String
    @Binding var value: Double
    var onEditingChanged: ((Bool) -> Void)? = nil
    var body: some View {
        VStack(spacing: 3) {
            Text(title).font(.subheadline.bold())
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
            RavenLevelKnob(title: title, value: $value, range: 0...2, format: "%.2f× focus", accent: .blue, resetValue: 1, onEditingChanged: onEditingChanged)
        }.frame(maxWidth: .infinity)
    }
}
private struct NoiseProfileChart: View {
    let spectrum: [Double]
    var body: some View {
        VStack(spacing: 4) {
            Text("Captured Noise · Relative Spectrum").font(.caption)
            Canvas { context, size in
                guard !spectrum.isEmpty else { return }
                for (index, level) in spectrum.enumerated() {
                    let width = size.width / Double(spectrum.count)
                    let height = max(1, (level + 60) / 60 * size.height)
                    let color: Color = index < 9 ? .blue : index < 18 ? .orange : .purple
                    context.fill(Path(CGRect(x: Double(index) * width, y: size.height - height, width: max(1, width - 2), height: height)), with: .color(color))
                }
            }.frame(height: 55).accessibilityLabel("Noise spectrum from low to high frequencies, relative to the loudest band")
            HStack { Text("20 Hz"); Spacer(); Text("Low → Mid → High"); Spacer(); Text("20 kHz") }.font(.caption2).foregroundStyle(.secondary)
        }.padding(8).background(.quaternary, in: .rect(cornerRadius: 6))
    }
}
