import Foundation
import AVFoundation
import Speech
enum StudioError: LocalizedError { case message(String); var errorDescription: String? { if case let .message(value) = self { return value }; return nil } }
@main struct StreamingCheck {
 @MainActor static func main() async throws {
  guard #available(macOS 26.0, *) else {return}
  guard await SpeechTranscriber.installedLocales.contains(where: { $0.identifier.hasPrefix("en") }) else { print("SKIP: install English transcription assets in the app first"); return }
  let session = try await NarrationLiveTranscription.prepare(localeID:"en-US")
  let file = try AVAudioFile(forReading:URL(fileURLWithPath:CommandLine.arguments[1]))
  var submitted:Int64=0
  let began=Date()
  while file.framePosition < file.length {
   let buffer=AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:4096)!
   try file.read(into:buffer,frameCount:4096)
   if buffer.frameLength==0 {break}
   session.feed.append(buffer);submitted+=Int64(buffer.frameLength)
   try await Task.sleep(for:.milliseconds(30))
  }
  let stopped=Date()
  let words=try await session.finish()
  precondition(!words.isEmpty && session.feed.error==nil)
  print("PASS: background streaming, \(submitted) frames, \(words.count) timed units; finalization \(Date().timeIntervalSince(stopped)) seconds; total \(Date().timeIntervalSince(began)) seconds")
  print(words.map(\.text).joined(separator:" "))
 }
}
