import AppKit
import SwiftUI

/// The always-on-top, click-through banner window. A borderless
/// non-activating NSPanel at screen-saver level that joins all Spaces and
/// follows into fullscreen, exactly like the MiniMeters-style toolbar.
final class BannerWindowController: NSObject {
    let panel: NSPanel
    private let app: AppState
    private let defaultHeight: CGFloat = 166

    init(app: AppState, deckA: DeckState, deckB: DeckState) {
        self.app = app
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 166),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        self.panel = panel

        super.init()

        let hosting = NSHostingView(rootView: BannerView(app: app, deckA: deckA, deckB: deckB))
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        positionAtTop()
        panel.orderFrontRegardless()
    }

    func positionAtTop() {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        panel.setFrame(
            NSRect(x: vf.minX, y: vf.maxY - defaultHeight, width: vf.width, height: defaultHeight),
            display: true
        )
    }

    func setDragMode(_ enabled: Bool) {
        app.dragMode = enabled
        panel.ignoresMouseEvents = !enabled
        if enabled {
            panel.orderFrontRegardless()
        }
    }
}