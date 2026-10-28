import AppKit
import AVFoundation
import Observation
import Darwin

struct Voice: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    static let english: [Voice] = [
        .init(id: "US_James", name: "American James", detail: "American · male"),
        .init(id: "US_Emma", name: "American Emma", detail: "American · female"),
        .init(id: "UK_George", name: "British George", detail: "British · male"),
        .init(id: "UK_Charlotte", name: "British Charlotte", detail: "British · female")
    ]
    static let designed = Voice(id: "designed", name: "Custom Voice", detail: "Voice Design · Describe the voice and delivery")
    static let own = Voice(id: "reference", name: "Your Voice", detail: "Voice cloned from your recording")
    static let natural = Voice(id: "natural", name: "Natural voice", detail: "Automatic voice for the selected language; each take may vary.")
    static var all: [Voice] { english + chinese + [natural, designed, own] }
    static func presets(for language: String) -> [Voice] {
        if language == "en" { return english }
        return language == "zh" ? [natural] + chinese : [natural]
    }
    static func choices(for language: String) -> [Voice] {
        presets(for: language) + [designed, own]
    }

}
struct Draft: Codable, Equatable {
    var title = "My voice-over"
    var script = ""
    var voice = "US_James"
    var style = "A warm, clear documentary narrator with measured pacing and thoughtful, understated delivery."
    var language: String? = "en"
    var presetVoice: String?
    var referenceFile: String?
    var referenceTranscript: String?
}
struct TakeInfo: Codable {
    let title: String
    let script: String
    let voice: String
    let style: String
    let created: Date
    var language: String? = "en"
    var presetVoice: String?
    var referenceFile: String?
    var referenceTranscript: String?
}
struct Take: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let title: String
    let detail: String
    let created: Date
}

@MainActor @Observable final class StudioModel {
    static var base: URL { StoragePreference.folder ?? URL(fileURLWithPath: "/Volumes/10TB JBOD/Work/Ming-Voiceovers", isDirectory: true) }
    let installer = ModelInstaller()
    let yourVoice: YourVoiceStore
    var storageChosen: Bool { StoragePreference.record != nil }
    var storageLabel: String { StoragePreference.folder?.path ?? "Choose where to store the model and recordings" }
    var modelPresent: Bool {
        var info = stat()
        return model.path.withCString { fstatat(AT_FDCWD, $0, &info, 0) } == 0 && info.st_size == ModelArtifact.ming.size
    }
    var draft = Draft()
    var takes: [Take] = []
    var selectedID: String?
    var available = false
    var availabilityMessage = "Checking engine…"
    var isGenerating = false
    var isDeleting = false
    var status = "Write your script, choose a voice, and generate a take."
    var errorMessage: String?
    var logTail = ""
    var elapsed: Double = 0
    let waveform = WaveformModel()
    var playbackVolume: Double = 1 { didSet { player?.volume = Float(playbackVolume) } }
    var isPlaying = false
    var position: Double = 0
    var duration: Double = 0
    var draftStatus = ""
    @ObservationIgnored private let engineOverride: URL?
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var logHandle: FileHandle?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let settingsWriter = SettingsWriter()
    @ObservationIgnored private var saveRevision = 0
    @ObservationIgnored private var playerTask: Task<Void, Never>?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var runID: UUID?
    @ObservationIgnored private var cancelled = false
    @ObservationIgnored private var started = Date()
    var selected: Take? { takes.first { $0.id == selectedID } }
    var selectedLanguage: String {
        get { draft.language ?? "en" }
        set {
            draft.language = newValue
            if !Voice.presets(for: newValue).contains(where: { $0.id == draft.presetVoice }) { draft.presetVoice = Voice.presets(for: newValue)[0].id }
            if !Voice.choices(for: newValue).contains(where: { $0.id == draft.voice }) { draft.voice = Voice.choices(for: newValue)[0].id }
        }
    }
    var usesCustomVoice: Bool {
        get { draft.voice == "designed" }
        set {
            guard newValue != usesCustomVoice else { return }
            if newValue { draft.presetVoice = selectedPresetVoice; draft.voice = "designed" }
            else { draft.voice = selectedPresetVoice }
        }
    }
    var selectedPresetVoice: String {
        get {
            let presets = Voice.presets(for: selectedLanguage)
            if presets.contains(where: { $0.id == draft.voice }) { return draft.voice }
            return presets.first(where: { $0.id == draft.presetVoice })?.id ?? presets[0].id
        }
        set {
            guard Voice.presets(for: selectedLanguage).contains(where: { $0.id == newValue }) else { return }
            draft.presetVoice = newValue
            if !usesCustomVoice { draft.voice = newValue }
        }
    }
    var usesYourVoice: Bool {
        get { draft.voice == "reference" }
        set {
            guard newValue != usesYourVoice else { return }
            if newValue { draft.presetVoice = selectedPresetVoice; draft.voice = "reference" }
            else { draft.voice = selectedPresetVoice }
        }
    }
    var canDeleteSelected: Bool { selected != nil && Self.volumeMounted() && !isGenerating && !isDeleting && !yourVoice.isRecording && !yourVoice.busy }
    var canGenerate: Bool { available && Voice.choices(for: selectedLanguage).contains(where: { $0.id == draft.voice }) && !isGenerating && !isDeleting && !yourVoice.isRecording && !yourVoice.busy && (draft.voice != "reference" || yourVoice.ready) && !draft.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (draft.voice != "designed" || !draft.style.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
    var generationGuidance: String {
        if isDeleting { return "Moving the take to Trash…" }
        if yourVoice.isRecording { return "Finish recording your voice sample before generating." }
        if yourVoice.busy { return "Preparing your voice sample…" }
        if !available { return availabilityMessage }
        if draft.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter the words to speak in Script." }
        if usesCustomVoice && draft.style.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Describe the Custom Voice you want to use." }
        if usesYourVoice && !yourVoice.ready { return "Record or import your voice sample first." }
        return status
    }
    var engine: URL {
        if let engineOverride { return engineOverride }
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Engine/audiocpp_cli"), FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        return Self.base.appendingPathComponent("audio.cpp/build/macos-metal-release/bin/audiocpp_cli")
    }
    var model: URL { Self.base.appendingPathComponent("models/ming-3.0-tts-0.5b-bf16.gguf") }
    var samples: URL { Self.base.appendingPathComponent("samples", isDirectory: true) }
    var draftURL: URL { Self.base.appendingPathComponent("app-data/draft.json") }

    init(engineOverride: URL? = nil, denoiserOverride: URL? = nil) {
        self.engineOverride = engineOverride
        self.yourVoice = YourVoiceStore(denoiserOverride: denoiserOverride)
        yourVoice.beforePreview = { [weak self] in self?.stopPlayback() }
        refreshAvailability()
        if Self.volumeMounted() {
            if let data = try? Data(contentsOf: draftURL), let saved = try? JSONDecoder().decode(Draft.self, from: data) { draft = saved }
            reloadTakes()
            if draft.voice == "reference", let file = draft.referenceFile { yourVoice.selectSavedSample(file, transcript: draft.referenceTranscript ?? "") }
        }
    }
    static func volumeMounted() -> Bool { StoragePreference.mounted }
    func chooseStorage() {
        guard !isGenerating && !isDeleting && !yourVoice.isRecording && !yourVoice.busy && !installer.busy else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.prompt = "Use this folder"
        panel.message = "Choose a folder for the 3 GB Ming model, scripts, and recordings. External storage is supported."
        panel.directoryURL = StoragePreference.folder
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do {
            try StoragePreference.choose(folder)
            refreshAvailability()
            yourVoice.reload()
            try FileManager.default.createDirectory(at: samples, withIntermediateDirectories: true)
            draft = (try? JSONDecoder().decode(Draft.self, from: Data(contentsOf: draftURL))) ?? Draft()
            reloadTakes(); select(nil)
        } catch { errorMessage = error.localizedDescription }
    }
    func downloadModel() {
        guard Self.volumeMounted(), !isGenerating else { refreshAvailability(); return }
        installer.download(to: model) { [weak self] in self?.refreshAvailability(); self?.reloadTakes() }
    }
    func refreshAvailability() {
        guard storageChosen else { available = false; availabilityMessage = "Choose a storage folder to get started."; return }
        guard Self.volumeMounted() else { available = false; availabilityMessage = "Reconnect your model-storage volume to continue."; return }
        guard FileManager.default.isExecutableFile(atPath: engine.path) else { available = false; availabilityMessage = "The bundled engine is missing. Reinstall the application."; return }
        guard modelPresent else { available = false; availabilityMessage = "Download the Ming 0.5B model to start generating."; return }
        available = true
        availabilityMessage = "Powered by Ming 0.5B · Apple GPU · Local generation"
    }
    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            self?.saveDraft()
        }
    }
    func saveDraft() {
        guard Self.volumeMounted() else { draftStatus = "Draft not saved — reconnect your storage volume."; return }
        saveRevision += 1
        let revision = saveRevision
        do {
            let data = try JSONEncoder().encode(draft)
            draftStatus = "Saving draft…"
            settingsWriter.submit([(data, draftURL)]) { [weak self] error in
                guard let self, self.saveRevision == revision else { return }
                self.draftStatus = error.map { "Could not save draft: \($0)" } ?? "Draft saved"
            }
        } catch { draftStatus = "Could not save draft: \(error.localizedDescription)" }
    }
    func flushSettings() async {
        await settingsWriter.flush()
        await yourVoice.flushSettings()
    }
    func reloadTakes() {
        guard Self.volumeMounted() else { refreshAvailability(); return }
        do {
            let files = try FileManager.default.contentsOfDirectory(at: samples, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles)
            takes = files.filter { $0.pathExtension.lowercased() == "wav" }.map { url in
                let metadata = (try? Data(contentsOf: url.deletingPathExtension().appendingPathExtension("json"))).flatMap { try? JSONDecoder().decode(TakeInfo.self, from: $0) }
                let date = metadata?.created ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let label = metadata.map { info in
                    let voice = Voice.all.first(where: { $0.id == info.voice })?.name ?? info.voice
                    let language = SpeechLanguage.all.first { $0.id == (info.language ?? "en") }?.name ?? "English"
                    return "\(voice) · \(language)"
                } ?? "Audition sample"
                return Take(url: url, title: metadata?.title ?? url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "-", with: " "), detail: label, created: date)
            }.sorted { $0.created > $1.created }
        } catch { errorMessage = "Could not read takes: \(error.localizedDescription)" }
    }
    func deleteTake(_ take: Take) {
        guard Self.volumeMounted(), !isGenerating, !isDeleting, !yourVoice.isRecording, !yourVoice.busy, takes.contains(where: { $0.id == take.id }) else { return }
        if selectedID == take.id { select(nil) }
        isDeleting = true
        let folder = samples
        let audioURL = take.url
        Task {
            defer { isDeleting = false }
            do {
                _ = try await Task.detached { try TakeDeletion.moveToTrash(audioURL, in: folder) }.value
                reloadTakes()
                status = "Moved “\(take.title)” to the Trash."
                AccessibilityAnnouncement.post(status)
            } catch {
                reloadTakes()
                errorMessage = "Could not delete take: \(error.localizedDescription)"
            }
        }
    }
    func generate() {
        refreshAvailability()
        guard canGenerate else { return }
        stopPlayback()
        saveDraft()
        var requestDraft = draft
        if usesYourVoice {
            requestDraft.referenceFile = yourVoice.profile?.fileName
            requestDraft.referenceTranscript = yourVoice.transcript
            draft.referenceFile = requestDraft.referenceFile
            draft.referenceTranscript = requestDraft.referenceTranscript
            saveDraft()
        }
        let snapshot = requestDraft
        let id = UUID()
        let run = Self.base.appendingPathComponent("runs/\(id.uuidString)", isDirectory: true)
        let output = run.appendingPathComponent("output.wav")
        let log = run.appendingPathComponent("generation.log")
        do {
            guard snapshot.script.count <= 20000 else { throw StudioError.message("Please split scripts longer than 20,000 characters into separate takes.") }
            try FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: Self.base.appendingPathComponent("tmp"), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: log.path, contents: nil)
            let handle = try FileHandle(forWritingTo: log)
            let job = Process()
            job.executableURL = engine
            job.currentDirectoryURL = Self.base
            var args = ["--family", "ming3_tts", "--task", snapshot.voice == "designed" ? "vdes" : (snapshot.voice == "reference" ? "clon" : "tts"), "--backend", "metal", "--model", model.path, "--text", snapshot.script, "--request-option", "language=\(snapshot.language ?? "en")", "--threads", "8", "--out", output.path, "--metrics", "--log"]
            if snapshot.voice == "designed" { args += ["--request-option", "instruct=\(snapshot.style)"] }
            else if snapshot.voice == "reference" {
                guard let reference = yourVoice.sampleURL else { throw StudioError.message("Record or import your voice sample first.") }
                let chunkSize = ["zh", "ja", "ko"].contains(snapshot.language ?? "en") ? "40" : "100"
                args += ["--voice-ref", reference.path, "--request-option", "text_chunk_size=\(chunkSize)"]
                if let transcript = snapshot.referenceTranscript?.trimmingCharacters(in: .whitespacesAndNewlines), !transcript.isEmpty { args += ["--request-option", "reference_text=\(transcript)"] }
            }
            else if snapshot.voice == "natural" { args += ["--request-option", "template_name=multilingual"] }
            else { args += ["--request-option", "template_name=ip", "--request-option", "voice_id=\(snapshot.voice)"] }
            job.arguments = args
            var env = ProcessInfo.processInfo.environment
            env["TMPDIR"] = Self.base.appendingPathComponent("tmp").path
            job.environment = env
            job.standardOutput = handle
            job.standardError = handle
            job.terminationHandler = { [weak self] finished in
                let code = finished.terminationStatus
                Task { @MainActor in self?.complete(id: id, code: code, output: output, log: log, snapshot: snapshot) }
            }
            isGenerating = true; cancelled = false; elapsed = 0; started = Date(); runID = id
            errorMessage = nil; logTail = ""; status = "Preparing model and generating speech…"
            process = job; logHandle = handle
            try job.run()
            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled, let self, self.runID == id else { return }
                    self.elapsed = Date().timeIntervalSince(self.started)
                    if let input = try? FileHandle(forReadingFrom: log) {
                        let length = (try? input.seekToEnd()) ?? 0
                        try? input.seek(toOffset: length > 7000 ? length - 7000 : 0)
                        self.logTail = String(decoding: (try? input.readToEnd()) ?? Data(), as: UTF8.self)
                        try? input.close()
                    }
                }
            }
        } catch {
            isGenerating = false; process = nil; runID = nil
            try? logHandle?.close(); logHandle = nil
            errorMessage = error.localizedDescription; status = "Generation did not start. Your script is kept."
        }
    }
    private func complete(id: UUID, code: Int32, output: URL, log: URL, snapshot: Draft) {
        guard runID == id else { return }
        pollTask?.cancel(); pollTask = nil
        logTail = String(decoding: (try? Data(contentsOf: log)) ?? Data(), as: UTF8.self).suffix(7000).description
        try? logHandle?.close(); logHandle = nil; process = nil; runID = nil; isGenerating = false
        if cancelled { status = "Generation cancelled. Your script is kept."; return }
        guard code == 0 else { errorMessage = "Ming stopped with code \(code). Open generation details for the engine log."; status = "Generation failed. Your script is kept."; return }
        do {
            guard Self.volumeMounted() else { throw StudioError.message("The storage volume was disconnected. Reconnect it to recover the take from the runs folder.") }
            let audio = try AVAudioFile(forReading: output)
            guard audio.length > 0 else { throw StudioError.message("The engine returned an empty audio file.") }
            let filename = "Take-\(Date.now.formatted(.iso8601).replacingOccurrences(of: ":", with: "-"))-\(id.uuidString.prefix(6)).wav"
            let target = samples.appendingPathComponent(filename)
            try FileManager.default.moveItem(at: output, to: target)
            let info = TakeInfo(title: snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled take" : snapshot.title, script: snapshot.script, voice: snapshot.voice, style: snapshot.style, created: Date(), language: snapshot.language, presetVoice: snapshot.presetVoice, referenceFile: snapshot.referenceFile, referenceTranscript: snapshot.referenceTranscript)
            do { try JSONEncoder().encode(info).write(to: target.deletingPathExtension().appendingPathExtension("json"), options: .atomic) }
            catch { errorMessage = "Audio saved, but its script details could not be saved: \(error.localizedDescription)" }
            reloadTakes(); select(target.path)
            status = "Take ready · \(String(format: "%.1f", duration)) seconds"
            logTail = String(decoding: (try? Data(contentsOf: log)) ?? Data(), as: UTF8.self).suffix(7000).description
        } catch { errorMessage = error.localizedDescription; status = "Could not finish saving. Any generated audio remains in the runs folder." }
    }
    func cancel() {
        guard let job = process, job.isRunning else { return }
        cancelled = true; status = "Cancelling…"; job.terminate()
    }
    func select(_ id: String?) {
        stopPlayback(); yourVoice.stopPreview(clear: true); waveform.load(nil)
        player = nil; selectedID = id; position = 0; duration = 0
        guard let take = selected else { return }
        guard Self.volumeMounted() else { errorMessage = "Reconnect your storage volume to play this take."; return }
        do { player = try AVAudioPlayer(contentsOf: take.url); player?.volume = Float(playbackVolume); player?.prepareToPlay(); duration = player?.duration ?? 0; waveform.load(take.url) }
        catch { player = nil; errorMessage = "Could not open audio: \(error.localizedDescription)" }
    }
    func playPause() {
        yourVoice.stopPreview(clear: true)
        guard let player else { return }
        if player.isPlaying { player.pause(); playerTask?.cancel(); playerTask = nil; isPlaying = false; return }
        if position >= duration { player.currentTime = 0; position = 0 }
        isPlaying = player.play()
        playerTask?.cancel()
        playerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, let self, let player = self.player else { return }
                self.isPlaying = player.isPlaying
                self.position = player.isPlaying ? player.currentTime : (player.currentTime == 0 ? self.duration : player.currentTime)
                if !player.isPlaying { return }
            }
        }
    }
    func seek(_ time: Double) {
        guard time.isFinite else { return }
        let clamped = min(duration, max(0, time)); player?.currentTime = clamped; position = clamped
    }
    func stopPlayback() { playerTask?.cancel(); playerTask = nil; player?.stop(); isPlaying = false }
    func restoreSelectedScript() {
        guard let take = selected, let data = try? Data(contentsOf: take.url.deletingPathExtension().appendingPathExtension("json")), let info = try? JSONDecoder().decode(TakeInfo.self, from: data) else { errorMessage = "This audition sample has no saved script. New takes include their script and voice settings."; return }
        draft = Draft(title: info.title, script: info.script, voice: info.voice, style: info.style, language: info.language ?? "en", presetVoice: info.presetVoice, referenceFile: info.referenceFile, referenceTranscript: info.referenceTranscript)
        if info.voice == "reference", let file = info.referenceFile { yourVoice.selectSavedSample(file, transcript: info.referenceTranscript ?? "") }
        scheduleSave()
    }
    func exportSelected() {
        guard let take = selected, Self.volumeMounted() else { errorMessage = "Reconnect your storage volume and select a take to export."; return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.wav]
        panel.nameFieldStringValue = take.url.lastPathComponent
        panel.directoryURL = Self.base
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let target = panel.url else { return }
        guard target.standardizedFileURL != take.url.standardizedFileURL else { return }
        do {
            // NSSavePanel confirms replacement; atomic data write keeps the old
            // export intact until the new copy is ready.
            try Data(contentsOf: take.url).write(to: target, options: .atomic)
            status = "Exported \(target.lastPathComponent)"
        } catch { errorMessage = "Export failed: \(error.localizedDescription)" }
    }
    func shutdown() { yourVoice.stopPreview(); yourVoice.flush(); saveTask?.cancel(); saveDraft(); cancel(); installer.cancel(); stopPlayback() }
}
enum StudioError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(message) = self { return message }; return nil }
}
