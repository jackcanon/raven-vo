import SwiftUI
import AppKit
import UniformTypeIdentifiers

private struct PrompterHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
struct NarrationTeleprompterView: View {
    @Bindable var model: NarrationStudioModel
    @State private var editing = false
    @State private var fontSize = 44.0
    @State private var speed = 30.0
    @State private var mirrored = false
    @State private var autoScrollOnRecord = true
    @State private var scrolling = false
    @State private var started = Date()
    @State private var savedOffset = 0.0
    @State private var textHeight = 0.0
    @State private var viewportHeight = 0.0
    private var maximumOffset: Double { max(0, textHeight - viewportHeight + 100) }
    private func offset(at date: Date) -> Double {
        min(maximumOffset, max(0, savedOffset + (scrolling ? date.timeIntervalSince(started) * speed : 0)))
    }
    private func pause() { savedOffset = offset(at: Date()); scrolling = false }
    private func start() { started = Date(); scrolling = true }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Teleprompter").font(.title2.bold())
                Spacer()
                Toggle("Edit Script", isOn: $editing).disabled(model.recording || model.busy || model.finishing)
                Button("Import Text…") { importText() }.disabled(model.locked)
                Button(model.recording ? "Stop Recording" : model.recordTakeLabel, systemImage: model.recording ? "stop.circle.fill" : "record.circle") {
                    if model.recording { model.stopRecording() } else { model.savePromptScript(); model.startRecording() }
                }.disabled(model.busy || model.finishing || model.effects.loading || model.samplingRoom)
            }
            if !model.takes.isEmpty { NarrationTakesView(model: model) }
            HStack {
                Slider(value: $fontSize, in: 24...80) { Text("Text Size") }.frame(maxWidth: 280)
                    .onChange(of: fontSize) { pause() }
                Slider(value: $speed, in: 10...100) { Text("Scroll Speed") }.frame(maxWidth: 280)
                    .onChange(of: speed) { old, _ in
                        if scrolling { savedOffset = min(maximumOffset, savedOffset + Date().timeIntervalSince(started) * old); started = Date() }
                    }
                Toggle("Mirror", isOn: $mirrored)
                Toggle("Scroll on Record", isOn: $autoScrollOnRecord)
            }
            if editing || model.promptScript.isEmpty {
                VStack(alignment: .leading) {
                    Text("Paste or type the words you want to read. Script changes do not change recorded audio.").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $model.promptScript).font(.system(size: 22)).accessibilityLabel("Teleprompter script")
                        .disabled(model.recording || model.busy || model.finishing)
                    Button("Save and Read") { model.savePromptScript(); editing = false; savedOffset = 0 }
                        .disabled(model.promptScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.locked)
                }
            } else {
                GeometryReader { geometry in
                    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !scrolling)) { timeline in
                        Text(model.promptScript)
                            .font(.system(size: fontSize, weight: .medium))
                            .lineSpacing(fontSize * 0.4)
                            .foregroundStyle(.white)
                            .frame(width: max(100, geometry.size.width - 100), alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .background { GeometryReader { proxy in Color.clear.preference(key: PrompterHeightKey.self, value: proxy.size.height) } }
                            .padding(.horizontal, 50).padding(.top, 70)
                            .offset(y: -offset(at: timeline.date))
                            .scaleEffect(x: mirrored ? -1 : 1, y: 1, anchor: .center)
                            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                            .clipped()
                            .background(.black)
                    }
                    .overlay(alignment: .leading) { Image(systemName: "arrowtriangle.right.fill").foregroundStyle(.yellow).padding(.leading, 12).offset(y: -geometry.size.height / 2 + 95).accessibilityHidden(true) }
                    .onAppear { viewportHeight = geometry.size.height }
                    .onChange(of: geometry.size.height) { _, value in viewportHeight = value }
                }
                .onPreferenceChange(PrompterHeightKey.self) { textHeight = $0 }
                .clipShape(.rect(cornerRadius: 8))
                HStack {
                    Button(scrolling ? "Pause Scroll" : "Start Scroll", systemImage: scrolling ? "pause.fill" : "play.fill") { if scrolling { pause() } else { start() } }
                    Button("Back to Start") { pause(); savedOffset = 0 }
                    Slider(value: Binding(get: { offset(at: Date()) }, set: { pause(); savedOffset = $0 }), in: 0...max(1, maximumOffset)).accessibilityLabel("Script position")
                }
            }
            HStack {
                if model.recording { Image(systemName: "record.circle.fill").foregroundStyle(.red); Text(String(format: "Recording %.1f s · %.0f dBFS", model.recordedSeconds, model.level)).monospacedDigit() }
                Text(model.appleTranscriptionEnabled ? "Apple transcription enabled in background" : "Apple transcription off").font(.caption).foregroundStyle(.secondary)
            }
            Text(model.status).font(.callout).textSelection(.enabled)
        }
        .padding(20).frame(minWidth: 800, minHeight: 560)
        .onAppear { if model.promptScript.isEmpty { editing = true } }
        .onChange(of: model.recording) { _, recording in
            if recording && !model.samplingRoom && autoScrollOnRecord { editing = false; savedOffset = 0; start() }
            else if !recording { pause() }
        }
        .onDisappear { pause(); model.savePromptScript() }
    }
    private func importText() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { model.promptScript = try String(contentsOf: url, encoding: .utf8); pause(); savedOffset = 0; model.savePromptScript() }
        catch { model.status = "Could not open script: \(error.localizedDescription)" }
    }
}
