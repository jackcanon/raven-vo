import Foundation

struct TrashedTakeFile: Sendable {
    let original: URL
    let trashed: URL
}

enum TakeDeletion {
    static func moveToTrash(_ audio: URL, in samples: URL, recycle: (URL) throws -> URL = trash) throws -> [TrashedTakeFile] {
        let root = samples.standardizedFileURL.resolvingSymlinksInPath()
        guard audio.pathExtension.lowercased() == "wav",
              audio.standardizedFileURL.deletingLastPathComponent().resolvingSymlinksInPath().path == root.path else {
            throw DeletionError("Only recordings in the selected recordings folder can be deleted.")
        }
        let fm = FileManager.default
        var files = [audio]
        let metadata = audio.deletingPathExtension().appendingPathExtension("json")
        if fm.fileExists(atPath: metadata.path) { files.append(metadata) }
        for file in files {
            let attributes = try fm.attributesOfItem(atPath: file.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                throw DeletionError("The recording or its saved settings are not regular files. Nothing was deleted.")
            }
        }
        var moved: [TrashedTakeFile] = []
        do {
            for file in files { moved.append(TrashedTakeFile(original: file, trashed: try recycle(file))) }
            return moved
        } catch {
            var recoveryFailed = false
            for file in moved.reversed() {
                do {
                    guard !fm.fileExists(atPath: file.original.path) else { throw DeletionError("The original filename is now occupied.") }
                    try fm.moveItem(at: file.trashed, to: file.original)
                } catch { recoveryFailed = true }
            }
            if recoveryFailed { throw DeletionError("The operation could not finish. Some files remain recoverable in the Trash; existing files were not overwritten.") }
            throw error
        }
    }
    private static func trash(_ file: URL) throws -> URL {
        var destination: NSURL?
        try FileManager.default.trashItem(at: file, resultingItemURL: &destination)
        guard let destination else { throw DeletionError("macOS moved the file to Trash but did not return its location. Check the Trash to recover it.") }
        return destination as URL
    }
    struct DeletionError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
