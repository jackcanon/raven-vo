import SwiftUI

struct ContentView: View {
    @Bindable var model: StudioModel
    @State private var showDetails = false
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Label("Your takes", systemImage: "waveform")
                        .font(.headline)
                    Spacer()
                    Button { model.reloadTakes() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless).help("Refresh recordings")
                        .accessibilityLabel("Refresh recordings").keyboardShortcut("r", modifiers: .command)
                }.padding()
                if model.takes.isEmpty {
                    ContentUnavailableView("No takes yet", systemImage: "waveform", description: Text("Your generated voice-overs appear here."))
                } else {
                    List(selection: Binding(get: { model.selectedID }, set: { model.select($0) })) {
                        ForEach(model.takes) { take in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(take.title).font(.headline).lineLimit(2)
                                Text(take.detail).font(.caption).foregroundStyle(model.selectedID == take.id ? Color.primary : RavenBrand.secondaryText)
                                Text(take.created, format: .dateTime.month(.abbreviated).day().hour().minute())
                                    .font(.caption).foregroundStyle(model.selectedID == take.id ? Color.primary : RavenBrand.secondaryText)
                            }.padding(.vertical, 5).accessibilityElement(children: .combine).tag(take.id)
                        }
                    }.listStyle(.sidebar)
                }
                Button { NSWorkspace.shared.open(model.samples) } label: {
                    Label("Open recordings folder", systemImage: "folder")
                }.buttonStyle(.borderless).padding().disabled(!model.available)
            }
            .navigationSplitViewColumnWidth(min: 230, ideal: 260, max: 330)
        } detail: {
            ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HeaderView(model: model)
                StorageSetupView(model: model)
                HStack(alignment: .top, spacing: 24) {
                    VoiceSettings(model: model).frame(width: 235)
                    ScriptEditor(model: model)
                }.frame(height: 380)
                GenerationBar(model: model)
                if let error = model.errorMessage {
                    HStack(alignment: .top) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(error).textSelection(.enabled)
                        Spacer()
                        Button { model.errorMessage = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("Dismiss message").accessibilityLabel("Dismiss error message")
                    }.font(.callout).padding(12).background(.orange.opacity(0.08), in: .rect(cornerRadius: 10))
                }
                Divider()
                PlaybackView(model: model)
                DisclosureGroup("Generation details", isExpanded: $showDetails) {
                    ScrollView {
                        Text(model.logTail.isEmpty ? "The engine log will appear here when you generate a take." : model.logTail)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(height: 110).padding(8).background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 8))
                }.font(.caption).foregroundStyle(RavenBrand.secondaryText)
            }
            .padding(26)
            .frame(minWidth: 690, maxWidth: .infinity, alignment: .topLeading)
            }
            .navigationTitle("Raven VO")
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 990, minHeight: 690)
        .onChange(of: model.draft) { model.scheduleSave() }
        .onChange(of: model.isGenerating) { wasGenerating, isGenerating in
            if wasGenerating && !isGenerating && model.errorMessage == nil { AccessibilityAnnouncement.post(model.status) }
        }
        .onChange(of: model.errorMessage) { _, message in
            if let message { AccessibilityAnnouncement.post(message) }
        }
        .task {
            while !Task.isCancelled {
                model.refreshAvailability()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
}
private struct HeaderView: View {
    let model: StudioModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(nsImage: NSImage(contentsOf: Bundle.main.url(forResource: "AppIcon", withExtension: "icns") ?? URL(fileURLWithPath: "/")) ?? NSImage())
                    .resizable().scaledToFit().frame(width: 46, height: 46).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Raven VO").font(.title2.bold())
                    Text("A voice for your story. Created on your Mac.").foregroundStyle(RavenBrand.secondaryText)
                }
                Spacer()
            }
            Label(model.availabilityMessage, systemImage: model.available ? "checkmark.circle.fill" : "externaldrive.badge.exclamationmark")
                .font(.caption).foregroundStyle(RavenBrand.secondaryText)
        }
    }
}
private struct VoiceSettings: View {
    @Bindable var model: StudioModel
    @State private var voiceSearch = ""
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            Text("Language").font(.headline)
            Picker("Language", selection: $model.selectedLanguage) {
                ForEach(SpeechLanguage.all) { language in Text(language.name).tag(language.id) }
            }.labelsHidden()
            Text("Voice").font(.headline)
            if model.selectedLanguage == "zh" {
                TextField("Find a Chinese voice…", text: $voiceSearch).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Find a Chinese voice")
            }
            Picker("Voice", selection: $model.draft.voice) {
                ForEach(Voice.choices(for: model.selectedLanguage).filter { model.selectedLanguage != "zh" || voiceSearch.isEmpty || $0.id == model.draft.voice || $0.name.localizedCaseInsensitiveContains(voiceSearch) || $0.detail.localizedCaseInsensitiveContains(voiceSearch) }) { voice in Text(voice.name).tag(voice.id) }
            }.labelsHidden()
            Text(Voice.all.first(where: { $0.id == model.draft.voice })?.detail ?? "Choose a voice")
                .lineLimit(4)
                .font(.caption).foregroundStyle(RavenBrand.secondaryText)
            if model.draft.voice == "designed" {
                Text("Describe the delivery").font(.subheadline.bold())
                TextEditor(text: $model.draft.style)
                    .font(.body).scrollContentBackground(.hidden).padding(6)
                    .frame(height: 145).background(.background, in: .rect(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
                    .accessibilityLabel("Voice description")
                Text("Describe age, tone, accent, and pace. Each take may vary.")
                    .font(.caption).foregroundStyle(RavenBrand.secondaryText)
            } else {
                Label(model.draft.voice == "natural" ? "Automatic voice" : "Named preset voice", systemImage: "person.wave.2")
                    .font(.caption).foregroundStyle(RavenBrand.secondaryText)
                Text("For a particular mood or delivery, choose Voice Design.")
                    .font(.caption).foregroundStyle(RavenBrand.secondaryText)
            }
            Text("Write your script in the selected language. Text is spoken as written, without translation.").font(.caption).foregroundStyle(RavenBrand.secondaryText)
            Divider()
            Text("\(SpeechLanguage.all.first { $0.id == model.selectedLanguage }?.name ?? "English") · WAV audio").font(.caption.bold())
            Text("Saved to your chosen folder. Longer scripts are split into chunks automatically.")
                .font(.caption).foregroundStyle(RavenBrand.secondaryText)
        }.frame(maxWidth: .infinity, alignment: .leading)
        }.disabled(model.isGenerating)
    }
}
private struct ScriptEditor: View {
    @Bindable var model: StudioModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Script").font(.headline)
                Spacer()
                Text("\(model.draft.script.count.formatted()) characters").font(.caption).foregroundStyle(RavenBrand.secondaryText)
            }
            TextField("Take title", text: $model.draft.title)
                .textFieldStyle(.roundedBorder).accessibilityLabel("Take title")
            TextEditor(text: $model.draft.script)
                .font(.body).scrollContentBackground(.hidden)
                .padding(10).frame(minHeight: 180, idealHeight: 250, maxHeight: .infinity)
                .background(.background, in: .rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
                .accessibilityLabel("Voice-over script")
            HStack {
                Text(model.draftStatus).font(.caption).foregroundStyle(RavenBrand.secondaryText)
                Spacer()
                if model.draft.script.isEmpty {
                    Button("Try a sample script") {
                        model.draft.title = "Happy Jack Media"
                        model.draft.script = SpeechLanguage.sample(for: model.selectedLanguage)
                    }.buttonStyle(.borderless)
                }
            }
        }
    }
}
private struct GenerationBar: View {
    let model: StudioModel
    var body: some View {
        HStack(spacing: 12) {
            if model.isGenerating {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.status).font(.callout)
                    Text("\(Int(model.elapsed))s elapsed · Timing varies with script length")
                        .font(.caption).foregroundStyle(RavenBrand.secondaryText)
                }
                Spacer()
                Button("Cancel") { model.cancel() }.accessibilityIdentifier("cancel-generation")
            } else {
                Text(model.canGenerate ? model.status : "Enter script text to enable generation. Voice Design also needs a voice description.")
                    .font(.callout).foregroundStyle(RavenBrand.secondaryText)
                Spacer()
                Button { model.generate() } label: {
                    Label("Generate voice-over", systemImage: "waveform.badge.plus")
                }.buttonStyle(RavenPrimaryButtonStyle()).controlSize(.large)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(!model.canGenerate).accessibilityIdentifier("generate-voiceover")
                    .accessibilityHint("Generates a WAV recording locally from the script and selected voice.")
            }
        }.frame(minHeight: 46)
    }
}
private struct PlaybackView: View {
    let model: StudioModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(model.selected?.title ?? "Listen to a take").font(.headline).lineLimit(1)
                Spacer()
                Button("Load script") { model.restoreSelectedScript() }.disabled(model.selected == nil || model.isGenerating)
                Button("Show in Finder") { if let take = model.selected { NSWorkspace.shared.activateFileViewerSelecting([take.url]) } }.disabled(model.selected == nil)
                Button("Export WAV…") { model.exportSelected() }.disabled(model.selected == nil)
            }
            HStack(spacing: 14) {
                Button { model.playPause() } label: { Image(systemName: model.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 32)) }
                    .buttonStyle(.bordered).foregroundStyle(.primary)
                    .accessibilityLabel(model.isPlaying ? "Pause take" : "Play take")
                    .disabled(model.duration == 0)
                Text(clock(model.position)).monospacedDigit().font(.caption).frame(width: 38)
                Slider(value: Binding(get: { model.position }, set: { model.seek($0) }), in: 0...max(model.duration, 0.01))
                    .accessibilityLabel("Playback position")
                    .accessibilityValue("\(clock(model.position)) of \(clock(model.duration))").disabled(model.duration == 0)
                Text(clock(model.duration)).monospacedDigit().font(.caption).frame(width: 38)
            }
            if model.selected == nil { Text("Choose a recording from the sidebar, or generate a new one.").font(.caption).foregroundStyle(RavenBrand.secondaryText) }
        }
    }
    private func clock(_ seconds: Double) -> String { String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60) }
}

private struct StorageSetupView: View {
    @Bindable var model: StudioModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(model.storageChosen ? "Model storage" : "First-time setup", systemImage: "externaldrive")
                    .font(.subheadline.bold())
                Spacer()
                Button(model.storageChosen ? "Change folder…" : "Choose storage folder…") { model.chooseStorage() }
                    .disabled(model.isGenerating || model.installer.busy)
            }
            Text(model.storageLabel).font(.caption).foregroundStyle(RavenBrand.secondaryText).textSelection(.enabled).lineLimit(2)
            if model.installer.busy {
                if model.installer.verifying { ProgressView().controlSize(.small) }
                else { ProgressView(value: model.installer.progress) }
                HStack {
                    Text(model.installer.message).font(.caption)
                    Spacer()
                    Button("Pause download") { model.installer.cancel() }.disabled(model.installer.verifying)
                }
            } else if model.storageChosen && !model.modelPresent {
                HStack {
                    Text("Ming 0.5B · 3 GB · Download once, then generate offline.").font(.caption).foregroundStyle(RavenBrand.secondaryText)
                    Spacer()
                    Button("Download model") { model.downloadModel() }.disabled(!StudioModel.volumeMounted())
                }
            }
            if let error = model.installer.error { Label(error, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.primary).textSelection(.enabled) }
            if !model.installer.busy && !model.installer.message.isEmpty { Text(model.installer.message).font(.caption).foregroundStyle(RavenBrand.secondaryText) }
        }
        .padding(12).background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 10))
    }
}
