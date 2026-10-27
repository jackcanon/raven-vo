import Foundation
import AVFoundation

@main struct ModelChecks {
    @MainActor static func main() async throws {
        let model = StudioModel()
        let previous = model.draft
        guard model.available else { fatalError(model.availabilityMessage) }
        model.draft.script = ""
        precondition(!model.canGenerate, "Blank scripts must not generate")
        model.draft = Draft(title: "Desktop app verification", script: "Every story deserves to be heard. This voice was generated locally on this Mac.", voice: "US_James", style: "")
        model.saveDraft()
        let saved = try JSONDecoder().decode(Draft.self, from: Data(contentsOf: model.draftURL))
        precondition(saved == model.draft, "Script persistence failed")
        model.generate()
        guard model.isGenerating else { fatalError(model.errorMessage ?? "Generation failed to start") }
        for _ in 0..<600 {
            if !model.isGenerating { break }
            try await Task.sleep(for: .milliseconds(500))
        }
        guard !model.isGenerating, let take = model.selected, model.duration > 0, model.errorMessage == nil else { fatalError(model.errorMessage ?? "Generation did not finish") }
        let wav = try AVAudioFile(forReading: take.url)
        precondition(wav.length > 0)
        model.seek(1)
        precondition(model.position == 1)
        model.restoreSelectedScript()
        precondition(model.draft.title == "Desktop app verification")
        let successfulTake = take.url.path
        let historyCount = model.takes.count
        model.draft.script = String(repeating: "This is a cancellation test. ", count: 200)
        model.generate()
        try await Task.sleep(for: .milliseconds(700))
        model.cancel()
        for _ in 0..<100 {
            if !model.isGenerating { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        precondition(!model.isGenerating && model.status.contains("cancelled"))
        precondition(model.draft.script.contains("cancellation test"))
        precondition(model.takes.count == historyCount, "Cancelled output must not become a completed take")
        model.draft = previous
        model.saveDraft()
        let result: [String: Any] = ["result":"passed", "checks":["external volume present","blank-script guard","draft persistence","real Metal generation","valid WAV","playback loading and seek","saved script recovery","generation cancellation","cancelled output excluded from history"],"testTake":successfulTake,"duration":Double(wav.length)/wav.processingFormat.sampleRate]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted,.sortedKeys])
        try data.write(to: StudioModel.base.appendingPathComponent("DesktopApp/model-check-results.json"))
        print(String(decoding:data,as:UTF8.self))
    }
}
