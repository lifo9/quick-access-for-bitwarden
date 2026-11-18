import AppKit
import Carbon.HIToolbox

/// A system-wide keyboard shortcut, registered through the Carbon hot key API: the one way to
/// receive a shortcut in every app without asking for the Accessibility permission.
@MainActor
final class GlobalHotKey {
    enum RegistrationError: Error {
        /// Another app, or the system, already claimed the shortcut.
        case failed(status: OSStatus)
    }

    /// Shift-Command-Space.
    static let quickAccessKeyCode = UInt32(kVK_Space)
    static let quickAccessModifiers = UInt32(cmdKey | shiftKey)

    private let onPress: () -> Void
    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?

    init(keyCode: UInt32, modifiers: UInt32, onPress: @escaping () -> Void) throws {
        self.onPress = onPress

        var hotKeyPressedEvent = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // The handler is a C function and cannot capture, so it finds this object through the
        // pointer it is installed with. The object lives as long as the app.
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else {
                    return OSStatus(eventNotHandledErr)
                }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                // Carbon delivers hot key events on the main thread.
                MainActor.assumeIsolated {
                    hotKey.onPress()
                }
                return noErr
            },
            1,
            &hotKeyPressedEvent,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerReference
        )
        guard handlerStatus == noErr else {
            throw RegistrationError.failed(status: handlerStatus)
        }

        // "BWQA", an arbitrary four character code that tells this hot key from others.
        let hotKeyIdentifier = EventHotKeyID(signature: OSType(0x4257_5141), id: 1)
        let registrationStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyIdentifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )
        guard registrationStatus == noErr else {
            throw RegistrationError.failed(status: registrationStatus)
        }
    }
}
