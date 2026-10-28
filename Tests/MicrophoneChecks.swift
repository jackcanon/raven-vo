import Foundation

@main struct MicrophoneChecks {
    @MainActor static func main() async throws {
        let devices = await Task.detached { MicrophoneCapture.choices() }.value
        precondition(Set(devices.map(\.id)).count == devices.count)
        precondition(devices.allSatisfy { !$0.id.isEmpty && !$0.name.isEmpty })
        let capture = MicrophoneCapture()
        var rejected = false
        do {
            try await capture.start(deviceID: "ravenvo-missing-device-\(UUID())", url: URL(fileURLWithPath: CommandLine.arguments[1]), onLevel: { _, _ in
                fatalError("Missing microphone must not capture")
            }, onFinish: { _, _ in fatalError("Missing microphone must not record") })
        } catch { rejected = error.localizedDescription.contains("unavailable") }
        precondition(rejected)
        print("MICROPHONE_CHECKS_PASSED: \(devices.count) named input devices; missing selection rejected without fallback or recording")
    }
}
