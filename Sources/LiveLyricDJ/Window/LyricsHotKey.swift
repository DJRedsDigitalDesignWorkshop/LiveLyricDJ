import AppKit
import Carbon

/// Carbon hot-key registration works while Serato is active and does not
/// require event monitoring or Accessibility permission.
@MainActor
final class LyricsHotKey {
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<LyricsHotKey>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in owner.action() }
            return noErr
        }, 1, &eventType, context, &eventHandler)
        guard installed == noErr else { return }
        let identifier = EventHotKeyID(signature: 0x4C4C444A, id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_L), UInt32(controlKey | optionKey), identifier,
                            GetApplicationEventTarget(), 0, &hotKey)
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
