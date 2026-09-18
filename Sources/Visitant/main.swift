// AppController + bootstrap.
//
// Architecture overview:
//   • This is a menu-bar-only app (.accessory activation policy = no Dock icon).
//   • A single floating NSWindow hosts a SwiftUI TranscriptView that overlays
//     whatever else is on screen.
//   • Mouse events are ignored by default so the overlay is click-through; the
//     user switches to "move mode" (⌃⌥M) to drag/resize it.
//   • Global hotkeys are registered via Carbon HIToolbox (the only public API for
//     system-wide key capture) and routed through HotkeyManager.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor

final class AppController: NSObject, NSApplicationDelegate {
    private let state = TranscriptState()
    private let settings: OverlaySettings
    private var window: NSWindow!
    private var hotkeys: HotkeyManager!
    private var statusItem: NSStatusItem!
    private var transcriptURL: URL?
    private var transcriptBookmarkData: Data?
    private var recentMenu: NSMenu?
    private var moveModeMenuItem: NSMenuItem?
    private var captureExclusionMenuItem: NSMenuItem?
    private var transparencySlider: NSSlider?
    private var transparencyValueLabel: NSTextField?

    private let recentBookmarksKey = "recentTranscriptBookmarks"
    private let panelOpacityKey = "panelOpacity"
    private let maxRecentPaths = 8
    private let minPanelOpacity = 0.25
    private let maxPanelOpacity = 0.90

    override init() {
        let saved = UserDefaults.standard.object(forKey: panelOpacityKey) as? Double
        let initialOpacity = min(max(saved ?? 0.62, minPanelOpacity), maxPanelOpacity)
        settings = OverlaySettings(panelOpacity: initialOpacity)
        super.init()
    }

    // Toggling interactive wires into applyInteractive() via didSet.
    private var interactive: Bool = false {
        didSet {
            applyInteractive()
            updateMoveModeMenuItem()
        }
    }

    private var captureExclusionEnabled: Bool = false {
        didSet {
            applyCaptureExclusion()
            updateCaptureExclusionMenuItem()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildWindow()
        let loadedFromArgs = loadFromArgs()
        buildStatusItem()
        hotkeys = HotkeyManager { [weak self] action in
            self?.handle(action)
        }
        if !loadedFromArgs && isAppBundleLaunch {
            DispatchQueue.main.async { [weak self] in self?.menuOpenFile() }
        }
    }

    private func buildWindow() {
        let rootView = TranscriptView(
            state: state,
            settings: settings
        )
        let hosting = NSHostingController(rootView: rootView)
        // .minSize lets SwiftUI enforce its minWidth/minHeight declared in the view,
        // but doesn't auto-resize when content changes — so user resizes stick.
        hosting.sizingOptions = NSHostingSizingOptions.minSize

        window = NSWindow(contentViewController: hosting)
        applyCaptureExclusion()
        window.styleMask = [.borderless, .resizable, .fullSizeContentView]
        window.isOpaque = false
        window.backgroundColor = .clear
        // System shadow: macOS computes it from the composited window content, so it
        // follows the rounded-rect shape (transparent corners cast no shadow).
        window.hasShadow = true
        window.level = .floating
        // canJoinAllSpaces: visible on every Space.
        // stationary: doesn't slide with Space transitions.
        // fullScreenAuxiliary: stays visible when another app goes full-screen.
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        // Click-through by default so the overlay doesn't steal focus or input.
        window.ignoresMouseEvents = true
        // Disabled initially; applyInteractive() enables it in move mode.
        window.isMovableByWindowBackground = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false

        // Initial size + position. Width 620 is comfortable for ~80-char steps;
        // height comes from SwiftUI's fitting size on first layout.
        let initialWidth: CGFloat = 620
        let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let fitting = hosting.sizeThatFits(in: NSSize(width: initialWidth, height: .greatestFiniteMagnitude))
        // Clamp height: sizeThatFits can return unexpectedly large values before first layout.
        // Cap at 260 so the window opens as a compact panel rather than filling the screen.
        let initialSize = NSSize(
            width: initialWidth,
            height: min(max(fitting.height, 180), 260)
        )
        window.setContentSize(initialSize)
        window.setFrameOrigin(NSPoint(
            x: screenFrame.midX - initialSize.width / 2,
            y: screenFrame.maxY - initialSize.height - 8
        ))

        window.orderFrontRegardless()
    }

    private var isAppBundleLaunch: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    private func loadFromArgs() -> Bool {
        guard let url = transcriptURL(fromLaunchArguments: Array(CommandLine.arguments.dropFirst())) else { return false }
        loadTranscript(url: url, remember: false)
        return true
    }

    private func transcriptURL(fromLaunchArguments args: [String]) -> URL? {
        var treatsRemainingArgumentsAsPaths = false
        var index = args.startIndex

        while index < args.endIndex {
            let arg = args[index]

            if treatsRemainingArgumentsAsPaths {
                return transcriptURL(fromPathArgument: arg)
            }

            if arg == "--" {
                treatsRemainingArgumentsAsPaths = true
                index = args.index(after: index)
                continue
            }

            if arg.hasPrefix("-") {
                index = indexAfterLaunchOption(startingAt: index, in: args)
                continue
            }

            return transcriptURL(fromPathArgument: arg)
        }

        return nil
    }

    private func transcriptURL(fromPathArgument path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    private func indexAfterLaunchOption(startingAt index: Array<String>.Index, in args: [String]) -> Array<String>.Index {
        let nextIndex = args.index(after: index)
        guard nextIndex < args.endIndex else { return nextIndex }

        let option = args[index]
        if option.hasPrefix("--") && option.contains("=") || option.hasPrefix("-psn_") {
            return nextIndex
        }

        let nextArgument = args[nextIndex]
        if launchOptionConsumesValue(option, nextArgument: nextArgument) {
            return args.index(after: nextIndex)
        }

        return nextIndex
    }

    private func launchOptionConsumesValue(_ option: String, nextArgument: String) -> Bool {
        if [
            "-NSDocumentRevisionsDebugMode",
            "-ApplePersistenceIgnoreState",
            "-NSQuitAlwaysKeepsWindows",
        ].contains(option) {
            return true
        }

        if ["YES", "NO", "TRUE", "FALSE", "true", "false"].contains(nextArgument) {
            return true
        }

        return option.hasPrefix("-NS") && !nextArgument.hasPrefix("-")
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "captions.bubble",
                accessibilityDescription: "Visitant"
            )
        }

        let menu = NSMenu()
        @discardableResult
        func add(_ title: String, _ selector: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            return item
        }

        add("Play / Pause   ⌃⌥Space", #selector(menuPlayPause))
        add("Next                  ⌃⌥→", #selector(menuNext))
        add("Previous           ⌃⌥←", #selector(menuPrev))
        add("Restart              ⌃⌥R", #selector(menuRestart))
        menu.addItem(.separator())
        add("Show / Hide      ⌃⌥H", #selector(menuToggleHide))
        moveModeMenuItem = add("Move Mode      ⌃⌥M", #selector(menuToggleMove))
        updateMoveModeMenuItem()
        let captureItem = NSMenuItem(
            title: "Hide From Screen Capture   ⌃⌥C",
            action: #selector(menuToggleCaptureExclusion),
            keyEquivalent: ""
        )
        captureItem.target = self
        captureExclusionMenuItem = captureItem
        menu.addItem(captureItem)
        updateCaptureExclusionMenuItem()
        menu.addItem(makeTransparencyMenuItem())
        menu.addItem(.separator())
        add("Open Transcript…", #selector(menuOpenFile))
        let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: "Open Recent")
        recentItem.submenu = recentMenu
        self.recentMenu = recentMenu
        menu.addItem(recentItem)
        rebuildRecentMenu()
        add("Reload Transcript", #selector(menuReload))
        add("Help / About", #selector(menuShowHelp))
        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit                       ⌃⌥Q",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        // target = nil routes the action up the responder chain to NSApp.
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func menuPlayPause() { state.playPause() }
    @objc private func menuNext() { state.next() }
    @objc private func menuPrev() { state.prev() }
    @objc private func menuRestart() { state.restart() }
    @objc private func menuToggleHide() {
        if window.isVisible { window.orderOut(nil) } else { window.orderFrontRegardless() }
    }
    @objc private func menuToggleMove() { interactive.toggle() }
    @objc private func menuToggleCaptureExclusion() { captureExclusionEnabled.toggle() }
    @objc private func menuTransparencyChanged(_ sender: NSSlider) {
        settings.panelOpacity = 1.0 - sender.doubleValue
        UserDefaults.standard.set(settings.panelOpacity, forKey: panelOpacityKey)
        updateTransparencyValueLabel()
    }
    @objc private func menuOpenFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText, .plainText]
        panel.title = "Open Transcript"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadTranscript(url: url, remember: true)
    }

    @objc private func menuReload() {
        if let bookmarkData = transcriptBookmarkData {
            loadBookmarkedTranscript(bookmarkData, remember: false)
        } else if let url = transcriptURL {
            loadTranscript(url: url, remember: false)
        }
    }

    @objc private func menuOpenRecent(_ sender: NSMenuItem) {
        guard let bookmarkData = sender.representedObject as? Data else { return }
        loadBookmarkedTranscript(bookmarkData, remember: true)
    }

    @objc private func menuClearRecent() {
        UserDefaults.standard.removeObject(forKey: recentBookmarksKey)
        rebuildRecentMenu()
    }

    @objc private func menuShowHelp() {
        let alert = NSAlert()
        alert.messageText = "Visitant"
        alert.informativeText = """
        A local teleprompter overlay for demos.

        Transcript lines use Markdown list items, with optional timers like:
        - Open the page [3s]
        - Wait for manual next

        Hotkeys: ⌃⌥Space play/pause, ⌃⌥→ next, ⌃⌥← previous, ⌃⌥R restart, ⌃⌥H hide/show, ⌃⌥M move mode, ⌃⌥C hide from screen capture, ⌃⌥Q quit.

        Move mode makes the overlay clickable and shows the blue indicator. "Hide From Screen Capture" is a best-effort presenter aid and is not a privacy guarantee.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func loadTranscript(url: URL, bookmarkData: Data? = nil, remember: Bool) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        state.load(url: url)
        guard state.sourceError == nil else {
            transcriptURL = nil
            transcriptBookmarkData = nil
            return
        }

        transcriptURL = url
        let bookmark = bookmarkData ?? (remember ? makeBookmark(for: url) : nil)
        transcriptBookmarkData = bookmark
        if remember, let bookmark {
            rememberRecent(bookmarkData: bookmark)
        }
    }

    private func loadBookmarkedTranscript(_ bookmarkData: Data, remember: Bool) {
        guard let resolved = resolveBookmark(bookmarkData) else {
            removeRecent(bookmarkData: bookmarkData)
            state.sourceError = "load failed: transcript access is no longer available"
            return
        }

        guard FileManager.default.fileExists(atPath: resolved.url.path) else {
            removeRecent(bookmarkData: bookmarkData)
            state.sourceError = "load failed: transcript file is missing"
            return
        }

        loadTranscript(url: resolved.url, bookmarkData: resolved.bookmarkData, remember: remember)
    }

    private func makeBookmark(for url: URL) -> Data? {
        do {
            return try url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            state.sourceError = "could not remember transcript: \(error.localizedDescription)"
            return nil
        }
    }

    private func resolveBookmark(_ bookmarkData: Data) -> (url: URL, bookmarkData: Data)? {
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale, let refreshed = makeBookmark(for: url) {
                replaceRecent(oldBookmarkData: bookmarkData, newBookmarkData: refreshed)
                return (url, refreshed)
            }

            return (url, bookmarkData)
        } catch {
            return nil
        }
    }

    private func rememberRecent(bookmarkData: Data) {
        var bookmarks = recentBookmarks().filter { $0 != bookmarkData }
        bookmarks.insert(bookmarkData, at: 0)
        if bookmarks.count > maxRecentPaths {
            bookmarks = Array(bookmarks.prefix(maxRecentPaths))
        }
        UserDefaults.standard.set(bookmarks, forKey: recentBookmarksKey)
        rebuildRecentMenu()
    }

    private func recentBookmarks() -> [Data] {
        UserDefaults.standard.array(forKey: recentBookmarksKey) as? [Data] ?? []
    }

    private func replaceRecent(oldBookmarkData: Data, newBookmarkData: Data) {
        let bookmarks = recentBookmarks().map { $0 == oldBookmarkData ? newBookmarkData : $0 }
        UserDefaults.standard.set(bookmarks, forKey: recentBookmarksKey)
    }

    private func removeRecent(bookmarkData: Data) {
        let bookmarks = recentBookmarks().filter { $0 != bookmarkData }
        UserDefaults.standard.set(bookmarks, forKey: recentBookmarksKey)
        rebuildRecentMenu()
    }

    private func rebuildRecentMenu() {
        guard let recentMenu else { return }
        recentMenu.removeAllItems()

        let bookmarks = recentBookmarks()
        if bookmarks.isEmpty {
            let empty = NSMenuItem(title: "No Recent Transcripts", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            recentMenu.addItem(empty)
            return
        }

        var validBookmarks: [Data] = []
        for bookmarkData in bookmarks {
            guard let resolved = resolveBookmark(bookmarkData) else { continue }
            validBookmarks.append(resolved.bookmarkData)
            let url = resolved.url
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(menuOpenRecent(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = resolved.bookmarkData
            item.toolTip = url.path
            recentMenu.addItem(item)
        }

        if validBookmarks.count != bookmarks.count {
            UserDefaults.standard.set(validBookmarks, forKey: recentBookmarksKey)
        }

        if validBookmarks.isEmpty {
            let empty = NSMenuItem(title: "No Recent Transcripts", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            recentMenu.addItem(empty)
            return
        }

        recentMenu.addItem(.separator())
        let clear = NSMenuItem(title: "Clear Menu", action: #selector(menuClearRecent), keyEquivalent: "")
        clear.target = self
        recentMenu.addItem(clear)
    }

    private func handle(_ action: HotkeyManager.Action) {
        switch action {
        case .playPause: state.playPause()
        case .next: state.next()
        case .prev: state.prev()
        case .restart: state.restart()
        case .toggleHide:
            if window.isVisible { window.orderOut(nil) } else { window.orderFrontRegardless() }
        case .toggleMove:
            interactive.toggle()
        case .toggleCaptureExclusion:
            captureExclusionEnabled.toggle()
        case .quit:
            NSApp.terminate(nil)
        }
    }

    private func applyInteractive() {
        settings.interactive = interactive
        window.ignoresMouseEvents = !interactive
        window.isMovableByWindowBackground = interactive
    }

    private func applyCaptureExclusion() {
        guard window != nil else { return }
        // Best-effort request to keep the overlay out of screen capture. Modern
        // macOS capture stacks may still include it, so this is not a privacy boundary.
        window.sharingType = captureExclusionEnabled ? .none : .readOnly
    }

    private func updateCaptureExclusionMenuItem() {
        captureExclusionMenuItem?.state = captureExclusionEnabled ? .on : .off
    }

    private func updateMoveModeMenuItem() {
        moveModeMenuItem?.state = interactive ? .on : .off
    }

    private func makeTransparencyMenuItem() -> NSMenuItem {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 46))

        let title = NSTextField(labelWithString: "Window transparency")
        title.font = .systemFont(ofSize: 12)
        title.frame = NSRect(x: 14, y: 26, width: 140, height: 16)
        container.addSubview(title)

        let value = NSTextField(labelWithString: "")
        value.alignment = .right
        value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        value.frame = NSRect(x: 164, y: 26, width: 56, height: 16)
        transparencyValueLabel = value
        container.addSubview(value)

        let slider = NSSlider(
            value: 1.0 - settings.panelOpacity,
            minValue: 1.0 - maxPanelOpacity,
            maxValue: 1.0 - minPanelOpacity,
            target: self,
            action: #selector(menuTransparencyChanged(_:))
        )
        slider.isContinuous = true
        slider.frame = NSRect(x: 12, y: 5, width: 214, height: 20)
        transparencySlider = slider
        container.addSubview(slider)

        updateTransparencyValueLabel()

        let item = NSMenuItem()
        item.view = container
        return item
    }

    private func updateTransparencyValueLabel() {
        transparencyValueLabel?.stringValue = "\(Int(round((1.0 - settings.panelOpacity) * 100)))%"
    }
}

// Bootstrap: NSApplication.run() blocks the main thread, so we use
// MainActor.assumeIsolated to satisfy Swift's strict concurrency — main.swift
// always runs on the main thread before the run loop starts.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let controller = AppController()
    app.delegate = controller
    app.setActivationPolicy(.accessory)  // hide from Dock and app switcher
    app.run()
}
