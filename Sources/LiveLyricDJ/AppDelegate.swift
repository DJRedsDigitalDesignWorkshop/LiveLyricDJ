import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var windowController: BannerWindowController?
    private var seratoServer: SeratoServer?
    private var deckControllers: [DeckController] = []
    private var statusItem: NSStatusItem?
    private var bannerMenu: NSMenu?
    private var lyricsHotKey: LyricsHotKey?
    private let app = AppState()
    private var ticker: Timer?
    private var decks: [DeckState] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let deckA = DeckState(label: "A")
        let deckB = DeckState(label: "B")
        decks = [deckA, deckB]
        deckControllers = [
            DeckController(deckIndex: 0, state: deckA),
            DeckController(deckIndex: 1, state: deckB),
        ]

        windowController = BannerWindowController(app: app, deckA: deckA, deckB: deckB)

        #if DEBUG
        if CommandLine.arguments.contains("--preview") || Bundle.main.object(forInfoDictionaryKey: "LiveLyricDJPreview") as? Bool == true {
            deckA.title = "Soundcheck"
            deckA.artist = "LiveLyricDJ"
            deckA.hasTrack = true
            deckA.setLyrics(.synced((0..<12).map { LyricLine(timeMs: $0 * 4000, text: ["Current lyric — ready for the next mix", "The next line stays in view", "Resize the banner to see more"][ $0 % 3 ]) }))
            deckA.updatePlayhead(positionSeconds: 1, playRate: 0, bpm: 120)
            deckB.title = "Second deck"
            deckB.artist = "Preview"
            deckB.hasTrack = true
            deckB.setLyrics(.synced([LyricLine(timeMs: 0, text: "Your next track, on the right"), LyricLine(timeMs: 4000, text: "Independent timing for each deck")]))
            setupStatusItem()
            setupMainMenu()
            return
        }
        #endif

        lyricsHotKey = LyricsHotKey { [weak self] in self?.toggleLyricsVisibility() }

        let server = SeratoServer()
        server.delegate = self
        server.start()
        seratoServer = server

        setupStatusItem()
        setupMainMenu()

        // 10 Hz ticker: keeps lyric lines advancing smoothly between
        // playhead updates by extrapolating from the last play rate.
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                for deck in self.decks {
                    deck.extrapolate()
                }
            }
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let menuIconURL = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png")
            button.image = menuIconURL.flatMap(NSImage.init(contentsOf:))
                ?? NSImage(systemSymbolName: "text.quote", accessibilityDescription: "LiveLyricDJ")
            button.image?.size = NSSize(width: 18, height: 18)
            button.image?.isTemplate = false
            button.toolTip = "LiveLyricDJ controls: resize, lyric timing, position, and quit"
        }
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(NSMenuItem(title: "Unlock to Move / Resize", action: #selector(toggleDragMode), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Make Room for Lyrics…", action: #selector(makeRoomForLyrics), keyEquivalent: ""))
        let visibility = NSMenuItem(title: "Hide Lyrics", action: #selector(toggleLyricsVisibility), keyEquivalent: "l")
        visibility.keyEquivalentModifierMask = [.control, .option]
        visibility.tag = 1001
        menu.addItem(visibility)
        menu.addItem(NSMenuItem(title: "Snap to Top", action: #selector(snapToTop), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Reset Banner Size", action: #selector(resetBannerSize), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Retry Lyrics", action: #selector(retryLyrics), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        for (index, label) in ["A", "B"].enumerated() {
            let parent = NSMenuItem(title: "Deck \(label) Lyric Timing", action: nil, keyEquivalent: "")
            let timing = NSMenu()
            for (title, delta) in [("Show Lyrics Earlier (0.5s)", 500), ("Show Lyrics Later (0.5s)", -500), ("Reset Timing", 0)] {
                let entry = NSMenuItem(title: title, action: #selector(adjustTiming(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = [index, delta]
                timing.addItem(entry)
            }
            parent.submenu = timing
            menu.addItem(parent)
        }
        menu.addItem(NSMenuItem.separator())
        let layoutStatus = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        layoutStatus.tag = 1000
        menu.addItem(layoutStatus)
        menu.addItem(NSMenuItem(title: "Quit LiveLyricDJ", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appMenu = NSMenu(title: "LiveLyricDJ")
        appMenu.minimumWidth = 202
        appMenu.addItem(opaqueMenuItem(
            "About LiveLyricDJ",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:))
        ))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(opaqueMenuItem(
            "Hide LiveLyricDJ",
            shortcut: "⌘H",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        ))
        appMenu.addItem(opaqueMenuItem(
            "Hide Others",
            shortcut: "⌥⌘H",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h",
            modifiers: [.command, .option]
        ))
        appMenu.addItem(opaqueMenuItem(
            "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:))
        ))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(opaqueMenuItem(
            "Quit LiveLyricDJ",
            shortcut: "⌘Q",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        let appMenuItem = NSMenuItem(title: "LiveLyricDJ", action: nil, keyEquivalent: "")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        // Keep banner controls discoverable from the normal app menu as well
        // as the menu-bar icon, including when menu-bar space is limited.
        let controls = NSMenu(title: "Banner")
        controls.delegate = self
        for source in statusItem?.menu?.items ?? [] {
            if source.action == #selector(NSApplication.terminate(_:)) { continue }
            if let copied = source.copy() as? NSMenuItem { controls.addItem(copied) }
        }
        let controlsItem = NSMenuItem(title: "Banner", action: nil, keyEquivalent: "")
        controlsItem.submenu = controls
        mainMenu.addItem(controlsItem)
        bannerMenu = controls
        NSApp.mainMenu = mainMenu
    }

    private func opaqueMenuItem(
        _ title: String,
        shortcut: String = "",
        action: Selector,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = modifiers
        item.view = OpaqueMenuRow(title: title, shortcut: shortcut, action: action)
        return item
    }

    @objc private func toggleDragMode() {
        guard let windowController else { return }
        windowController.setDragMode(!app.dragMode)
        let title = app.dragMode ? "Lock Banner" : "Unlock to Move / Resize"
        statusItem?.menu?.item(at: 0)?.title = title
        bannerMenu?.item(at: 0)?.title = title
    }

    @objc private func adjustTiming(_ sender: NSMenuItem) {
        guard let values = sender.representedObject as? [Int], values.count == 2,
              decks.indices.contains(values[0]) else { return }
        let deck = decks[values[0]]
        if values[1] == 0 {
            deck.resetLyricOffset()
        } else {
            deck.adjustLyricOffset(by: values[1])
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.item(withTag: 1000)?.title = app.bannerObstructed
            ? "Hidden to keep Serato controls clear — choose Make Room"
            : "Lyrics stay outside Serato’s window"
        menu.item(withTag: 1001)?.title = app.bannerManuallyHidden ? "Show Lyrics" : "Hide Lyrics"
    }

    @objc private func toggleLyricsVisibility() {
        windowController?.toggleVisibility()
    }

    @objc private func makeRoomForLyrics() {
        guard let controller = windowController else { return }
        controller.positionAtTop()
        let result = SeratoWorkspace.makeRoom(bannerFrame: controller.panel.frame)
        switch result {
        case .success:
            app.bannerManuallyHidden = false
            controller.setDragMode(false)
            statusItem?.menu?.item(at: 0)?.title = "Unlock to Move / Resize"
            bannerMenu?.item(at: 0)?.title = "Unlock to Move / Resize"
            controller.updateVisibility()
        case .needsAccessibility:
            let alert = NSAlert()
            alert.messageText = "Make room above Serato"
            alert.informativeText = "To move and resize Serato automatically, allow LiveLyricDJ in System Settings → Privacy & Security → Accessibility, then choose Make Room again. You can also move Serato below the banner yourself. Lyrics stay hidden whenever they would cover Serato."
            alert.addButton(withTitle: "Open Accessibility Settings")
            alert.addButton(withTitle: "Arrange Manually")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        default:
            let alert = NSAlert()
            alert.messageText = "Arrange Serato below the lyrics"
            alert.informativeText = "Serato could not be fitted automatically. Exit fullscreen and leave room above its window, or reduce the banner size. Lyrics will appear when they have space without covering Serato’s controls."
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func resetBannerSize() {
        windowController?.resetSize()
    }

    @objc private func retryLyrics() {
        deckControllers.forEach { $0.reloadLyrics() }
    }

    @objc private func snapToTop() {
        windowController?.positionAtTop()
    }
}

private final class OpaqueMenuRow: NSView {
    private let title: String
    private let shortcut: String
    private let action: Selector
    private var isHighlighted = false { didSet { needsDisplay = true } }
    private var trackingArea: NSTrackingArea?

    init(title: String, shortcut: String, action: Selector) {
        self.title = title
        self.shortcut = shortcut
        self.action = action
        super.init(frame: NSRect(x: 0, y: 0, width: 202, height: 30))
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isOpaque: Bool { true }

    override func updateTrackingAreas() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHighlighted = true }
    override func mouseExited(with event: NSEvent) { isHighlighted = false }

    override func mouseDown(with event: NSEvent) {
        NSApp.sendAction(action, to: nil, from: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        (isHighlighted ? NSColor.controlAccentColor : NSColor(calibratedWhite: 0.14, alpha: 1)).setFill()
        bounds.fill()

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuFont(ofSize: 13),
            .foregroundColor: isHighlighted ? NSColor.selectedMenuItemTextColor : NSColor.white,
        ]
        title.draw(at: NSPoint(x: 12, y: 8), withAttributes: titleAttributes)
        guard !shortcut.isEmpty else { return }
        let shortcutSize = shortcut.size(withAttributes: titleAttributes)
        shortcut.draw(
            at: NSPoint(x: bounds.maxX - shortcutSize.width - 12, y: 8),
            withAttributes: titleAttributes
        )
    }
}

extension AppDelegate: SeratoServerDelegate {
    func seratoConnectionStateChanged(connected: Bool) {
        app.seratoConnected = connected
        if !connected { decks.forEach { $0.stopExtrapolating() } }
        print("[Serato] \(connected ? "connected" : "disconnected")")
    }

    func seratoDeck(deck: Int, title: String) {
        guard let c = controller(for: deck) else { return }
        c.handleTitle(title)
    }

    func seratoDeck(deck: Int, artist: String) {
        guard let c = controller(for: deck) else { return }
        c.handleArtist(artist)
    }

    func seratoDeck(deck: Int, filepath: String) {
        guard let c = controller(for: deck) else { return }
        c.handleFilepath(filepath)
    }

    func seratoDeck(deck: Int, valid: Bool) {
        guard let c = controller(for: deck) else { return }
        c.handleValid(valid)
    }

    func seratoDeck(deck: Int, positionSeconds: Double, playRate: Float, bpm: Float) {
        guard let c = controller(for: deck) else { return }
        c.handlePlayhead(positionSeconds: positionSeconds, playRate: playRate, bpm: bpm)
    }

    private func controller(for deck: Int) -> DeckController? {
        guard deck >= 0, deck < deckControllers.count else { return nil }
        return deckControllers[deck]
    }
}
