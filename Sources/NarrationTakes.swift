import Foundation
import Darwin

struct NarrationTake: Identifiable, Equatable {
    let id: Int
    let name: String
    let folder: URL
    let original: URL
    let duration: Double
}

/// The first take is the ordinary project. Later takes are self-contained projects beneath it.
enum NarrationTakes {
    static let directory = "ravenvo-takes"
    private static let metadata = "script-takes.json"

    struct Settings: Codable {
        var names: [Int: String] = [:]
        var favorite: Int?
        var script: String?
    }

    static func number(of folder: URL) -> Int? {
        let name = folder.lastPathComponent
        guard name.hasPrefix("Take-"), let n = Int(name.dropFirst(5)), n >= 2, n < Int.max,
              name == "Take-\(n)" else { return nil }
        return n
    }

    static func group(of folder: URL) -> URL {
        let parent = folder.deletingLastPathComponent()
        if parent.lastPathComponent == directory, number(of: folder) != nil {
            return parent.deletingLastPathComponent()
        }
        return folder
    }

    static func children(in group: URL) throws -> [URL] {
        let dir = group.appendingPathComponent(directory)
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { number(of: $0) != nil }
    }

    static func allocate(in group: URL) throws -> URL {
        let dir = group.appendingPathComponent(directory, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var n = (try children(in: group).compactMap(number).max() ?? 1) + 1
        while n < Int.max {
            let folder = dir.appendingPathComponent("Take-\(n)", isDirectory: true)
            if mkdir(folder.path, 0o755) == 0 { return folder }
            let code = errno
            guard code == EEXIST else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(code)) }
            n += 1
        }
        throw CocoaError(.fileWriteOutOfSpace)
    }

    static func settings(in group: URL) throws -> Settings {
        let url = group.appendingPathComponent(metadata)
        guard FileManager.default.fileExists(atPath: url.path) else { return Settings() }
        return try JSONDecoder().decode(Settings.self, from: Data(contentsOf: url))
    }

    static func update(in group: URL, _ change: (inout Settings) -> Void) throws {
        var settings = try settings(in: group)
        change(&settings)
        try JSONEncoder().encode(settings).write(to: group.appendingPathComponent(metadata), options: .atomic)
    }

    static func list(in group: URL, settings: Settings) throws -> [NarrationTake] {
        let folders = [group] + (try children(in: group))
        return try folders.compactMap { folder -> NarrationTake? in
            let project = folder.appendingPathComponent("project.ravenvo.json")
            guard FileManager.default.fileExists(atPath: project.path) else { return nil }
            let edit = try JSONDecoder().decode(NarrationEdit.self, from: Data(contentsOf: project))
            try edit.validate()
            let id = folder.path == group.path ? 1 : number(of: folder)!
            return NarrationTake(id: id, name: settings.names[id] ?? "Take \(id)", folder: folder,
                original: folder.appendingPathComponent(edit.sourceName), duration: edit.duration)
        }.sorted { $0.id < $1.id }
    }
}
