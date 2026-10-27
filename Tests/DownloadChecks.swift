import Foundation
import CryptoKit
@main struct DownloadChecks {
    static func run(_ artifact: ModelArtifact, _ file: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let worker = ModelTransfer(artifact: artifact, destination: file, progress: { _,_ in }, completion: { result in continuation.resume(with: result) })
            worker.start()
        }
    }
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if CommandLine.arguments.contains("--real") {
            let url = try await run(.ming, root.appendingPathComponent("ming-3.0-tts-0.5b-bf16.gguf"))
            print("REAL_INSTALL_PASSED \(url.path)"); return
        }
        let data = Data((0..<(256*4096)).map { UInt8($0 % 256) })
        let hash = SHA256.hash(data: data).map { String(format:"%02x",$0) }.joined()
        func artifact(_ endpoint: String) -> ModelArtifact { ModelArtifact(url: URL(string:"http://127.0.0.1:4349/\(endpoint)")!,size:Int64(data.count),sha256:hash) }
        let full = try await run(artifact("blob"),root.appendingPathComponent("full.gguf"))
        let fullBytes = try Data(contentsOf:full); precondition(fullBytes==data)
        print("PASS full download and checksum")
        for endpoint in ["blob","ignore-range"] {
            let file=root.appendingPathComponent("resume-\(endpoint).gguf")
            try data.prefix(120000).write(to:file.appendingPathExtension("partial"))
            let result=try await run(artifact(endpoint),file)
            let resumedBytes = try Data(contentsOf:result); precondition(resumedBytes==data)
            print("PASS resume \(endpoint)")
        }
        let bad=root.appendingPathComponent("bad.gguf")
        do { _ = try await run(artifact("bad"),bad);fatalError("Bad checksum accepted") }
        catch { precondition(!FileManager.default.fileExists(atPath:bad.path)); print("PASS checksum rejection") }
        _ = try await run(artifact("blob"),full)
        print("PASS verification of existing file without overwriting")
    }
}
