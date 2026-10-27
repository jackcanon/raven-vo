import Foundation

struct StorageRecord: Codable {
    let path: String
    let volumePath: String
    let volumeUUID: String?
}
@MainActor enum StoragePreference {
    private static let key = "MingVoiceovers.storage.v1"
    static var record: StorageRecord? {
        if let data = UserDefaults.standard.data(forKey: key), let value = try? JSONDecoder().decode(StorageRecord.self, from: data) { return value }
        let original = URL(fileURLWithPath: "/Volumes/10TB JBOD/Work/Ming-Voiceovers")
        if FileManager.default.fileExists(atPath: original.path), let value = try? makeRecord(original), value.volumePath == "/Volumes/10TB JBOD" { return value }
        return nil
    }
    static var folder: URL? { record.map { URL(fileURLWithPath: $0.path, isDirectory: true) } }
    static var mounted: Bool {
        guard let saved = record else { return false }
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeUUIDStringKey], options: []) ?? []
        return volumes.contains { url in
            guard url.standardizedFileURL.path == saved.volumePath else { return false }
            if let id = saved.volumeUUID { return (try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString) == id }
            return true
        }
    }
    static func makeRecord(_ folder: URL) throws -> StorageRecord {
        let values = try folder.resourceValues(forKeys: [.volumeURLKey, .volumeUUIDStringKey])
        guard let volume = values.volume else { throw StudioError.message("Could not identify this storage volume.") }
        return StorageRecord(path: folder.standardizedFileURL.path, volumePath: volume.standardizedFileURL.path, volumeUUID: values.volumeUUIDString)
    }
    static func choose(_ folder: URL) throws {
        let record = try makeRecord(folder)
        UserDefaults.standard.set(try JSONEncoder().encode(record), forKey: key)
    }
}
