import AVFoundation
import AudioToolbox
import CoreAudioKit
import AppKit
import Observation

struct NarrationPluginChoice: Identifiable {
    let name: String
    let description: AudioComponentDescription
    var id: String { "\(description.componentType)-\(description.componentSubType)-\(description.componentManufacturer)" }
}
@MainActor @Observable final class NarrationAudioUnits {
    var choices: [NarrationPluginChoice] = []
    var selectedID = ""
    var plugins: [NarrationPluginState] = []
    var loading = false
    var message = ""
    @ObservationIgnored private var units: [UUID: AVAudioUnit] = [:]
    @ObservationIgnored private var windows: [UUID: NSWindow] = [:]
    init() { refresh() }
    func refresh() {
        let pattern = AudioComponentDescription(componentType: kAudioUnitType_Effect, componentSubType: 0, componentManufacturer: 0, componentFlags: 0, componentFlagsMask: 0)
        choices = AVAudioUnitComponentManager.shared().components(matching: pattern).map { .init(name: $0.name, description: $0.audioComponentDescription) }.sorted { $0.name < $1.name }
        if !choices.contains(where: { $0.id == selectedID }) { selectedID = choices.first?.id ?? "" }
    }
    func add() async {
        guard !loading, let choice = choices.first(where: { $0.id == selectedID }) else { return }
        loading = true; defer { loading = false }
        do {
            let unit = try await AVAudioUnit.instantiate(with: choice.description, options: [])
            let plugin = NarrationPluginState(name: choice.name, type: choice.description.componentType, subtype: choice.description.componentSubType, manufacturer: choice.description.componentManufacturer)
            units[plugin.id] = unit; plugins.append(plugin); message = "Added \(choice.name). Save the project after adjusting its controls."
        } catch { message = "Could not load \(choice.name): \(error.localizedDescription)" }
    }
    func snapshot() throws -> [NarrationPluginState] {
        for index in plugins.indices {
            if let unit = units[plugins[index].id], let state = unit.auAudioUnit.fullStateForDocument {
                plugins[index].state = try PropertyListSerialization.data(fromPropertyList: state, format: .binary, options: 0)
            }
        }
        return plugins
    }
    func restore(_ states: [NarrationPluginState]) async {
        loading = true; defer { loading = false }
        for window in windows.values { window.close() }
        windows = [:]; units = [:]; plugins = states; message = ""
        for plugin in states {
            do {
                let unit = try await AVAudioUnit.instantiate(with: plugin.description, options: [])
                if let data = plugin.state, let state = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] { unit.auAudioUnit.fullStateForDocument = state }
                units[plugin.id] = unit
            } catch { message += "Unavailable: \(plugin.name). State retained. \(error.localizedDescription)\n" }
        }
    }
    func clear() { for window in windows.values { window.close() }; windows = [:]; units = [:]; plugins = []; message = "" }
    func remove(_ id: UUID) { windows[id]?.close(); windows[id] = nil; units[id] = nil; plugins.removeAll { $0.id == id } }
    func showEditor(_ id: UUID) {
        if let window = windows[id] { window.makeKeyAndOrderFront(nil); return }
        guard let unit = units[id] else { message = "This plugin is unavailable. Its saved state is preserved."; return }
        unit.auAudioUnit.requestViewController { [weak self] controller in
            Task { @MainActor in
                guard let self else { return }
                let editor = controller ?? AUGenericViewController()
                if let generic = editor as? AUGenericViewController { generic.auAudioUnit = unit.auAudioUnit }
                let window = NSWindow(contentViewController: editor)
                window.title = self.plugins.first(where: { $0.id == id })?.name ?? "Audio Unit"
                window.isReleasedWhenClosed = false
                if window.frame.width < 300 || window.frame.height < 150 { window.setContentSize(.init(width: 520, height: 400)) }
                self.windows[id] = window; window.makeKeyAndOrderFront(nil)
            }
        }
    }
    /// Fresh instances keep offline render state separate from open plugin editors.
    nonisolated static func render(source: URL, destination: URL, plugins: [NarrationPluginState], floatingPoint: Bool = false) async throws {
        let active = plugins.filter { !$0.bypass }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let file = try AVAudioFile(forReading: source)
        let format = file.processingFormat
        engine.attach(player)
        var previous: AVAudioNode = player
        var latency = 0.0
        var tail = 0.0
        var loaded: [AVAudioUnit] = []
        for plugin in active {
            let unit = try await AVAudioUnit.instantiate(with: plugin.description, options: [])
            if let data = plugin.state, let state = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] { unit.auAudioUnit.fullStateForDocument = state }
            unit.auAudioUnit.isRenderingOffline = true
            engine.attach(unit); engine.connect(previous, to: unit, format: format); previous = unit
            loaded.append(unit)
        }
        engine.connect(previous, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        let output = try autoreleasepool { try AVAudioFile(forWriting: destination, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: format.sampleRate, AVNumberOfChannelsKey: format.channelCount, AVLinearPCMBitDepthKey: floatingPoint ? 32 : 16, AVLinearPCMIsFloatKey: floatingPoint]) }
        defer { if #available(macOS 15.0, *) { output.close() } }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096) else { throw StudioError.message("Could not allocate effect render buffer.") }
        player.scheduleFile(file, at: nil, completionHandler: nil)
        try engine.start(); player.play()
        defer { player.stop(); engine.stop() }
        for unit in loaded { latency += unit.auAudioUnit.latency; tail += unit.auAudioUnit.tailTime }
        guard latency.isFinite, tail.isFinite, latency >= 0, tail >= 0, latency <= 30, tail <= 30 else { throw StudioError.message("This effect reports unsupported latency or tail length (maximum 30 seconds). Bypass it and retry.") }
        let skip = Int64((latency * format.sampleRate).rounded())
        let total = file.length + skip + Int64((tail * format.sampleRate).rounded())
        var position: Int64 = 0
        var retries = 0
        while position < total {
            try Task.checkCancellation()
            let count = AVAudioFrameCount(min(4096, total - position))
            let status = try engine.renderOffline(count, to: buffer)
            switch status {
            case .success:
                guard buffer.frameLength > 0 else { throw StudioError.message("Plugin render returned no audio.") }
                let frames = Int64(buffer.frameLength)
                let drop = min(frames, max(0, skip - position))
                if drop < frames {
                    if drop > 0, let channels = buffer.floatChannelData {
                        for channel in 0..<Int(format.channelCount) {
                            memmove(channels[channel], channels[channel].advanced(by: Int(drop)), Int(frames - drop) * MemoryLayout<Float>.size)
                        }
                        buffer.frameLength = AVAudioFrameCount(frames - drop)
                    }
                    try output.write(from: buffer)
                }
                position += frames; retries = 0
            case .cannotDoInCurrentContext, .insufficientDataFromInputNode:
                retries += 1
                guard retries < 100 else { throw StudioError.message("Plugin rendering stalled. Bypass the effect and retry.") }
            case .error: throw StudioError.message("Audio Unit rendering failed. Original audio is preserved.")
            @unknown default: throw StudioError.message("Unknown Audio Unit render status.")
            }
        }
    }
}
