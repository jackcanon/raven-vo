import Foundation

/// Written before capture starts. Removed only after a readable recording has a saved project.
struct NarrationRecordingRecovery: Codable, Identifiable, Sendable {
    static let markerName = "recording-in-progress.json"
    var id: String { folder.path }
    var started: Date
    var deviceName: String
    var script: String
    var localeID: String
    var audioName: String = "original.wav"
    var folder: URL

    func write() throws {
        guard audioName == "original.wav" else { throw RecoveryError.invalidMarker }
        try JSONEncoder().encode(self).write(to: folder.appendingPathComponent(Self.markerName), options: .atomic)
    }
    static func pending(in root: URL) throws -> [Self] {
        let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        let groups = folders.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        let nested = try groups.flatMap { try NarrationTakes.children(in: $0) }
        return (groups + nested).compactMap { folder in
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let data = try? Data(contentsOf: folder.appendingPathComponent(markerName)),
                  var item = try? JSONDecoder().decode(Self.self, from: data), item.audioName == "original.wav" else { return nil }
            // Never trust a serialized absolute location after a project was moved.
            item.folder = folder
            return item
        }.sorted { $0.started > $1.started }
    }
    func complete() throws {
        let marker = folder.appendingPathComponent(Self.markerName)
        if FileManager.default.fileExists(atPath: marker.path) { try FileManager.default.removeItem(at: marker) }
    }
    enum RecoveryError: Error { case invalidMarker }
}
