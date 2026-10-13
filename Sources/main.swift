import AppKit
import CoreServices
import ServiceManagement

func screenshotFolder() -> String {
    let domain = "com.apple.screencapture" as CFString
    CFPreferencesAppSynchronize(domain)
    let location = CFPreferencesCopyAppValue("location" as CFString, domain) as? String
    return ((location ?? "~/Desktop") as NSString).expandingTildeInPath
}

func isCapture(_ url: URL) -> Bool {
    ["png", "mov"].contains(url.pathExtension.lowercased()) && !url.lastPathComponent.hasPrefix(".")
}

// A recording's file can be created when recording starts, so judge it by when it was last written.
func captureDate(_ url: URL) -> Date? {
    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
    return attributes?[url.pathExtension.lowercased() == "mov" ? .modificationDate : .creationDate] as? Date
}

// Escaped the way Terminal escapes a dragged-in file, so the pasted path works in a shell and in Claude Code.
func shellEscaped(_ path: String) -> String {
    let special = Set(" \\'\"()[]{}&;|<>*?$`!#~")
    return String(path.flatMap { special.contains($0) ? ["\\", $0] : [$0] })
}

@discardableResult
func copyCapture(_ url: URL) -> Bool {
    let item = NSPasteboardItem()
    if url.pathExtension.lowercased() == "png" {
        guard let data = FileManager.default.contents(atPath: url.path) else { return false }
        item.setData(data, forType: .png)
    }
    item.setString(url.absoluteString, forType: .fileURL)
    item.setString(shellEscaped(url.path), forType: .string)
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    return pasteboard.writeObjects([item])
}

func latestCapture(in folder: String) -> URL? {
    let urls = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: nil)) ?? []
    return urls.filter(isCapture).compactMap { url in captureDate(url).map { (url, $0) } }.max { $0.1 < $1.1 }?.0
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

final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "")
    private let openAtLoginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleOpenAtLogin), keyEquivalent: "")
    private let watcher: FolderWatcher
    private let idleImage = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Screenshot Clipboard")
    private let copiedImage = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Copied")
    private var restoreIcon: DispatchWorkItem?

    private var isPaused: Bool {
        get { UserDefaults.standard.bool(forKey: "paused") }
        set { UserDefaults.standard.set(newValue, forKey: "paused"); statusItem.button?.appearsDisabled = newValue }
    }

    init(watcher: FolderWatcher) {
        self.watcher = watcher
        super.init()
        statusItem.button?.image = idleImage
        statusItem.button?.appearsDisabled = isPaused
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(pauseItem)
        menu.addItem(NSMenuItem(title: "Copy Latest", action: #selector(copyLatest), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open Folder", action: #selector(openFolder), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(openAtLoginItem)
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
        statusItem.menu = menu
    }

    func handleNewFile(_ path: String) {
        let url = URL(fileURLWithPath: path)
        guard !isPaused, isCapture(url), let date = captureDate(url), date.timeIntervalSinceNow > -10 else { return }
        if copyCapture(url) { flashIcon() }
    }

    private func flashIcon() {
        statusItem.button?.image = copiedImage
        restoreIcon?.cancel()
        let restore = DispatchWorkItem { [weak self] in self?.statusItem.button?.image = self?.idleImage }
        restoreIcon = restore
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: restore)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        pauseItem.title = isPaused ? "Resume" : "Pause"
        openAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func togglePause() { isPaused.toggle() }

    @objc private func toggleOpenAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            NSSound.beep()
        }
    }

    @objc private func copyLatest() {
        if let url = latestCapture(in: watcher.folder), copyCapture(url) { flashIcon() }
    }

    @objc private func openFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: watcher.folder))
    }
}

let app = NSApplication.shared
if !UserDefaults.standard.bool(forKey: "openAtLoginConfigured") {
    try? SMAppService.mainApp.register()
    UserDefaults.standard.set(true, forKey: "openAtLoginConfigured")
}
var menuBar: MenuBarController?
let watcher = FolderWatcher { menuBar?.handleNewFile($0) }
menuBar = MenuBarController(watcher: watcher)
watcher.watch(screenshotFolder())
Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in watcher.watch(screenshotFolder()) }

app.run()
