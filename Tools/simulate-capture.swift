// Usage: swift Tools/simulate-capture.swift <source file> [destination folder]
// Writes a copy of the source the way screencapture does (hidden file, then rename), reports how long the
// clipboard took to change and what it holds, then trashes the copy.
import AppKit

let args = CommandLine.arguments
guard args.count >= 2, let data = FileManager.default.contents(atPath: args[1]) else {
    print("usage: simulate-capture.swift <source file> [destination folder]"); exit(2)
}
let defaultFolder = (CFPreferencesCopyAppValue("location" as CFString, "com.apple.screencapture" as CFString) as? String) ?? "~/Desktop"
let folder = ((args.count >= 3 ? args[2] : defaultFolder) as NSString).expandingTildeInPath
let ext = (args[1] as NSString).pathExtension
let hidden = "\(folder)/.simulated-capture.\(ext)", final = "\(folder)/simulated-capture.\(ext)"

let pasteboard = NSPasteboard.general
pasteboard.clearContents()
pasteboard.setString("before", forType: .string)
let before = pasteboard.changeCount

FileManager.default.createFile(atPath: hidden, contents: data)
let start = Date()
try! FileManager.default.moveItem(atPath: hidden, toPath: final)
while pasteboard.changeCount == before && Date().timeIntervalSince(start) < 10 { usleep(5000) }

if pasteboard.changeCount == before {
    print("no clipboard change within 10 s")
} else {
    let types = pasteboard.pasteboardItems?.first?.types.map(\.rawValue).joined(separator: ", ") ?? ""
    print("clipboard changed after \(Int(Date().timeIntervalSince(start) * 1000)) ms: \(types)")
}
try? FileManager.default.trashItem(at: URL(fileURLWithPath: final), resultingItemURL: nil)
