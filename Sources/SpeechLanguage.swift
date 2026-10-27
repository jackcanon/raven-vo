struct SpeechLanguage: Identifiable {
    let id: String
    let name: String
    static func sample(for id: String) -> String {
        switch id {
        case "zh": return "你好，每一个故事都值得被听见。让我们一起创造难忘的时刻。"
        case "ja": return "こんにちは。すべての物語には価値があります。忘れられない瞬間を一緒に作りましょう。"
        case "ko": return "안녕하세요. 모든 이야기는 소중합니다. 잊지 못할 순간을 함께 만들어 보세요."
        case "de": return "Jede Geschichte verdient es, gehört zu werden. Gemeinsam schaffen wir unvergessliche Momente."
        case "fr": return "Chaque histoire mérite d’être entendue. Ensemble, créons des moments inoubliables."
        case "es": return "Cada historia merece ser escuchada. Juntos, creamos momentos inolvidables."
        default: return "Every story deserves to be heard. At Happy Jack Media, we bring real voices and unforgettable moments to life."
        }
    }
    static let all: [SpeechLanguage] = [
        .init(id: "en", name: "English"), .init(id: "zh", name: "Chinese · 中文"),
        .init(id: "ja", name: "Japanese · 日本語"), .init(id: "ko", name: "Korean · 한국어"),
        .init(id: "de", name: "German · Deutsch"), .init(id: "fr", name: "French · Français"),
        .init(id: "es", name: "Spanish · Español")
    ]
}
