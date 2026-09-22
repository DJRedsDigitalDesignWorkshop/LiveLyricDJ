import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: BannerWindowController?
    private var seratoServer: SeratoServer?
    private var deckControllers: [DeckController] = []
    private var statusItem: NSStatusItem?
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
            button.image?.size = NSSize(width: 18, height: 18)
            button.image?.isTemplate = false
            button.toolTip = "LiveLyricDJ controls: move banner, snap to top, or quit"
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Drag Mode: Move Banner", action: #selector(toggleDragMode), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Snap to Top", action: #selector(snapToTop), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit LiveLyricDJ", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appMenu = NSMenu(title: "LiveLyricDJ")
        appMenu.addItem(NSMenuItem(
            title: "About LiveLyricDJ",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        ))
        appMenu.addItem(NSMenuItem.separator())

        let servicesMenu = NSMenu(title: "Services")
        NSApp.servicesMenu = servicesMenu
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        servicesItem.submenu = servicesMenu
        appMenu.addItem(servicesItem)

        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(
            title: "Hide LiveLyricDJ",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        ))
        appMenu.addItem(NSMenuItem(
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        ))
        appMenu.items.last?.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(NSMenuItem(
            title: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        ))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(
            title: "Quit LiveLyricDJ",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        let appMenuItem = NSMenuItem(title: "LiveLyricDJ", action: nil, keyEquivalent: "")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu
    }

    @objc private func toggleDragMode() {
        guard let windowController else { return }
        windowController.setDragMode(!app.dragMode)
        statusItem?.menu?.item(at: 0)?.title = app.dragMode
            ? "Lock Banner Position"
            : "Drag Mode: Move Banner"
    }

    @objc private func snapToTop() {
        windowController?.positionAtTop()
    }
}

extension AppDelegate: SeratoServerDelegate {
    func seratoConnectionStateChanged(connected: Bool) {
        app.seratoConnected = connected
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
