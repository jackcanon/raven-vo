import Foundation
@main struct TakeDeletionChecks {
    static func main() throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(UUID().uuidString)
        let samples = root.appendingPathComponent("samples")
        try fm.createDirectory(at: samples, withIntermediateDirectories: true)
        let audio = samples.appendingPathComponent("fixture.wav")
        let metadata = samples.appendingPathComponent("fixture.json")
        let note = samples.appendingPathComponent("fixture.txt")
        let original = Data("test recording".utf8)
        try original.write(to: audio); try Data("{}".utf8).write(to: metadata); try Data("keep".utf8).write(to: note)
        let moved = try TakeDeletion.moveToTrash(audio, in: samples)
        precondition(moved.count == 2 && !fm.fileExists(atPath: audio.path) && !fm.fileExists(atPath: metadata.path))
        precondition(fm.fileExists(atPath: note.path))
        for file in moved { precondition(fm.fileExists(atPath: file.trashed.path)); try fm.moveItem(at: file.trashed, to: file.original) }
        var count = 0
        do {
            _ = try TakeDeletion.moveToTrash(audio, in: samples) { file in
                count += 1
                if count == 2 { throw TakeDeletion.DeletionError("Simulated metadata failure") }
                let target = root.appendingPathComponent("temporary-trash.wav")
                try fm.moveItem(at: file, to: target)
                return target
            }
            fatalError("Expected failure")
        } catch { }
        let restored = try Data(contentsOf: audio)
        precondition(restored == original)
        precondition(fm.fileExists(atPath: metadata.path))
        let outside = root.appendingPathComponent("outside.wav"); try original.write(to: outside)
        do { _ = try TakeDeletion.moveToTrash(outside, in: samples); fatalError("Outside path accepted") } catch { }
        precondition(fm.fileExists(atPath: outside.path))
        let alias = samples.appendingPathComponent("alias.wav"); try fm.createSymbolicLink(at: alias, withDestinationURL: outside)
        do { _ = try TakeDeletion.moveToTrash(alias, in: samples); fatalError("Symlink accepted") } catch { }
        precondition(fm.fileExists(atPath: outside.path))
        print("TAKE_DELETION_CHECKS_PASSED: real Trash/recovery, paired metadata, unrelated file preservation, rollback, path and symlink guards")
    }
}
