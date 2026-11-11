import AppKit
import SwiftUI

@MainActor
private final class BannerContentContainer: NSView {
    init(frame: NSRect, hostedView: NSView, resizeHandle: NSView) {
        super.init(frame: frame)
        hostedView.frame = bounds
        hostedView.autoresizingMask = [.width, .height]
        resizeHandle.frame = NSRect(x: bounds.maxX - 24, y: bounds.minY, width: 24, height: 24)
        resizeHandle.autoresizingMask = [.minXMargin, .maxYMargin]
        addSubview(hostedView)
        addSubview(resizeHandle)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

/// A real AppKit hit target for resizing the otherwise borderless panel.
@MainActor
private final class BannerResizeHandleView: NSView {
    var isResizeEnabled = false {
        didSet {
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }

    private var dragStart: NSPoint?
    private var startingFrame: NSRect?

    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard isResizeEnabled else { return }
        addCursorRect(bounds, cursor: Self.resizeCursor)
    }

    override func cursorUpdate(with event: NSEvent) {
        if isResizeEnabled {
            Self.resizeCursor.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard isResizeEnabled, let window else { return }
        dragStart = window.convertPoint(toScreen: event.locationInWindow)
        startingFrame = window.frame
    }

    override func mouseDragged(with event: NSEvent) {
        guard isResizeEnabled, let window, let dragStart, let startingFrame else { return }
        let current = window.convertPoint(toScreen: event.locationInWindow)
        let deltaX = current.x - dragStart.x
        let deltaY = current.y - dragStart.y

        let minWidth = window.minSize.width
        let maxWidth = max(minWidth, window.maxSize.width)
        let minHeight = window.minSize.height
        let maxHeight = max(minHeight, window.maxSize.height)
        let width = min(max(startingFrame.width + deltaX, minWidth), maxWidth)
        let height = min(max(startingFrame.height - deltaY, minHeight), maxHeight)
        let resized = NSRect(
            x: startingFrame.minX,
            y: startingFrame.maxY - height,
            width: width,
            height: height
        )
        window.setFrame(resized, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        dragStart = nil
        startingFrame = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isResizeEnabled else { return }
        let control = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 5, yRadius: 5)
        NSColor.systemYellow.withAlphaComponent(0.12).setFill()
        control.fill()
    }

    private static let resizeCursor: NSCursor = {
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        let path = NSBezierPath()
        path.lineWidth = 1.6
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        NSColor.labelColor.setStroke()
        // Diagonal, two-ended arrow from the upper-left to lower-right corner.
        path.move(to: NSPoint(x: 2, y: 14))
        path.line(to: NSPoint(x: 14, y: 2))
        path.move(to: NSPoint(x: 2, y: 14))
        path.line(to: NSPoint(x: 2, y: 10))
        path.move(to: NSPoint(x: 2, y: 14))
        path.line(to: NSPoint(x: 6, y: 14))
        path.move(to: NSPoint(x: 14, y: 2))
        path.line(to: NSPoint(x: 10, y: 2))
        path.move(to: NSPoint(x: 14, y: 2))
        path.line(to: NSPoint(x: 14, y: 6))
        path.stroke()
        image.unlockFocus()
        return NSCursor(image: image, hotSpot: NSPoint(x: 8, y: 8))
    }()
}

/// The always-on-top, click-through banner window. The window can be moved and
/// resized only while the menu-bar control is unlocked.
@MainActor
final class BannerWindowController: NSObject, NSWindowDelegate {
    let panel: NSPanel
    private let app: AppState
    private let resizeHandle: BannerResizeHandleView

    private let defaultHeight: CGFloat = 80
    private let minimumWidth: CGFloat = 520
    private let minimumHeight: CGFloat = 72
    private let maximumHeight: CGFloat = 420
    private let geometryDefaultsKey = "LiveLyricDJ.BannerFrame"

    private var safetyTimer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var isAdjustingFrame = false

    init(app: AppState, deckA: DeckState, deckB: DeckState) {
        self.app = app

        let savedFrame = Self.readSavedFrame(forKey: "LiveLyricDJ.BannerFrame")
        let initialScreen = Self.screen(for: savedFrame) ?? NSScreen.main ?? NSScreen.screens.first
        let initialVisibleFrame = initialScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let initialFrame: NSRect
        if let savedFrame {
            initialFrame = Self.clamped(savedFrame, to: initialVisibleFrame, minWidth: 520, minHeight: 72, maxHeight: 420)
        } else {
            initialFrame = NSRect(
                x: initialVisibleFrame.minX,
                y: initialVisibleFrame.maxY - 80,
                width: initialVisibleFrame.width,
                height: 80
            )
        }

        let resizeHandle = BannerResizeHandleView(
            frame: NSRect(x: initialFrame.width - 24, y: 0, width: 24, height: 24)
        )
        self.resizeHandle = resizeHandle

        let panel = NSPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        self.panel = panel

        super.init()

        panel.delegate = self
        let hosting = NSHostingView(rootView: BannerView(app: app, deckA: deckA, deckB: deckB))
        let content = BannerContentContainer(
            frame: NSRect(origin: .zero, size: initialFrame.size),
            hostedView: hosting,
            resizeHandle: resizeHandle
        )
        panel.contentView = content
        updateSizeLimits(for: initialScreen)

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.screensDidChange()
            }
        }

        updateVisibility()
        safetyTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateVisibility() }
        }
    }

    /// The banner must never cover Serato's controls. If the user has not left
    /// enough room, keep it hidden until they arrange the workspace.
    func updateVisibility() {
        if app.bannerManuallyHidden {
            panel.orderOut(nil)
            return
        }
        let seratoFrame = SeratoWorkspace.windowFrame()
        let overlaps = seratoFrame.map { panel.frame.intersects($0.insetBy(dx: -4, dy: -4)) } ?? SeratoWorkspace.isRunning
        if overlaps != app.bannerObstructed { app.bannerObstructed = overlaps }
        if overlaps && !app.dragMode {
            panel.orderOut(nil)
        } else if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    func toggleVisibility() {
        app.bannerManuallyHidden.toggle()
        updateVisibility()
    }

    deinit {
        safetyTimer?.invalidate()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    func positionAtTop() {
        guard let screen = Self.screen(for: panel.frame) ?? NSScreen.main ?? NSScreen.screens.first else { return }
        updateSizeLimits(for: screen)
        let frame = Self.clamped(
            NSRect(x: screen.visibleFrame.minX, y: screen.visibleFrame.maxY - panel.frame.height,
                   width: panel.frame.width, height: panel.frame.height),
            to: screen.visibleFrame,
            minWidth: minimumWidth,
            minHeight: minimumHeight,
            maxHeight: maximumHeight
        )
        applyFrame(frame, display: true)
        saveGeometry()
        updateVisibility()
    }

    /// Restores the compact full-screen-width layout and snaps it to the top.
    func resetSize() {
        guard let screen = Self.screen(for: panel.frame) ?? NSScreen.main ?? NSScreen.screens.first else { return }
        updateSizeLimits(for: screen)
        let visibleFrame = screen.visibleFrame
        let frame = Self.clamped(
            NSRect(x: visibleFrame.minX, y: visibleFrame.maxY - defaultHeight,
                   width: visibleFrame.width, height: defaultHeight),
            to: visibleFrame,
            minWidth: minimumWidth,
            minHeight: minimumHeight,
            maxHeight: maximumHeight
        )
        applyFrame(frame, display: true)
        saveGeometry()
        updateVisibility()
    }

    func setDragMode(_ enabled: Bool) {
        app.dragMode = enabled
        if enabled { app.bannerManuallyHidden = false }
        resizeHandle.isResizeEnabled = enabled
        resizeHandle.isHidden = !enabled
        if enabled {
            panel.styleMask.insert(.resizable)
        } else {
            panel.styleMask.remove(.resizable)
        }
        panel.isMovableByWindowBackground = enabled
        panel.ignoresMouseEvents = !enabled
        panel.showsResizeIndicator = enabled
        updateVisibility()
    }

    func windowDidMove(_ notification: Notification) {
        guard !isAdjustingFrame else { return }
        constrainToDesktop()
        saveGeometry()
        updateVisibility()
    }

    func windowDidResize(_ notification: Notification) {
        guard !isAdjustingFrame else { return }
        constrainToDesktop()
        saveGeometry()
        updateVisibility()
    }

    private func screensDidChange() {
        let screen = Self.screen(for: panel.frame) ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        updateSizeLimits(for: screen)
        let adjusted = Self.clamped(
            panel.frame,
            to: screen.visibleFrame,
            minWidth: minimumWidth,
            minHeight: minimumHeight,
            maxHeight: maximumHeight
        )
        applyFrame(adjusted, display: true)
        saveGeometry()
        updateVisibility()
    }

    private func updateSizeLimits(for screen: NSScreen?) {
        let screens = NSScreen.screens
        let widestDisplay = screens.map(\.visibleFrame.width).max() ?? screen?.visibleFrame.width ?? 1440
        let tallestDisplay = screens.map(\.visibleFrame.height).max() ?? screen?.visibleFrame.height ?? 900
        let activeBounds = screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        let minWidth = min(minimumWidth, activeBounds?.width ?? minimumWidth)
        let minHeight = min(minimumHeight, activeBounds?.height ?? minimumHeight)
        panel.minSize = NSSize(width: minWidth, height: minHeight)
        panel.maxSize = NSSize(
            width: max(minWidth, widestDisplay),
            height: max(minHeight, min(maximumHeight, tallestDisplay))
        )
    }

    /// Keep the banner fully reachable on the virtual desktop while allowing it
    /// to cross between displays during a drag.
    private func constrainToDesktop() {
        guard let bounds = Self.desktopVisibleBounds() else { return }
        let frame = panel.frame
        if !NSScreen.screens.contains(where: { Self.intersectionArea($0.visibleFrame, frame) > 0 }),
           let nearestScreen = Self.screen(for: frame) {
            let adjusted = Self.clamped(
                frame,
                to: nearestScreen.visibleFrame,
                minWidth: minimumWidth,
                minHeight: minimumHeight,
                maxHeight: maximumHeight
            )
            if !Self.framesEqual(frame, adjusted) {
                applyFrame(adjusted, display: true)
            }
            return
        }
        let width = min(frame.width, bounds.width)
        let height = min(frame.height, bounds.height)
        let clamped = NSRect(
            x: min(max(frame.minX, bounds.minX), bounds.maxX - width),
            y: min(max(frame.minY, bounds.minY), bounds.maxY - height),
            width: width,
            height: height
        )
        if !Self.framesEqual(frame, clamped) {
            applyFrame(clamped, display: true)
        }
    }

    private func applyFrame(_ frame: NSRect, display: Bool) {
        guard !Self.framesEqual(panel.frame, frame) else { return }
        isAdjustingFrame = true
        panel.setFrame(frame, display: display)
        isAdjustingFrame = false
    }

    private func saveGeometry() {
        let frame = panel.frame
        UserDefaults.standard.set(
            [Double(frame.minX), Double(frame.minY), Double(frame.width), Double(frame.height)],
            forKey: geometryDefaultsKey
        )
    }

    private static func readSavedFrame(forKey key: String) -> NSRect? {
        guard let values = UserDefaults.standard.array(forKey: key) as? [NSNumber], values.count == 4 else { return nil }
        let frame = NSRect(x: CGFloat(values[0].doubleValue), y: CGFloat(values[1].doubleValue),
                           width: CGFloat(values[2].doubleValue), height: CGFloat(values[3].doubleValue))
        guard frame.width.isFinite, frame.height.isFinite, frame.minX.isFinite, frame.minY.isFinite,
              frame.width > 0, frame.height > 0 else { return nil }
        return frame
    }

    private static func clamped(
        _ frame: NSRect,
        to bounds: NSRect,
        minWidth: CGFloat,
        minHeight: CGFloat,
        maxHeight: CGFloat
    ) -> NSRect {
        let effectiveMinWidth = min(minWidth, bounds.width)
        let effectiveMinHeight = min(minHeight, bounds.height)
        let width = min(max(frame.width, effectiveMinWidth), bounds.width)
        let height = min(max(frame.height, effectiveMinHeight), min(maxHeight, bounds.height))
        return NSRect(
            x: min(max(frame.minX, bounds.minX), bounds.maxX - width),
            y: min(max(frame.minY, bounds.minY), bounds.maxY - height),
            width: width,
            height: height
        )
    }

    private static func screen(for frame: NSRect?) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        guard let frame else { return NSScreen.main ?? screens.first }

        if let intersecting = screens.max(by: {
            intersectionArea($0.visibleFrame, frame) < intersectionArea($1.visibleFrame, frame)
        }), intersectionArea(intersecting.visibleFrame, frame) > 0 {
            return intersecting
        }

        let center = NSPoint(x: frame.midX, y: frame.midY)
        return screens.min(by: { distance(from: center, to: $0.visibleFrame) < distance(from: center, to: $1.visibleFrame) })
    }

    private static func distance(from point: NSPoint, to rect: NSRect) -> CGFloat {
        let dx = max(0, max(rect.minX - point.x, point.x - rect.maxX))
        let dy = max(0, max(rect.minY - point.y, point.y - rect.maxY))
        return hypot(dx, dy)
    }

    private static func intersectionArea(_ lhs: NSRect, _ rhs: NSRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return max(0, intersection.width) * max(0, intersection.height)
    }

    private static func desktopVisibleBounds() -> NSRect? {
        guard let first = NSScreen.screens.first?.visibleFrame else { return nil }
        return NSScreen.screens.dropFirst().reduce(first) { $0.union($1.visibleFrame) }
    }

    private static func framesEqual(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
        abs(lhs.minX - rhs.minX) < 0.5 && abs(lhs.minY - rhs.minY) < 0.5 &&
            abs(lhs.width - rhs.width) < 0.5 && abs(lhs.height - rhs.height) < 0.5
    }
}
