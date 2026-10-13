import AppKit
import CoreServices

func screenshotFolder() -> String {
    let domain = "com.apple.screencapture" as CFString
    CFPreferencesAppSynchronize(domain)
    let location = CFPreferencesCopyAppValue("location" as CFString, domain) as? String
    return ((location ?? "~/Desktop") as NSString).expandingTildeInPath
}

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

final class FolderWatcher {
    private(set) var folder = ""
    private var stream: FSEventStreamRef?
    private let onNewFile: (String) -> Void

    init(onNewFile: @escaping (String) -> Void) { self.onNewFile = onNewFile }

    func watch(_ path: String) {
        // FSEvents reports real paths such as /private/tmp, which NSString's symlink resolution strips.
        guard let resolved = realpath(path, nil) else { return }
        let path = String(cString: resolved)
        free(resolved)
        guard path != folder else { return }
        stop()
        folder = path
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info!).takeUnretainedValue()
            let paths = unsafeBitCast(paths, to: NSArray.self) as! [String]
            let wanted = FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRenamed)
            for i in 0..<count where flags[i] & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsFile) != 0 && flags[i] & wanted != 0
                && (paths[i] as NSString).deletingLastPathComponent == watcher.folder {
                watcher.onNewFile(paths[i])
            }
        }
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.05,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        ) else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}

let watcher = FolderWatcher(onNewFile: copyIfNewScreenshot)
watcher.watch(screenshotFolder())
Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in watcher.watch(screenshotFolder()) }

NSApplication.shared.setActivationPolicy(.prohibited)
NSApplication.shared.run()
