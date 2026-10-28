import Foundation
import AVFoundation
@main struct ModelFlowChecks {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath:CommandLine.arguments[1]).appendingPathComponent(UUID().uuidString)
        let fm = FileManager.default
        try fm.createDirectory(at:root.appendingPathComponent("models"),withIntermediateDirectories:true)
        try fm.createDirectory(at:root.appendingPathComponent("samples"),withIntermediateDirectories:true)
        let name="RavenVO.Tests.\(UUID().uuidString)"
        StoragePreference.preferences=UserDefaults(suiteName:name)!
        defer { StoragePreference.preferences.removePersistentDomain(forName:name); StoragePreference.preferences = .standard }
        try StoragePreference.choose(root)
        try fm.createSymbolicLink(at:root.appendingPathComponent("models/ming-3.0-tts-0.5b-bf16.gguf"),withDestinationURL:URL(fileURLWithPath:CommandLine.arguments[2]))
        let model=StudioModel(engineOverride:URL(fileURLWithPath:CommandLine.arguments[3]),denoiserOverride:URL(fileURLWithPath:CommandLine.arguments[4]))
        model.yourVoice.denoiseEnabled = true
        model.yourVoice.install(URL(fileURLWithPath:CommandLine.arguments[5]))
        for _ in 0..<300 { if !model.yourVoice.busy { break };try await Task.sleep(for:.milliseconds(200)) }
        guard model.yourVoice.ready else { fatalError(model.yourVoice.error ?? "Voice sample did not prepare") }
        precondition(model.yourVoice.profile?.cleanupApplied == true)
        model.usesYourVoice=true
        model.draft.title="QA cloned-voice verification"
        model.draft.script="Every story deserves to be heard. This is a local voice reference test."
        precondition(model.canGenerate)
        model.generate()
        for _ in 0..<600 { if !model.isGenerating { break };try await Task.sleep(for:.milliseconds(500)) }
        guard let take=model.selected, model.errorMessage == nil, model.duration>0 else { fatalError(model.errorMessage ?? "Clone generation failed") }
        let info=try JSONDecoder().decode(TakeInfo.self,from:Data(contentsOf:take.url.deletingPathExtension().appendingPathExtension("json")))
        precondition(info.voice=="reference" && info.referenceFile==model.yourVoice.profile?.fileName)
        model.usesCustomVoice=true
        model.restoreSelectedScript()
        precondition(model.usesYourVoice && !model.usesCustomVoice)
        let script=model.draft.script
        model.playPause()
        model.deleteTake(take)
        for _ in 0..<200 { if !model.isDeleting { break };try await Task.sleep(for:.milliseconds(100)) }
        precondition(!fm.fileExists(atPath:take.url.path) && !model.isPlaying && model.selected == nil)
        precondition(model.draft.script==script && model.yourVoice.ready)
        model.shutdown()
        print("MODEL_FLOW_CHECKS_PASSED: isolated preferences, prepared/denoised voice, real Ming cloning, saved reference metadata, restored voice mode, delete while playing, draft and voice preservation")
    }
}
