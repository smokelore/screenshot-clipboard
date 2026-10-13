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
    private let onFileEvent: (String) -> Void

    init(onFileEvent: @escaping (String) -> Void) { self.onFileEvent = onFileEvent }

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
            let wanted = FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRenamed | kFSEventStreamEventFlagItemRemoved)
            for i in 0..<count where flags[i] & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsFile) != 0 && flags[i] & wanted != 0
                && (paths[i] as NSString).deletingLastPathComponent == watcher.folder {
                watcher.onFileEvent(paths[i])
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

// Sits over the menu bar button so that dragging carries the latest capture out and clicking opens the menu.
final class StatusButtonOverlay: NSView, NSDraggingSource {
    var latestCapture: () -> URL? = { nil }
    var openMenu: () -> Void = {}

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let start = event.locationInWindow
        while let next = window.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
            if next.type == .leftMouseUp { openMenu(); return }
            let dx = next.locationInWindow.x - start.x, dy = next.locationInWindow.y - start.y
            if dx * dx + dy * dy > 16, let url = latestCapture() {
                beginDraggingSession(with: [draggingItem(for: url)], event: event, source: self)
                return
            }
        }
    }

    override func rightMouseDown(with event: NSEvent) { openMenu() }

    private func draggingItem(for url: URL) -> NSDraggingItem {
        let image = NSImage(contentsOf: url) ?? NSWorkspace.shared.icon(forFile: url.path)
        let width: CGFloat = 96, height = width * image.size.height / max(image.size.width, 1)
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(NSRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height), contents: image)
        return item
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}

final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "")
    private let pauseForHourItem = NSMenuItem(title: "Pause for 1 Hour", action: #selector(pauseForHour), keyEquivalent: "")
    private let openAtLoginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleOpenAtLogin), keyEquivalent: "")
    private let watcher: FolderWatcher
    private let menu = NSMenu()
    private let idleImage = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Screenshot Clipboard")
    private let copiedImage = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Copied")
    private var restoreIcon: DispatchWorkItem?
    private var copied: (path: String, changeCount: Int)?
    private var resumeTimer: Timer?

    private var pausedUntil: Date? { UserDefaults.standard.object(forKey: "pausedUntil") as? Date }

    private var isPaused: Bool {
        UserDefaults.standard.bool(forKey: "paused") || pausedUntil.map { $0 > Date() } ?? false
    }

    private func setPaused(_ paused: Bool, until: Date? = nil) {
        UserDefaults.standard.set(paused && until == nil, forKey: "paused")
        UserDefaults.standard.set(paused ? until : nil, forKey: "pausedUntil")
        resumeTimer?.invalidate()
        if paused, let until {
            resumeTimer = Timer.scheduledTimer(withTimeInterval: until.timeIntervalSinceNow, repeats: false) { [weak self] _ in
                self?.statusItem.button?.appearsDisabled = false
            }
        }
        statusItem.button?.appearsDisabled = isPaused
    }

    init(watcher: FolderWatcher) {
        self.watcher = watcher
        super.init()
        statusItem.button?.image = idleImage
        if let pausedUntil, pausedUntil > Date() { setPaused(true, until: pausedUntil) }
        statusItem.button?.appearsDisabled = isPaused
        menu.delegate = self
        menu.addItem(NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(pauseItem)
        menu.addItem(pauseForHourItem)
        menu.addItem(NSMenuItem(title: "Copy Latest", action: #selector(copyLatest), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open Folder", action: #selector(openFolder), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(openAtLoginItem)
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }

        guard let button = statusItem.button else { return }
        let overlay = StatusButtonOverlay(frame: button.bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.latestCapture = { [weak self] in self.flatMap { latestCapture(in: $0.watcher.folder) } }
        overlay.openMenu = { [weak self] in
            guard let self else { return }
            statusItem.menu = menu
            button.performClick(nil)
            statusItem.menu = nil
        }
        button.addSubview(overlay)
    }

    func handleFileEvent(_ path: String) {
        let pasteboard = NSPasteboard.general
        if !FileManager.default.fileExists(atPath: path) {
            if let copied, copied.path == path, copied.changeCount == pasteboard.changeCount { pasteboard.clearContents() }
            return
        }
        let url = URL(fileURLWithPath: path)
        guard !isPaused, isCapture(url), let date = captureDate(url), date.timeIntervalSinceNow > -10 else { return }
        copy(url)
    }

    private func copy(_ url: URL) {
        guard copyCapture(url) else { return }
        copied = (url.path, NSPasteboard.general.changeCount)
        flashIcon()
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
        pauseForHourItem.isHidden = isPaused
        openAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func togglePause() { setPaused(!isPaused) }

    @objc private func pauseForHour() { setPaused(true, until: Date().addingTimeInterval(3600)) }

    @objc private func toggleOpenAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            NSSound.beep()
        }
    }

    @objc private func copyLatest() {
        if let url = latestCapture(in: watcher.folder) { copy(url) }
    }

    @objc private func showAbout() {
        let repository = "https://github.com/smokelore/screenshot-clipboard"
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let credits = NSAttributedString(string: repository, attributes: [
            .link: URL(string: repository)!, .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .paragraphStyle: paragraph,
        ])
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
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
let watcher = FolderWatcher { menuBar?.handleFileEvent($0) }
menuBar = MenuBarController(watcher: watcher)
watcher.watch(screenshotFolder())
Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in watcher.watch(screenshotFolder()) }

app.run()
