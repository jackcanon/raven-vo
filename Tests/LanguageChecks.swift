import Foundation
@main struct LanguageChecks {
    @MainActor static func main() throws {
        let old = Data(#"{"title":"Legacy","script":"Hello","voice":"US_James","style":"warm"}"#.utf8)
        let legacy = try JSONDecoder().decode(Draft.self, from: old)
        precondition((legacy.language ?? "en") == "en")
        let oldTake = Data(#"{"title":"Legacy","script":"Hello","voice":"US_James","style":"warm","created":0}"#.utf8)
        let take = try JSONDecoder().decode(TakeInfo.self, from: oldTake)
        precondition((take.language ?? "en") == "en")
        let multilingualTake = TakeInfo(title: "Spanish", script: "Hola", voice: "natural", style: "", created: Date(), language: "es")
        let restoredTake = try JSONDecoder().decode(TakeInfo.self, from: JSONEncoder().encode(multilingualTake))
        precondition(restoredTake.language == "es")
        let model = StudioModel()
        let previous = model.draft
        defer { model.draft = previous }
        model.draft = legacy
        for language in SpeechLanguage.all {
            model.selectedLanguage = language.id
            precondition(Voice.choices(for: language.id).contains { $0.id == model.draft.voice })
            let decoded = try JSONDecoder().decode(Draft.self, from: JSONEncoder().encode(model.draft))
            precondition(decoded.language == language.id)
        }
        model.draft.voice = "US_Emma"
        model.selectedLanguage = "zh"
        precondition(model.draft.voice == "natural")
        precondition(Voice.chinese.count > 100)
        precondition(Set(Voice.chinese.map(\.id)).count == Voice.chinese.count)
        precondition(Voice.choices(for: "es").map(\.id) == ["natural", "designed"])
        model.draft.voice = "灵小柔"
        model.selectedLanguage = "en"
        precondition(model.draft.voice == "US_James")
        model.draft.voice = "designed"
        model.selectedLanguage = "ja"
        precondition(model.draft.voice == "designed")
        print("LANGUAGE_CHECKS_PASSED: legacy drafts, selection reset, persistence, unique Chinese catalogue, language filtering")
    }
}
