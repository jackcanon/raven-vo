import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct CleanupControlSnapshot: Equatable {
    var settings: NarrationCleanupSettings
    var monitorGainDB: Double
}
@MainActor @Observable final class NarrationStudioModel {
    private(set) var takes: [NarrationTake] = []
    private(set) var favoriteTake: Int?
    private(set) var auditioningTake: Int?
    var recordTakeLabel: String { takes.isEmpty ? "Record Take 1" : "Record Next Take" }
    var currentTake: NarrationTake? { takes.first { $0.folder.path == project?.path } }

    private func refreshTakes(loadScript: Bool = false) {
        takes = []; favoriteTake = nil
        guard let project else { return }
        do {
            let group = NarrationTakes.group(of: project)
            let settings = try NarrationTakes.settings(in: group)
            takes = try NarrationTakes.list(in: group, settings: settings)
            favoriteTake = settings.favorite
            if loadScript, let script = settings.script { promptScript = script }
        } catch { status = "Could not read the take list: \(error.localizedDescription)" }
    }

    func renameTake(_ id: Int, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateTake(id) { $0.names[id] = trimmed }
    }

    func toggleFavorite(_ id: Int) {
        updateTake(id) { $0.favorite = $0.favorite == id ? nil : id }
    }

    private func updateTake(_ id: Int, change: (inout NarrationTakes.Settings) -> Void) {
        guard !locked, let project, takes.contains(where: { $0.id == id }) else { return }
        do {
            try checkStorage()
            try NarrationTakes.update(in: NarrationTakes.group(of: project), change)
            refreshTakes()
        } catch { status = error.localizedDescription }
    }

    func editTake(_ take: NarrationTake) {
        guard !locked, takes.contains(take) else { return }
        do { try persist() } catch { status = error.localizedDescription; return }
        openProject(at: take.folder.appendingPathComponent("project.ravenvo.json"))
    }

    func audition(_ take: NarrationTake) {
        guard !locked, takes.contains(take) else { return }
        let wasPlaying = auditioningTake == take.id
        stop()
        guard !wasPlaying else { return }
        do {
            try checkStorage()
            let audio = try AVAudioPlayer(contentsOf: take.original)
            guard audio.play() else { throw StudioError.message("Could not play this take.") }
            player = audio; playing = true; auditioningTake = take.id
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.auditioningTake != nil, self.player?.isPlaying != true else { return }
                    self.stop()
                }
            }
        } catch { status = error.localizedDescription }
    }

    func newScript() -> Bool {
        guard !locked else { return false }
        do {
            if let project, edit != nil {
                try persist()
                try NarrationTakes.update(in: NarrationTakes.group(of: project)) { $0.script = promptScript }
            }
            let draft = try root().appendingPathComponent("prompter-draft.txt")
            try "".write(to: draft, atomically: true, encoding: .utf8)
            stop(); clearPreparedExport()
            project = nil; edit = nil; promptScript = ""; takes = []; favoriteTake = nil
            history = []; future = []; selection = nil; playhead = 0
            recordingWarning = nil; effects.clear(); waveform.load(nil)
            roomToneURL = nil; roomToneDeviceID = nil; noiseAnalysis = nil; magicChoice = nil
            cleanupControlUndo = []; cleanupControlRedo = []; cleanupGestureStart = nil
            status = "Enter the script for the first take."
            return true
        } catch { status = error.localizedDescription; return false }
    }

    var edit: NarrationEdit?
    var project: URL?
    var selection: NarrationRange?
    var status = "Record your narration or import an audio file to begin."
    var busy = false
    var recording = false
    var finishing = false
    var exportEncoding = NarrationExportEncoding.pcm24
    var exportGainDB = 0.0
    var exportCeiling = false
    var exportLevels: NarrationExportLevels?
    var exportSummary = ""
    @ObservationIgnored private var preparedExport: URL?
    var pendingRecordings: [NarrationRecordingRecovery] = []
    var recordingWarning: String?
    var level = -80.0
    var recordedSeconds = 0.0
    var deviceID = StoragePreference.preferences.string(forKey: "RavenVO.studio.microphone") ?? "" {
        didSet { StoragePreference.preferences.set(deviceID, forKey: "RavenVO.studio.microphone") }
    }
    var devices = MicrophoneCapture.choices()
    var promptScript = ""
    var localeID = "en-US"
    var appleTranscriptionEnabled = StoragePreference.preferences.bool(forKey: "RavenVO.studio.appleTranscription") {
        didSet { StoragePreference.preferences.set(appleTranscriptionEnabled, forKey: "RavenVO.studio.appleTranscription") }
    }
    @ObservationIgnored private var liveTranscription: AnyObject?
    private var transcriptionSetupError: String?
    var playing = false
    var playhead = 0.0
    let waveform = WaveformModel()
    let effects = NarrationAudioUnits()
    var roomToneURL: URL?
    var roomToneDeviceID: String?
    var cleanupSettings = NarrationCleanupSettings.referenceA {
        didSet {
            if cleanupSettings != oldValue { rememberCleanupControl(.init(settings: oldValue, monitorGainDB: monitorGainDB)) }
            cleanupPreview?.state.update(cleanupSettings, original: previewOriginal)
        }
    }
    var previewOriginal = false {
        didSet { cleanupPreview?.state.update(cleanupSettings, original: previewOriginal) }
    }
    var monitorGainDB = 0.0 {
        didSet {
            if monitorGainDB != oldValue { rememberCleanupControl(.init(settings: cleanupSettings, monitorGainDB: oldValue)) }
            cleanupPreview?.setMonitorDB(monitorGainDB)
        }
    }
    var cleanupPreviewRunning = false
    var previewLevelHigh = false
    @ObservationIgnored private var cleanupPreview: NarrationLivePreview?
    var cleanupControlUndo: [CleanupControlSnapshot] = []
    var cleanupControlRedo: [CleanupControlSnapshot] = []
    @ObservationIgnored private var cleanupGestureStart: CleanupControlSnapshot?
    @ObservationIgnored private var restoringCleanupControl = false
    private var cleanupControlSnapshot: CleanupControlSnapshot { .init(settings: cleanupSettings, monitorGainDB: monitorGainDB) }
    private func rememberCleanupControl(_ before: CleanupControlSnapshot) {
        guard !restoringCleanupControl, cleanupGestureStart == nil else { return }
        cleanupControlUndo.append(before); cleanupControlRedo = []
        if cleanupControlUndo.count > 100 { cleanupControlUndo.removeFirst() }
    }
    func cleanupEditingChanged(_ editing: Bool) {
        if editing {
            if cleanupGestureStart == nil { cleanupGestureStart = cleanupControlSnapshot }
        } else if let before = cleanupGestureStart {
            cleanupGestureStart = nil
            if before != cleanupControlSnapshot { rememberCleanupControl(before) }
        }
    }
    func undoCleanupControl() {
        guard !locked, let previous = cleanupControlUndo.popLast() else { return }
        cleanupControlRedo.append(cleanupControlSnapshot)
        restoringCleanupControl = true; cleanupSettings = previous.settings; monitorGainDB = previous.monitorGainDB; restoringCleanupControl = false
    }
    func redoCleanupControl() {
        guard !locked, let next = cleanupControlRedo.popLast() else { return }
        cleanupControlUndo.append(cleanupControlSnapshot)
        restoringCleanupControl = true; cleanupSettings = next.settings; monitorGainDB = next.monitorGainDB; restoringCleanupControl = false
    }
    var magicChoice: String?
    var noiseAnalysis: NarrationNoiseAnalysis?
    var cleanupNeedsRender: Bool { edit?.cleanedSourceName != nil && edit?.cleanupSettings != cleanupSettings }
    var samplingRoom = false
    private var currentMicrophoneID: String { deviceID.isEmpty ? AVCaptureDevice.default(for: .audio)?.uniqueID ?? "" : deviceID }
    var history: [NarrationEdit] = []
    var future: [NarrationEdit] = []
    @ObservationIgnored private var capture: MicrophoneCapture?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var timer: Timer?
    var locked: Bool { busy || recording || finishing || effects.loading }
    var source: URL? { guard let edit, let project else { return nil }; return project.appendingPathComponent(edit.useCleanedAudio == true ? edit.cleanedSourceName ?? edit.sourceName : edit.sourceName) }

    init() {
        if StoragePreference.mounted, let folder = StoragePreference.folder {
            promptScript = (try? String(contentsOf: folder.appendingPathComponent("studio/prompter-draft.txt"), encoding: .utf8)) ?? ""
        }
    }
    func savePromptScript() {
        do {
            let url = try root().appendingPathComponent("prompter-draft.txt")
            try promptScript.write(to: url, atomically: true, encoding: .utf8)
            if let project, edit != nil {
                try NarrationTakes.update(in: NarrationTakes.group(of: project)) { $0.script = promptScript }
            }
        } catch { status = "Could not save prompter script: \(error.localizedDescription)" }
    }
    private func root() throws -> URL {
        guard StoragePreference.mounted, let folder = StoragePreference.folder else { throw StudioError.message("Choose mounted storage in the main Raven VO window first.") }
        let root = folder.appendingPathComponent("studio", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func checkStorage() throws {
        _ = try root()
        guard let project, FileManager.default.fileExists(atPath: project.path) else { throw StudioError.message("The studio project folder is unavailable.") }
    }
    private func newFolder() throws -> URL {
        let folder = try root().appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
    func save() {
        do { try persist(); status = "Project saved. Original audio is preserved." }
        catch { status = error.localizedDescription }
    }
    private func persist() throws {
        try checkStorage()
        guard let project, var edit else { return }
        edit.plugins = try effects.snapshot(); self.edit = edit
        try edit.validate()
        try JSONEncoder().encode(edit).write(to: project.appendingPathComponent("project.ravenvo.json"), options: .atomic)
    }
    func loadAudio(_ url: URL, folder: URL) throws {
        let file = try AVAudioFile(forReading: url)
        let duration = Double(file.length) / file.processingFormat.sampleRate
        guard duration.isFinite, duration > 0 else { throw StudioError.message("This file contains no audio.") }
        stop()
        clearPreparedExport()
        recordingWarning = nil
        project = folder
        edit = NarrationEdit(sourceName: url.lastPathComponent, duration: duration, kept: [.init(start: 0, end: duration)], joinCrossfadeMS: 5)
        edit?.promptScript = promptScript
        effects.clear()
        cleanupControlUndo = []; cleanupControlRedo = []; cleanupGestureStart = nil
        history = []; future = []; selection = nil; playhead = 0
        waveform.load(url)
        try persist()
        refreshTakes()
    }
    func importAudio() {
        guard !locked else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.audio]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        busy = true; stop()
        Task { [self] in
            defer { busy = false }
            do {
                let folder = try newFolder()
                let target = folder.appendingPathComponent("original.\(url.pathExtension.isEmpty ? "wav" : url.pathExtension)")
                try await Task.detached { try FileManager.default.copyItem(at: url, to: target) }.value
                try loadAudio(target, folder: folder)
                status = "Imported. Transcribe to edit by text, or drag across the waveform to cut audio."
            } catch { status = error.localizedDescription }
        }
    }
    func openProject() {
        guard !locked else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        panel.message = "Choose project.ravenvo.json in a saved studio folder."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openProject(at: url)
    }
    func openProject(at url: URL) {
        guard !locked else { return }
        do {
            _ = try root()
            let candidate = try JSONDecoder().decode(NarrationEdit.self, from: Data(contentsOf: url))
            try candidate.validate()
            let folder = url.deletingLastPathComponent()
            let audio = folder.appendingPathComponent(candidate.sourceName)
            let file = try AVAudioFile(forReading: audio)
            guard abs(Double(file.length) / file.processingFormat.sampleRate - candidate.duration) < 0.1 else { throw StudioError.message("The original audio does not match this project.") }
            // Only open projects on the selected storage volume.
            let volume = try folder.resourceValues(forKeys: [.volumeURLKey]).volume?.standardizedFileURL.path
            guard volume == StoragePreference.record?.volumePath else { throw StudioError.message("Copy the project folder to your selected storage volume before opening it.") }
            clearPreparedExport()
            recordingWarning = nil
            stop(); project = folder; edit = candidate; selection = nil; history = []; future = []; playhead = 0
            waveform.load(source); status = "Project opened."
            roomToneURL = candidate.roomToneName.map { folder.appendingPathComponent($0) }
            promptScript = candidate.promptScript ?? ""
            refreshTakes(loadScript: true)
            roomToneDeviceID = candidate.roomToneDeviceID
            cleanupSettings = candidate.cleanupSettings ?? .init(strength: candidate.cleanupAmount ?? 1.2, maximumReductionDB: 22, smoothing: 0)
            noiseAnalysis = nil; magicChoice = nil
            cleanupControlUndo = []; cleanupControlRedo = []; cleanupGestureStart = nil
            busy = true
            Task { [self] in
                await effects.restore(candidate.plugins ?? [])
                busy = false
                if !effects.message.isEmpty { status = effects.message }
            }
        } catch { status = error.localizedDescription }
    }
    func findInterruptedRecordings() {
        guard !locked else { return }
        do { pendingRecordings = try NarrationRecordingRecovery.pending(in: root()) }
        catch { status = "Could not check recordings: \(error.localizedDescription)" }
    }
    func recoverRecording(_ item: NarrationRecordingRecovery) {
        guard !locked else { return }
        busy = true; stop()
        Task { [self] in
            defer { busy = false }
            do {
                try checkRecoveryLocation(item)
                let original = item.folder.appendingPathComponent(item.audioName)
                let file = try AVAudioFile(forReading: original)
                guard file.length > 0 else { throw StudioError.message("No readable audio is available in this take.") }
                let group = NarrationTakes.group(of: item.folder)
                let folder = group.path == item.folder.path ? try newFolder() : try NarrationTakes.allocate(in: group)
                let copy = folder.appendingPathComponent("original.wav")
                try await Task.detached { try FileManager.default.copyItem(at: original, to: copy) }.value
                roomToneURL = nil; roomToneDeviceID = nil; noiseAnalysis = nil; magicChoice = nil
                promptScript = item.script; localeID = item.localeID
                try loadAudio(copy, folder: folder)
                try item.complete()
                pendingRecordings.removeAll { $0.id == item.id }
                recordingWarning = "Recovered an interrupted take. Listen through its ending before using it. The original file remains in \(item.folder.path)."
                status = "Recording recovered into a new project. Transcribe Recording can create its transcript."
            } catch { status = "Recovery could not finish: \(error.localizedDescription) The original recording remains untouched." }
        }
    }
    private func checkRecoveryLocation(_ item: NarrationRecordingRecovery) throws {
        let expected = try root().resolvingSymlinksInPath()
        let group = NarrationTakes.group(of: item.folder.resolvingSymlinksInPath())
        guard group.deletingLastPathComponent().resolvingSymlinksInPath().path == expected.path, item.audioName == "original.wav" else {
            throw StudioError.message("This recording is outside the selected studio storage.")
        }
    }
    func nextRecordingFolder() throws -> URL {
        guard let project else { return try newFolder() }
        try persist()
        let group = NarrationTakes.group(of: project)
        try NarrationTakes.update(in: group) { $0.script = promptScript }
        return try NarrationTakes.allocate(in: group)
    }

    func startRecording() {
        guard !locked else { return }
        busy = true; stop()
        Task { [self] in
            defer { busy = false }
            do {
                guard await AVCaptureDevice.requestAccess(for: .audio) else { throw StudioError.message("Allow microphone access in System Settings to record.") }
                let folder = try nextRecordingFolder()
                let url = folder.appendingPathComponent("original.wav")
                let recovery = NarrationRecordingRecovery(started: Date(), deviceName: devices.first(where: { $0.id == deviceID })?.name ?? MicrophoneCapture.defaultName(), script: promptScript, localeID: localeID, folder: folder)
                try recovery.write()
                recordingWarning = nil
                var onAudio: (@Sendable (AVAudioPCMBuffer) -> Void)?
                transcriptionSetupError = nil
                if appleTranscriptionEnabled {
                    if #available(macOS 26.0, *) {
                        status = "Preparing background Apple transcription…"
                        do {
                            let session = try await NarrationLiveTranscription.prepare(localeID: localeID)
                            liveTranscription = session
                            let feed = session.feed
                            onAudio = { feed.append($0) }
                        } catch { transcriptionSetupError = error.localizedDescription }
                    } else { transcriptionSetupError = "Apple transcription requires macOS 26 or newer." }
                }
                let recorder = MicrophoneCapture(); capture = recorder
                try await recorder.start(deviceID: deviceID, url: url, maximumDuration: 0, sampleRate: 48000, onAudio: onAudio,
                    onLevel: { [weak self] db, seconds in self?.level = db; self?.recordedSeconds = seconds },
                    onFinish: { [weak self] url, error in
                        guard let self else { return }
                        self.recording = false; self.finishing = false; self.capture = nil
                        do {
                            try self.loadAudio(url, folder: folder)
                            try recovery.complete()
                            self.recordingWarning = error.map { "Recording was interrupted: \($0) A readable partial take was saved. Listen through its ending." }
                            self.status = error == nil ? "Recording saved." : "Partial recording saved after interruption."
                            if self.appleTranscriptionEnabled { self.finishRecordingTranscription(url: url) }

                        } catch {
                            if #available(macOS 26.0, *), let session = self.liveTranscription as? NarrationLiveTranscription {
                                self.liveTranscription = nil
                                Task { await session.cancel() }
                            }
                            self.status = "Recording could not finish: \(error.localizedDescription) Audio, if recoverable, remains in \(folder.path)."
                        }
                    })
                recordedSeconds = 0; recording = true; status = appleTranscriptionEnabled ? "Recording narration with background Apple transcription…" : "Recording narration…"
            } catch {
                capture = nil; status = error.localizedDescription
                if #available(macOS 26.0, *), let session = liveTranscription as? NarrationLiveTranscription { await session.cancel() }
                liveTranscription = nil
            }
        }
    }
    private func finishRecordingTranscription(url: URL) {
        guard #available(macOS 26.0, *) else { status = "Recording saved. Apple transcription requires macOS 26+."; return }
        busy = true; status = "Recording saved. Finalizing background transcription…"
        let session = liveTranscription as? NarrationLiveTranscription
        liveTranscription = nil
        let locale = localeID
        Task { [self] in
            defer { busy = false }
            do {
                let words: [NarrationWord]
                var fallback = false
                do {
                    guard let session else { throw StudioError.message(transcriptionSetupError ?? "Background transcription was unavailable.") }
                    words = try await session.finish()
                } catch {
                    fallback = true
                    status = "Recording saved. Background transcription unavailable; transcribing the saved audio…"
                    words = try await AppleNarrationTranscriber.transcribe(url, localeID: locale)
                }
                guard !words.isEmpty else { throw StudioError.message("No speech was recognized.") }
                edit?.words = words
                try persist()
                status = fallback ? "Transcript ready from saved recording (background fallback)." : "Transcript ready from background recording transcription."
            } catch { status = "Recording saved; transcription could not finish: \(error.localizedDescription)" }
        }
    }
    func stopRecording() {
        guard recording else { return }
        finishing = true; status = "Finishing recording…"; capture?.stop()
    }
    func transcribe() {
        guard !locked, let source else { return }
        guard #available(macOS 26.0, *) else { status = "Apple transcription requires macOS 26 or newer. Recording and waveform editing remain available."; return }
        busy = true; stop(); status = "Preparing Apple transcription. Missing language assets may download to system-managed storage…"
        let locale = localeID
        Task { [self] in
            defer { busy = false }
            do {
                try checkStorage()
                let words = try await AppleNarrationTranscriber.transcribe(source, localeID: locale)
                guard !words.isEmpty else { throw StudioError.message("No timed speech was recognized. Try another language or a clearer recording.") }
                if let edit { history.append(edit) }; future = []
                edit?.words = words
                try persist()
                status = "Transcribed \(words.count) timed units. Select text to audition or cut its audio."
            } catch { status = error.localizedDescription }
        }
    }
    func selectWord(_ word: NarrationWord, extending: Bool) {
        guard !locked else { return }
        if extending, let current = selection {
            selection = .init(start: min(current.start, word.start), end: max(current.end, word.end))
        } else { selection = .init(start: word.start, end: word.end) }
        seek(word.start)
    }
    func setJoinCrossfade(_ milliseconds: Double) {
        guard !locked, milliseconds.isFinite, (0...20).contains(milliseconds), var next = edit,
              (next.joinCrossfadeMS ?? 0) != milliseconds, let current = edit else { return }
        stop(); history.append(current); future = []
        next.joinCrossfadeMS = milliseconds; edit = next; save()
        status = "Edit joins: \(Int(milliseconds)) ms crossfade. Undo restores the previous setting."
    }
    func cutSelection() {
        guard !locked, let selection, var next = edit else { return }
        next.cut(selection)
        guard next != edit, let old = edit else { return }
        stop(); history.append(old); future = []; edit = next; self.selection = nil
        save()
    }
    func undo() {
        guard !locked, let previous = history.popLast(), let current = edit else { return }
        stop(); future.append(current); edit = previous; selection = nil; waveform.load(source); save()
    }
    func redo() {
        guard !locked, let next = future.popLast(), let current = edit else { return }
        stop(); history.append(current); edit = next; selection = nil; waveform.load(source); save()
    }
    func correctWord(id: UUID, text: String) {
        guard !locked, let current = edit, let index = current.words.firstIndex(where: { $0.id == id }), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        history.append(current); future = []; edit?.words[index].text = text; save()
    }
    func seek(_ sourceTime: Double) {
        if cleanupPreviewRunning || auditioningTake != nil { stop() }
        playhead = sourceTime
        if let edit { player?.currentTime = edit.outputTime(at: sourceTime) }
    }
    func stop() {
        auditioningTake = nil
        cleanupPreview?.stop(); cleanupPreview = nil; cleanupPreviewRunning = false; previewLevelHigh = false
        player?.stop(); player = nil; timer?.invalidate(); timer = nil; playing = false
    }
    func toggleLiveCleanupPreview() {
        if cleanupPreviewRunning { stop(); return }
        guard !locked, let edit, let project, let room = roomToneURL else { return }
        stop(); busy = true; status = "Preparing live cleanup preview…"
        let raw = project.appendingPathComponent(edit.sourceName)
        Task { [self] in
            defer { busy = false }
            do {
                try checkStorage()
                let format = try AVAudioFile(forReading: raw).processingFormat
                let preview = NarrationLivePreview()
                try preview.start(source: raw, roomTone: room, directory: project, format: format, edit: edit,
                                  settings: cleanupSettings, monitorDB: monitorGainDB,
                                  onError: { [weak self] message in self?.stop(); self?.status = "Preview stopped: \(message)" })
                preview.state.update(cleanupSettings, original: previewOriginal)
                cleanupPreview = preview; cleanupPreviewRunning = true; playing = true
                timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, let preview = self.cleanupPreview else { return }
                        self.playhead = edit.sourceTime(at: preview.time)
                        self.previewLevelHigh = Double(preview.state.samplePeak) * pow(10, self.monitorGainDB / 20) >= 0.99
                    }
                }
                status = "Live cleanup preview loops the edit. Move the controls to hear changes. Monitor volume does not affect exports."
            } catch { stop(); status = error.localizedDescription }
        }
    }
    func play() {
        if playing { stop(); return }
        guard !locked, let edit, let source, let project else { return }
        busy = true
        Task { [self] in
            defer { busy = false }
            do {
                try checkStorage()
                let preview = project.appendingPathComponent("preview.wav")
                try await renderProcessed(source: source, edit: edit, destination: preview)
                player = try AVAudioPlayer(contentsOf: preview)
                player?.currentTime = edit.outputTime(at: playhead)
                if (player?.currentTime ?? 0) >= edit.outputDuration - 0.01 { player?.currentTime = 0 }
                guard player?.play() == true else { throw StudioError.message("Playback could not start.") }
                playing = true
                timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, let player = self.player else { return }
                        self.playhead = edit.sourceTime(at: player.currentTime)
                        if !player.isPlaying { self.stop() }
                    }
                }
            } catch { status = error.localizedDescription }
        }
    }
    private func renderProcessed(source: URL, edit: NarrationEdit, destination: URL) async throws {
        let plugins = try effects.snapshot()
        var renderSource = source
        let updated = destination.deletingLastPathComponent().appendingPathComponent("cleanup-render-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: updated) }
        if edit.useCleanedAudio == true, edit.cleanupSettings != cleanupSettings, let room = roomToneURL, let project {
            let settings = cleanupSettings
            let raw = project.appendingPathComponent(edit.sourceName)
            try await Task.detached { try NarrationNoiseCleanup.render(source: raw, roomTone: room, destination: updated, settings: settings) }.value
            renderSource = updated
        }
        try persist()
        let dry = destination.deletingLastPathComponent().appendingPathComponent("dry-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: dry) }
        let selectedSource = renderSource
        try await Task.detached { try NarrationRenderer.render(source: selectedSource, edit: edit, destination: dry, floatingPoint: true) }.value
        if plugins.contains(where: { !$0.bypass }) {
            try await NarrationAudioUnits.render(source: dry, destination: destination, plugins: plugins, floatingPoint: true)
        } else {
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.moveItem(at: dry, to: destination)
        }
    }
    func sampleRoomNoise() {
        guard !locked else { return }
        busy = true; stop()
        Task { [self] in
            defer { busy = false }
            do {
                guard await AVCaptureDevice.requestAccess(for: .audio) else { throw StudioError.message("Allow microphone access to capture room noise.") }
                let folder = try newFolder()
                let url = folder.appendingPathComponent("room-noise.wav")
                let device = currentMicrophoneID
                let rate = try source.map { try AVAudioFile(forReading: $0).processingFormat.sampleRate } ?? 48000
                let recorder = MicrophoneCapture(); capture = recorder
                samplingRoom = true
                try await recorder.start(deviceID: deviceID, url: url, maximumDuration: 3, sampleRate: rate,
                    onLevel: { [weak self] db, seconds in self?.level = db; self?.recordedSeconds = seconds },
                    onFinish: { [weak self] url, error in
                        guard let self else { return }
                        self.recording = false; self.finishing = false; self.samplingRoom = false; self.capture = nil
                        if let error { self.status = error; return }
                        self.roomToneURL = url; self.roomToneDeviceID = device; self.noiseAnalysis = nil; self.magicChoice = nil
                        self.status = "Room noise captured. Record narration with the same microphone and input gain, then apply cleanup."
                    })
                recordedSeconds = 0; recording = true; status = "Stay silent: sampling 3 seconds of room noise…"
            } catch { capture = nil; samplingRoom = false; status = error.localizedDescription }
        }
    }
    func magicCleanup() {
        guard !locked, let room = roomToneURL else { return }
        busy = true; status = "Magic is checking the room-noise sample…"
        Task { [self] in
            do {
                _ = try root()
                let analysis = try await Task.detached { try NarrationNoiseAnalysis.analyze(room) }.value
                noiseAnalysis = analysis
                magicChoice = analysis.recommendedPreset.name
                cleanupSettings = analysis.recommendedPreset.settings
                previewOriginal = false
                busy = false
                if !cleanupPreviewRunning, edit != nil { toggleLiveCleanupPreview() }
                status = "Magic chose \(analysis.recommendedPreset.name). This is a starting point—adjust the knobs to taste."
            } catch { busy = false; status = error.localizedDescription }
        }
    }
    func suggestCleanupSettings() {
        guard !locked, let room = roomToneURL else { return }
        busy = true; status = "Analyzing the room-noise spectrum…"
        Task { [self] in
            defer { busy = false }
            do {
                _ = try root()
                let analysis = try await Task.detached { try NarrationNoiseAnalysis.analyze(room) }.value
                noiseAnalysis = analysis; cleanupSettings = analysis.suggested
                status = "Suggested settings loaded. Start Live Preview to listen and adjust."
            } catch { status = error.localizedDescription }
        }
    }
    func applyNoiseCleanup() {
        guard !locked, let current = edit, let project, let room = roomToneURL else { return }
        guard roomToneDeviceID == nil || roomToneDeviceID == currentMicrophoneID else {
            status = "The selected microphone changed. Capture a new room-noise sample."; return
        }
        busy = true; stop(); status = "Applying room-noise cleanup…"
        let settings = cleanupSettings
        Task { [self] in
            defer { busy = false }
            do {
                try checkStorage()
                let raw = project.appendingPathComponent(current.sourceName)
                let savedRoom = project.appendingPathComponent("room-noise-\(UUID().uuidString).wav")
                try FileManager.default.copyItem(at: room, to: savedRoom)
                let cleaned = project.appendingPathComponent("cleaned-\(UUID().uuidString).wav")
                try await Task.detached { try NarrationNoiseCleanup.render(source: raw, roomTone: savedRoom, destination: cleaned, settings: settings) }.value
                history.append(current); future = []
                edit?.roomToneDeviceID = roomToneDeviceID; edit?.cleanupAmount = settings.strength; edit?.cleanupSettings = settings
                edit?.roomToneName = savedRoom.lastPathComponent; edit?.cleanedSourceName = cleaned.lastPathComponent; edit?.useCleanedAudio = true
                roomToneURL = savedRoom
                waveform.load(source); try persist()
                status = "Cleanup ready. Toggle Use Cleaned Audio to compare; original audio and word timing are preserved."
            } catch { status = error.localizedDescription }
        }
    }
    func toggleCleanup(_ enabled: Bool) {
        guard !locked, let current = edit else { return }
        stop(); history.append(current); future = []; edit?.useCleanedAudio = enabled; waveform.load(source); save()
    }
    func clearPreparedExport() {
        if let url = preparedExport { try? FileManager.default.removeItem(at: url) }
        preparedExport = nil; exportLevels = nil
    }
    func prepareExport() {
        guard !locked, let edit, let source, let project else { return }
        clearPreparedExport(); busy = true; stop()
        exportSummary = "\(edit.useCleanedAudio == true ? "Cleaned audio" : "Original audio") · \(effects.plugins.filter { !$0.bypass }.count) active AU effects · \(Int(edit.joinCrossfadeMS ?? 0)) ms edit joins"
        status = "Preparing export and checking output levels…"
        Task { [self] in
            defer { busy = false }
            let staged = project.appendingPathComponent("export-review-\(UUID().uuidString).wav")
            do {
                try checkStorage()
                try await renderProcessed(source: source, edit: edit, destination: staged)
                let levels = try await Task.detached { try NarrationExport.analyze(staged) }.value
                preparedExport = staged; exportLevels = levels
                status = "Export ready. Preview volume is excluded."
            } catch { try? FileManager.default.removeItem(at: staged); status = "Could not prepare export: \(error.localizedDescription)" }
        }
    }
    func exportAudio() {
        guard !locked, let edit, let source, let preparedExport, let project else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.wav]; panel.nameFieldStringValue = "Voice Over.wav"
        panel.directoryURL = project
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let encoding = exportEncoding, gain = exportGainDB, ceiling = exportCeiling
        busy = true; stop()
        Task { [self] in
            defer { busy = false }
            do {
                try checkStorage()
                let destinationVolume = try destination.deletingLastPathComponent().resourceValues(forKeys: [.volumeURLKey]).volume?.standardizedFileURL.path
                guard destinationVolume == StoragePreference.record?.volumePath else { throw StudioError.message("Export to the selected storage volume.") }
                let protected = [source, project.appendingPathComponent(edit.sourceName), preparedExport, project.appendingPathComponent("preview.wav")] + [edit.roomToneName, edit.cleanedSourceName].compactMap { $0.map { project.appendingPathComponent($0) } }
                guard !protected.contains(where: { $0.resolvingSymlinksInPath() == destination.resolvingSymlinksInPath() }) else { throw StudioError.message("Choose a separate export file to preserve project audio.") }
                let staged = project.appendingPathComponent("export-\(UUID().uuidString).wav")
                defer { try? FileManager.default.removeItem(at: staged) }
                let result = try await Task.detached { try NarrationExport.write(source: preparedExport, destination: staged, encoding: encoding, gainDB: gain, ceiling: ceiling) }.value
                if FileManager.default.fileExists(atPath: destination.path) {
                    _ = try FileManager.default.replaceItemAt(destination, withItemAt: staged)
                } else { try FileManager.default.moveItem(at: staged, to: destination) }
                status = "Exported \(destination.lastPathComponent) · \(encoding.rawValue) · sample peak \(String(format: "%.1f", result.peakDB)) dBFS."
            } catch { status = error.localizedDescription }
        }
    }
}
