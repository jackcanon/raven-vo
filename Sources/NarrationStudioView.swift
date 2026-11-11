import SwiftUI
import AppKit

struct NarrationStudioView: View {
    @Environment(\.openWindow) private var openWindow
    @Bindable var model: NarrationStudioModel
    @State private var showProcessing = false
    @State private var showRecovery = false
    @State private var showExport = false
    @State private var extendSelection = false
    @State private var correction: NarrationWord?
    @State private var correctedText = ""
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Voice-over Studio").font(.title2.bold())
                Spacer()
                Button("Teleprompter…") { openWindow(id: "prompter") }
                Button("Open Project…") { model.openProject() }.disabled(model.locked)
                Button("Import Audio…") { model.importAudio() }.disabled(model.locked)
                Button("Recover Takes…") { model.findInterruptedRecordings(); showRecovery = true }.disabled(model.locked)
                Button("Save") { model.save() }.disabled(model.edit == nil || model.locked)
            }
            HStack(alignment: .top) {
                if !model.takes.isEmpty { NarrationTakesView(model: model) }
                Spacer()
                Button("New Script…") { if model.newScript() { openWindow(id: "prompter") } }.disabled(model.locked)
            }
            HStack {
                Picker("Microphone", selection: $model.deviceID) {
                    Text("System default").tag("")
                    ForEach(model.devices) { Text($0.name).tag($0.id) }
                }.frame(maxWidth: 380).disabled(model.locked)
                Button("Refresh Inputs", systemImage: "arrow.clockwise") { model.devices = MicrophoneCapture.choices() }.labelStyle(.iconOnly).disabled(model.locked)
                Button(model.recording ? "Stop Recording" : model.recordTakeLabel, systemImage: model.recording ? "stop.circle.fill" : "record.circle") {
                    if model.recording { model.stopRecording() } else { model.startRecording() }
                }.disabled(model.busy || model.finishing)
                if model.recording {
                    ProgressView(value: max(0, min(1, (model.level + 60) / 60))).frame(width: 100).accessibilityLabel("Microphone level")
                    Text(String(format: "%.1f s · %.0f dBFS", model.recordedSeconds, model.level)).monospacedDigit()
                }
            }
            HStack {
                Picker("Language", selection: $model.localeID) {
                    Text("English (US)").tag("en-US")
                    Text("English (UK)").tag("en-GB")
                    Text("Spanish").tag("es-ES")
                    Text("French").tag("fr-FR")
                    Text("German").tag("de-DE")
                    Text("Japanese").tag("ja-JP")
                    Text("Korean").tag("ko-KR")
                    Text("Chinese (Mandarin)").tag("zh-CN")
                }.frame(maxWidth: 300)
                Toggle("Apple Transcription", isOn: $model.appleTranscriptionEnabled).toggleStyle(.checkbox).disabled(model.locked)
                if model.appleTranscriptionEnabled, model.edit != nil {
                    Button("Transcribe Recording") { model.transcribe() }.disabled(model.locked)
                }
                if model.busy { ProgressView().controlSize(.small) }
                Spacer()
                Text("Background during recording · macOS 26+").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Cleanup and Audio Unit Effects…", systemImage: "slider.horizontal.3") { showProcessing = true }
                Text("\(model.effects.plugins.count) AU effects · \(model.edit?.useCleanedAudio == true ? "Cleaned audio" : "Original audio")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Text("Transcript").font(.headline)
                Toggle("Extend Selection", isOn: $extendSelection).toggleStyle(.switch)
                    .frame(minHeight: 44)
            }
            Text("Tap a word to select its audio. Turn on Extend Selection, then tap the last word to select a passage. Correct Text changes spelling; Cut Selection removes audio.")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), alignment: .leading)], alignment: .leading, spacing: 8) {
                    ForEach(model.edit?.words ?? []) { word in
                        let retained = model.edit?.contains(word) == true
                        let selected = model.selection.map { word.start < $0.end && word.end > $0.start } ?? false
                        let active = model.playing && model.playhead >= word.start && model.playhead < word.end
                        Button {
                            model.selectWord(word, extending: extendSelection || NSEvent.modifierFlags.contains(.shift))
                        } label: {
                            Text(word.text).strikethrough(!retained)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.horizontal, 6)
                                .background(active ? Color.green.opacity(0.3) : selected ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.08), in: .rect(cornerRadius: 5))
                                .opacity(retained ? 1 : 0.45)
                        }.buttonStyle(.plain).disabled(model.locked)
                            .accessibilityLabel("\(word.text), \(String(format: "%.2f", word.start)) seconds\(retained ? "" : ", cut")")
                            .contextMenu {
                                Button("Correct Text…") { correction = word; correctedText = word.text }
                            }
                    }
                }.padding(4)
                if model.edit?.words.isEmpty != false {
                    Text("Your timed transcript will appear here after transcription.").foregroundStyle(.secondary).padding(24)
                }
            }.frame(height: 180)
            HStack {
                Text(model.edit?.useCleanedAudio == true ? "Waveform · cleaned recording" : "Waveform · original recording").font(.headline)
                Spacer()
                if let edit = model.edit { Text(String(format: "Original %.2f s · Edited %.2f s", edit.duration, edit.outputDuration)).monospacedDigit() }
            }
            if let duration = model.edit?.duration {
                HStack {
                    Text("0.00 s")
                    Spacer()
                    Text(String(format: "%.2f s", duration / 2))
                    Spacer()
                    Text(String(format: "%.2f s", duration))
                }.font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            HStack {
                Picker("Edit Join Crossfade", selection: Binding(get: { model.edit?.joinCrossfadeMS ?? 0 }, set: { model.setJoinCrossfade($0) })) {
                    Text("Off").tag(0.0)
                    ForEach([3.0, 5.0, 10.0, 20.0], id: \.self) { Text("\(Int($0)) ms").tag($0) }
                }.pickerStyle(.segmented).frame(maxWidth: 480)
                    .disabled(model.locked || model.edit == nil)
                Text("Short overlaps soften cuts · Undo restores changes").font(.caption).foregroundStyle(.secondary)
            }
            NarrationWaveformView(model: model)
            HStack {
                Button(model.playing ? "Stop" : "Play Edit", systemImage: model.playing ? "stop.fill" : "play.fill") { model.play() }
                    .disabled(model.edit == nil || model.locked || model.edit?.outputDuration == 0)
                Button("Cut Selection", systemImage: "scissors") { model.cutSelection() }.disabled(model.selection == nil || model.locked)
                Button("Clear Selection") { model.selection = nil }.disabled(model.selection == nil || model.locked)
                Button("Undo") { model.undo() }.disabled(model.history.isEmpty || model.locked)
                Button("Redo") { model.redo() }.disabled(model.future.isEmpty || model.locked)
                Spacer()
                Button("Export WAV…") { showExport = true; model.prepareExport() }.disabled(model.edit == nil || model.locked || model.edit?.outputDuration == 0)
            }
            if let selection = model.selection {
                Text(String(format: "Selected source audio: %.3f–%.3f s", selection.start, selection.end)).font(.caption).monospacedDigit()
            }
            if let warning = model.recordingWarning { Text(warning).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
            Text(model.status).font(.callout).textSelection(.enabled).accessibilityIdentifier("studioStatus")
            Text("Cuts are non-destructive. Shaded regions are cut from playback and export. Struck-through words overlap a cut. Drag to select audio; click to seek.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        }
        .buttonStyle(RavenTouchButtonStyle())
        .frame(minWidth: 900, minHeight: 760)
        .onAppear {
            if model.edit == nil, let index = CommandLine.arguments.firstIndex(of: "--studio-project"), CommandLine.arguments.count > index + 1 {
                model.openProject(at: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            }
        }
        .sheet(isPresented: $showExport, onDismiss: { model.clearPreparedExport() }) {
            NarrationExportView(model: model) { showExport = false }
        }
        .sheet(isPresented: $showRecovery) {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Text("Interrupted Recordings").font(.headline); Spacer(); Button("Done") { showRecovery = false } }
                Text("Recover a readable take into a new project. Originals stay intact. A file that was never finalized may be unreadable; recovery does not repair damaged WAV files.").font(.callout)
                if model.pendingRecordings.isEmpty { Text("No interrupted recordings found in the selected studio storage.") }
                ScrollView {
                    ForEach(model.pendingRecordings) { item in
                        HStack {
                            VStack(alignment: .leading) { Text(item.started.formatted()); Text(item.deviceName).foregroundStyle(.secondary) }
                            Spacer()
                            Button("Recover") { model.recoverRecording(item) }.disabled(model.locked)
                        }.padding(.vertical, 8)
                    }
                }.frame(maxHeight: 240)
                Text(model.status).font(.callout).textSelection(.enabled)
            }.buttonStyle(RavenTouchButtonStyle()).padding(24).frame(width: 640)
        }
        .sheet(isPresented: $showProcessing) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Cleanup and Audio Unit Effects").font(.headline)
                    Spacer()
                    Button("Done") { showProcessing = false }.keyboardShortcut(.defaultAction)
                }
                ScrollView { NarrationProcessingView(model: model) }.frame(maxHeight: 620)
                Text(model.status).font(.callout).textSelection(.enabled)
            }.buttonStyle(RavenTouchButtonStyle()).padding(24).frame(width: 800)
        }
        .sheet(item: $correction) { word in
            VStack(alignment: .leading, spacing: 16) {
                Text("Correct transcription text").font(.headline)
                TextField("Text", text: $correctedText)
                Text("This changes the transcript label. The recorded speech stays the same.").font(.caption)
                HStack {
                    Button("Cancel") { correction = nil }
                    Button("Save Correction") { model.correctWord(id: word.id, text: correctedText); correction = nil }.disabled(correctedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(24).frame(width: 420)
        }
    }
}

private struct NarrationWaveformView: View {
    @Bindable var model: NarrationStudioModel
    @State private var zoom = 1.0
    @State private var center = 0.0
    @State private var detail = WaveformModel()
    @State private var adjustEnd = false
    @State private var nudge = 0.01
    private var duration: Double { max(0.001, model.edit?.duration ?? 1) }
    private var span: Double { duration / zoom }
    private var start: Double { max(0, min(duration - span, center - span / 2)) }
    private var end: Double { start + span }
    private func changeZoom(_ next: Double) {
        center = min(duration, max(0, model.selection.map { ($0.start + $0.end) / 2 } ?? model.playhead))
        zoom = max(1, min(64, next))
    }
    private func setBoundary(_ value: Double, endBoundary: Bool) {
        guard !model.locked, value.isFinite, let selected = model.selection else { return }
        let limit = min(duration, max(0, value))
        let next = endBoundary ? NarrationRange(start: selected.start, end: max(selected.start + 0.0001, limit)) : NarrationRange(start: min(selected.end - 0.0001, limit), end: selected.end)
        guard next.start >= 0, next.end <= duration else { return }
        model.selection = next; model.seek(next.start)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button("Zoom In", systemImage: "plus.magnifyingglass") { changeZoom(zoom * 2) }.disabled(zoom >= 64)
                Button("Zoom Out", systemImage: "minus.magnifyingglass") { changeZoom(zoom / 2) }.disabled(zoom <= 1)
                Button("Fit All") { zoom = 1; center = duration / 2 }
                Button("Fit Selection") {
                    guard let selected = model.selection else { return }
                    changeZoom(duration / max(0.001, selected.duration * 1.3))
                }.disabled(model.selection == nil)
                Text(String(format: "%.0f× · %.3f–%.3f s", zoom, start, end)).font(.caption.monospacedDigit())
            }
            GeometryReader { geometry in
                Canvas { context, size in
                    func x(_ time: Double) -> Double { (time - start) / span * size.width }
                    let peaks = detail.peaks
                    for (index, peak) in peaks.enumerated() {
                        let position = Double(index) / Double(max(1, peaks.count)) * size.width
                        let height = max(1, Double(peak) * (size.height - 12))
                        context.fill(Path(CGRect(x: position, y: (size.height - height) / 2, width: max(1, size.width / Double(max(1, peaks.count))), height: height)), with: .color(.accentColor))
                    }
                    var previous = 0.0
                    for range in (model.edit?.kept ?? []) + [.init(start: duration, end: duration)] {
                        let a = max(start, previous), b = min(end, range.start)
                        if b > a { context.fill(Path(CGRect(x: x(a), y: 0, width: x(b) - x(a), height: size.height)), with: .color(.black.opacity(0.65))) }
                        previous = range.end
                    }
                    if let selection = model.selection {
                        let a = max(start, selection.start), b = min(end, selection.end)
                        if b > a { context.fill(Path(CGRect(x: x(a), y: 0, width: x(b) - x(a), height: size.height)), with: .color(.yellow.opacity(0.3))) }
                    }
                    if (start...end).contains(model.playhead) { context.fill(Path(CGRect(x: x(model.playhead), y: 0, width: 2, height: size.height)), with: .color(.green)) }
                }
                .background(Color.secondary.opacity(0.12), in: .rect(cornerRadius: 6))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                    guard !model.locked else { return }
                    let first = max(start, min(end, start + value.startLocation.x / max(1, geometry.size.width) * span))
                    let last = max(start, min(end, start + value.location.x / max(1, geometry.size.width) * span))
                    if abs(value.translation.width) < 3 { model.seek(last); model.selection = nil }
                    else { model.selection = .init(start: min(first, last), end: max(first, last)); model.seek(min(first, last)) }
                })
                .accessibilityLabel("Source waveform. Zoom and use selection boundary controls for precise editing.")
            }.frame(height: 100)
            if detail.loading { Text("Loading waveform detail…").font(.caption) }
            if let error = detail.error { Text(error).font(.caption).foregroundStyle(.secondary) }
            if zoom > 1 {
                HStack {
                    Button("Earlier", systemImage: "chevron.left") { center = max(span / 2, start + span / 2 - span / 2) }
                    Slider(value: Binding(get: { start + span / 2 }, set: { center = $0 }), in: (span / 2)...(duration - span / 2))
                        .accessibilityLabel("Visible waveform center").frame(minHeight: 44)
                    Button("Later", systemImage: "chevron.right") { center = min(duration - span / 2, start + span) }
                }
            }
            Slider(value: Binding(get: { min(duration, max(0, model.playhead)) }, set: { model.seek($0) }), in: 0...duration)
                .accessibilityLabel("Source audio position").frame(minHeight: 44)
            if let selected = model.selection {
                HStack {
                    TextField("Start seconds", value: Binding(get: { model.selection?.start ?? 0 }, set: { setBoundary($0, endBoundary: false) }), format: .number.precision(.fractionLength(3)))
                        .frame(width: 100, height: 44).textFieldStyle(.roundedBorder).accessibilityLabel("Selection start seconds")
                    TextField("End seconds", value: Binding(get: { model.selection?.end ?? 0 }, set: { setBoundary($0, endBoundary: true) }), format: .number.precision(.fractionLength(3)))
                        .frame(width: 100, height: 44).textFieldStyle(.roundedBorder).accessibilityLabel("Selection end seconds")
                    Picker("Adjust", selection: $adjustEnd) { Text("Start").tag(false); Text("End").tag(true) }.frame(width: 140)
                    Picker("Step", selection: $nudge) { Text("1 ms").tag(0.001); Text("10 ms").tag(0.01); Text("100 ms").tag(0.1) }.frame(width: 130)
                    Button("−") { setBoundary((adjustEnd ? selected.end : selected.start) - nudge, endBoundary: adjustEnd) }.accessibilityLabel("Move selected boundary earlier")
                    Button("+") { setBoundary((adjustEnd ? selected.end : selected.start) + nudge, endBoundary: adjustEnd) }.accessibilityLabel("Move selected boundary later")
                }
            }
        }
        .disabled(model.locked || model.edit == nil)
        .onChange(of: model.source) { _, _ in zoom = 1; center = 0 }
        .task(id: "\(model.source?.path ?? "")|\(start)|\(end)") {
            detail.load(model.source, start: start, end: end, bins: 1200)
        }
    }
}
