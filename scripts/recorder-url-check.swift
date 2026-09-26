import Foundation

// Compile alongside ExerciseAnalyzer/FrameRecorder.swift on the Mac. No camera or writer is started.
@main
enum RecorderURLCheck {
  static func main() {
    let urls = (0..<100).map { _ in FrameRecorder().url }
    guard Set(urls).count == urls.count else {
      FileHandle.standardError.write(Data("recording segments share a URL\n".utf8))
      exit(1)
    }
    precondition(urls.allSatisfy { $0.pathExtension == "mov" })
    print("100 recording segments have distinct movie URLs")
  }
}
