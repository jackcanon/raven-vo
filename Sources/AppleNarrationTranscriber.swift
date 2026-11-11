import Speech
import AVFoundation

@available(macOS 26.0, *)
enum AppleNarrationTranscriber {
    static func transcribe(_ url: URL, localeID: String) async throws -> [NarrationWord] {
        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: localeID)) else {
            throw StudioError.message("Apple transcription is unavailable for this Mac or language.")
        }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let consumer = Task { () throws -> [NarrationWord] in
            var words: [NarrationWord] = []
            for try await result in transcriber.results {
                try Task.checkCancellation()
                for run in result.text.runs {
                    guard let timing = run.audioTimeRange else { continue }
                    let text = String(result.text[run.range].characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    let start = timing.start.seconds
                    let end = CMTimeRangeGetEnd(timing).seconds
                    if !text.isEmpty, start.isFinite, end.isFinite, end > start {
                        words.append(.init(text: text, start: start, end: end))
                    }
                }
            }
            return words
        }
        do {
            let file = try AVAudioFile(forReading: url)
            _ = try await analyzer.analyzeSequence(from: file)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            return try await consumer.value
        } catch {
            consumer.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }
}
