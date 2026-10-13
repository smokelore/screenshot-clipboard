import AppKit
import CoreServices

let folder = (NSHomeDirectory() as NSString).appendingPathComponent("Documents/Screenshots")

func copyIfNewScreenshot(_ path: String) {
    let name = (path as NSString).lastPathComponent
    guard name.lowercased().hasSuffix(".png"), !name.hasPrefix("."),
          let attributes = try? FileManager.default.attributesOfItem(atPath: path),
          let created = attributes[.creationDate] as? Date, created.timeIntervalSinceNow > -10,
          let data = FileManager.default.contents(atPath: path) else { return }
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setData(data, forType: .png)
}

let callback: FSEventStreamCallback = { _, _, count, paths, flags, _ in
    let paths = unsafeBitCast(paths, to: NSArray.self) as! [String]
    let wanted = FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRenamed)
    for i in 0..<count where flags[i] & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsFile) != 0 && flags[i] & wanted != 0 {
        copyIfNewScreenshot(paths[i])
    }
}

var context = FSEventStreamContext()
let stream = FSEventStreamCreate(
    nil, callback, &context, [folder] as CFArray,
    FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.05,
    FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
)!
FSEventStreamSetDispatchQueue(stream, .main)
FSEventStreamStart(stream)

NSApplication.shared.setActivationPolicy(.prohibited)
NSApplication.shared.run()
