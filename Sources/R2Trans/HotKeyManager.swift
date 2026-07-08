import Carbon
import Foundation

struct HotKey: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
}

final class HotKeyManager {
    private static let hotKeySignature = OSType(0x52545452)

    private var eventHotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var action: (() -> Void)?
    private var currentHotKey: HotKey?
    private var nextHotKeyID: UInt32 = 1

    func register(hotKey: HotKey, action: @escaping () -> Void) throws {
        if eventHotKey != nil, currentHotKey == hotKey {
            self.action = action
            return
        }

        try installEventHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: nextHotKeyID)
        var hotKeyRef: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr, let hotKeyRef else {
            removeEventHandlerIfIdle()
            throw R2TransError.invalidHotKey("This hotkey could not be registered. It may already be used by macOS or another app.")
        }

        let previousHotKey = eventHotKey
        eventHotKey = hotKeyRef
        currentHotKey = hotKey
        self.action = action
        advanceHotKeyID()

        if let previousHotKey {
            UnregisterEventHotKey(previousHotKey)
        }
    }

    func unregister() {
        if let eventHotKey {
            UnregisterEventHotKey(eventHotKey)
            self.eventHotKey = nil
        }

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }

        currentHotKey = nil
        action = nil
    }

    private func installEventHandlerIfNeeded() throws {
        guard eventHandler == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData else {
                    return noErr
                }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard status == noErr, hotKeyID.signature == HotKeyManager.hotKeySignature else {
                    return noErr
                }

                let manager = Unmanaged<HotKeyManager>
                    .fromOpaque(userData)
                    .takeUnretainedValue()

                DispatchQueue.main.async {
                    manager.action?()
                }

                return noErr
            },
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandler
        )

        guard handlerStatus == noErr else {
            throw R2TransError.invalidHotKey("Unable to install hotkey handler.")
        }
    }

    private func removeEventHandlerIfIdle() {
        guard eventHotKey == nil, let eventHandler else {
            return
        }

        RemoveEventHandler(eventHandler)
        self.eventHandler = nil
    }

    private func advanceHotKeyID() {
        nextHotKeyID = nextHotKeyID == UInt32.max ? 1 : nextHotKeyID + 1
    }
}
