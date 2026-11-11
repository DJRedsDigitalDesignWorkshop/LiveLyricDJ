import AppKit
import ApplicationServices
import CoreGraphics

/// Reads Serato's visible window and can move it below the lyric banner after
/// the user has enabled Accessibility access for LiveLyricDJ.
@MainActor
enum SeratoWorkspace {
    enum Result: Equatable {
        case success
        case needsAccessibility
        case unavailable
        case notEnoughSpace
        case failed
    }

    private static let seratoWindowOwnerName = "Serato DJ Pro"
    private static let bannerGap: CGFloat = 8
    private static let topAlignmentTolerance: CGFloat = 8
    private static let fallbackMinimumWindowSize = NSSize(width: 480, height: 320)

    static var isRunning: Bool {
        runningSeratoApplication() != nil
    }

    /// Returns the largest on-screen layer-zero Serato window, converted from
    /// Quartz's top-left global coordinates to AppKit's bottom-left system.
    static func windowFrame() -> NSRect? {
        guard let application = runningSeratoApplication(),
              let primaryScreen = NSScreen.screens.first,
              let windowList = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
              ) as? [[String: Any]] else {
            return nil
        }

        let bounds = windowList.compactMap { info -> CGRect? in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == application.processIdentifier,
                  (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let rect = quartzRect(from: info[kCGWindowBounds as String]),
                  rect.width > 0,
                  rect.height > 0 else {
                return nil
            }
            return rect
        }

        guard let mainBounds = bounds.max(by: { $0.width * $0.height < $1.width * $1.height }) else {
            return nil
        }

        return NSRect(
            x: mainBounds.minX,
            y: primaryScreen.frame.maxY - mainBounds.maxY,
            width: mainBounds.width,
            height: mainBounds.height
        )
    }

    /// Computes the available rectangle below a top-aligned banner. Returns
    /// nil if the banner is away from the screen top or the free area cannot
    /// hold the requested minimum window size.
    static func fittingFrame(
        bannerFrame: NSRect,
        visibleFrame: NSRect,
        minimumSize: NSSize
    ) -> NSRect? {
        guard visibleFrame.width > 0,
              visibleFrame.height > 0,
              bannerFrame.width > 0,
              bannerFrame.height > 0,
              bannerFrame.intersects(visibleFrame) else {
            return nil
        }

        let topOffset = visibleFrame.maxY - bannerFrame.maxY
        guard topOffset >= -topAlignmentTolerance,
              topOffset <= topAlignmentTolerance else {
            return nil
        }

        let freeTop = min(visibleFrame.maxY, bannerFrame.minY - bannerGap)
        let freeHeight = freeTop - visibleFrame.minY
        guard visibleFrame.width >= minimumSize.width,
              freeHeight >= minimumSize.height else {
            return nil
        }

        return NSRect(
            x: visibleFrame.minX,
            y: visibleFrame.minY,
            width: visibleFrame.width,
            height: freeHeight
        )
    }

    /// Moves and, when needed, shrinks Serato's main window into the free area
    /// below a top-aligned banner. It never enlarges the Serato window and
    /// never displays an Accessibility permission prompt.
    static func makeRoom(bannerFrame: NSRect) -> Result {
        guard let application = runningSeratoApplication() else { return .unavailable }
        guard AXIsProcessTrusted() else { return .needsAccessibility }
        guard let screen = screen(for: bannerFrame),
              let primaryScreen = NSScreen.screens.first else {
            return .unavailable
        }

        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        guard let window = mainWindow(of: applicationElement) else { return .unavailable }
        if accessibilityBooleanAttribute("AXMinimized", of: window) == true
            || accessibilityBooleanAttribute("AXFullScreen", of: window) == true {
            return .unavailable
        }
        guard let currentFrame = accessibilityFrame(of: window) else { return .failed }
        let minimumWindowSize = minimumSize(of: window) ?? fallbackMinimumWindowSize

        guard let availableFrame = fittingFrame(
            bannerFrame: bannerFrame,
            visibleFrame: screen.visibleFrame,
            minimumSize: minimumWindowSize
        ) else {
            let topOffset = screen.visibleFrame.maxY - bannerFrame.maxY
            return abs(topOffset) <= topAlignmentTolerance ? .notEnoughSpace : .unavailable
        }

        // An already clear window needs no Accessibility writes.
        guard currentFrame.intersects(bannerFrame) else { return .success }

        let targetSize = NSSize(
            width: min(currentFrame.width, availableFrame.width),
            height: min(currentFrame.height, availableFrame.height)
        )
        guard targetSize.width >= minimumWindowSize.width,
              targetSize.height >= minimumWindowSize.height else {
            return .notEnoughSpace
        }

        let targetFrame = NSRect(
            x: min(max(currentFrame.minX, availableFrame.minX), availableFrame.maxX - targetSize.width),
            y: min(max(currentFrame.minY, availableFrame.minY), availableFrame.maxY - targetSize.height),
            width: targetSize.width,
            height: targetSize.height
        )
        if nearlyEqual(currentFrame, targetFrame) { return .success }

        var positionSettable = DarwinBoolean(false)
        var sizeSettable = DarwinBoolean(false)
        let positionAttribute = kAXPositionAttribute as CFString
        let sizeAttribute = kAXSizeAttribute as CFString
        guard AXUIElementIsAttributeSettable(window, positionAttribute, &positionSettable) == .success,
              AXUIElementIsAttributeSettable(window, sizeAttribute, &sizeSettable) == .success,
              positionSettable.boolValue,
              sizeSettable.boolValue else {
            return .failed
        }

        guard writeAccessibilityFrame(targetFrame, to: window, screenTop: primaryScreen.frame.maxY) else {
            _ = writeAccessibilityFrame(currentFrame, to: window, screenTop: primaryScreen.frame.maxY)
            return .failed
        }

        guard let updatedFrame = accessibilityFrame(of: window) else {
            _ = writeAccessibilityFrame(currentFrame, to: window, screenTop: primaryScreen.frame.maxY)
            return .failed
        }
        let permittedTop = bannerFrame.minY - bannerGap
        guard updatedFrame.maxY <= permittedTop,
              !updatedFrame.intersects(bannerFrame) else {
            _ = writeAccessibilityFrame(currentFrame, to: window, screenTop: primaryScreen.frame.maxY)
            return .notEnoughSpace
        }
        return .success
    }

    private static func runningSeratoApplication() -> NSRunningApplication? {
        let applications = NSWorkspace.shared.runningApplications
        return applications.first {
            ($0.localizedName ?? "").caseInsensitiveCompare(seratoWindowOwnerName) == .orderedSame
        } ?? applications.first {
            guard let bundleIdentifier = $0.bundleIdentifier?.lowercased() else { return false }
            return bundleIdentifier.contains("serato") && bundleIdentifier.contains("dj")
        }
    }

    private static func screen(for frame: NSRect) -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.intersects(frame) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private static func mainWindow(of application: AXUIElement) -> AXUIElement? {
        var mainWindowValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            application,
            kAXMainWindowAttribute as CFString,
            &mainWindowValue
        ) == .success,
           let mainWindow = axUIElement(from: mainWindowValue) {
            return mainWindow
        }

        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXWindowsAttribute as CFString,
            &windowsValue
        ) == .success,
              let windowsValue,
              CFGetTypeID(windowsValue) == CFArrayGetTypeID() else {
            return nil
        }
        let windows = unsafeBitCast(windowsValue, to: CFArray.self)
        guard CFArrayGetCount(windows) > 0,
              let firstWindow = CFArrayGetValueAtIndex(windows, 0) else {
            return nil
        }
        let firstWindowValue = unsafeBitCast(firstWindow, to: CFTypeRef.self)
        return axUIElement(from: firstWindowValue)
    }

    private static func accessibilityFrame(of window: AXUIElement) -> NSRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue = axValue(from: positionValue),
              let sizeValue = axValue(from: sizeValue),
              AXValueGetType(positionValue) == .cgPoint,
              AXValueGetType(sizeValue) == .cgSize else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size),
              size.width > 0,
              size.height > 0,
              let primaryScreen = NSScreen.screens.first else {
            return nil
        }

        return NSRect(
            x: position.x,
            y: primaryScreen.frame.maxY - (position.y + size.height),
            width: size.width,
            height: size.height
        )
    }

    private static func accessibilityBooleanAttribute(_ name: String, of element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let number = value as? NSNumber else {
            return nil
        }
        return number.boolValue
    }

    private static func minimumSize(of window: AXUIElement) -> NSSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, "AXMinSize" as CFString, &value) == .success,
              let sizeValue = axValue(from: value),
              AXValueGetType(sizeValue) == .cgSize else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(sizeValue, .cgSize, &size), size.width > 0, size.height > 0 else {
            return nil
        }
        return NSSize(width: size.width, height: size.height)
    }

    private static func axUIElement(from value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private static func axValue(from value: CFTypeRef?) -> AXValue? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXValue.self)
    }

    private static func writeAccessibilityFrame(
        _ frame: NSRect,
        to window: AXUIElement,
        screenTop: CGFloat
    ) -> Bool {
        var size = CGSize(width: frame.width, height: frame.height)
        var position = CGPoint(x: frame.minX, y: screenTop - frame.maxY)
        guard let sizeValue = AXValueCreate(.cgSize, &size),
              let positionValue = AXValueCreate(.cgPoint, &position) else {
            return false
        }
        guard AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue) == .success else {
            return false
        }
        return AXUIElementSetAttributeValue(
            window,
            kAXPositionAttribute as CFString,
            positionValue
        ) == .success
    }

    private static func quartzRect(from value: Any?) -> CGRect? {
        guard let dictionary = value as? NSDictionary,
              let x = dictionary["X"] as? NSNumber,
              let y = dictionary["Y"] as? NSNumber,
              let width = dictionary["Width"] as? NSNumber,
              let height = dictionary["Height"] as? NSNumber else {
            return nil
        }
        return CGRect(
            x: CGFloat(x.doubleValue),
            y: CGFloat(y.doubleValue),
            width: CGFloat(width.doubleValue),
            height: CGFloat(height.doubleValue)
        )
    }

    private static func nearlyEqual(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
        let epsilon: CGFloat = 1
        return abs(lhs.minX - rhs.minX) <= epsilon
            && abs(lhs.minY - rhs.minY) <= epsilon
            && abs(lhs.width - rhs.width) <= epsilon
            && abs(lhs.height - rhs.height) <= epsilon
    }
}
