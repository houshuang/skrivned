import AppKit
import Foundation

struct HotkeyBinding {
    let keyCode: UInt16
    let requiredModifiers: UInt64
    let onKeyDown: () -> Void
    let onKeyUp: () -> Void
    var modifierPressed: Bool = false
}

class HotkeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var bindings: [UInt16: HotkeyBinding] = [:]

    func addBinding(keyCode: UInt16, modifiers: UInt64 = 0, onKeyDown: @escaping () -> Void, onKeyUp: @escaping () -> Void) {
        bindings[keyCode] = HotkeyBinding(
            keyCode: keyCode,
            requiredModifiers: modifiers,
            onKeyDown: onKeyDown,
            onKeyUp: onKeyUp
        )
    }

    func start() {
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleCGEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: selfPtr
        ) else {
            Log.error("Failed to create CGEventTap — check Accessibility permissions")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        let keys = bindings.keys.map { String($0) }.joined(separator: ", ")
        Log.info("CGEventTap installed for keyCodes: \(keys)")
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
        bindings.removeAll()
    }

    private func handleCGEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let eventKeyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        // Debug: log ALL keyDown events to diagnose which codes arrive
        if type == .keyDown {
            let mods = String(UInt64(event.flags.rawValue) & 0x00FF0000, radix: 16)
            Log.info("AnyKey: keyDown code=\(eventKeyCode) mods=0x\(mods)")
        }

        guard bindings[eventKeyCode] != nil else {
            return Unmanaged.passUnretained(event)
        }

        if isModifierOnlyKey(eventKeyCode) {
            guard type == .flagsChanged else { return Unmanaged.passUnretained(event) }

            let flags = event.flags.rawValue
            Log.info("Hotkey[\(eventKeyCode)] flagsChanged: modifierPressed=\(bindings[eventKeyCode]!.modifierPressed) flags=\(String(flags, radix: 16))")

            if bindings[eventKeyCode]!.modifierPressed {
                bindings[eventKeyCode]!.modifierPressed = false
                Log.info("Hotkey[\(eventKeyCode)] → keyUp")
                bindings[eventKeyCode]!.onKeyUp()
            } else {
                if bindings[eventKeyCode]!.requiredModifiers != 0 {
                    let currentMods = UInt64(flags) & 0x00FF0000
                    guard currentMods & bindings[eventKeyCode]!.requiredModifiers == bindings[eventKeyCode]!.requiredModifiers else {
                        return Unmanaged.passUnretained(event)
                    }
                }
                bindings[eventKeyCode]!.modifierPressed = true
                Log.info("Hotkey[\(eventKeyCode)] → keyDown")
                bindings[eventKeyCode]!.onKeyDown()
            }
            return nil
        } else {
            if bindings[eventKeyCode]!.requiredModifiers != 0 {
                let currentMods = UInt64(event.flags.rawValue) & 0x00FF0000
                guard currentMods & bindings[eventKeyCode]!.requiredModifiers == bindings[eventKeyCode]!.requiredModifiers else {
                    return Unmanaged.passUnretained(event)
                }
            }
            if type == .keyDown {
                Log.info("Hotkey[\(eventKeyCode)] → keyDown (mods=0x\(String(UInt64(event.flags.rawValue) & 0x00FF0000, radix: 16)))")
                bindings[eventKeyCode]!.onKeyDown()
            } else if type == .keyUp {
                Log.info("Hotkey[\(eventKeyCode)] → keyUp")
                bindings[eventKeyCode]!.onKeyUp()
            }
            return nil
        }
    }

    private func isModifierOnlyKey(_ code: UInt16) -> Bool {
        return [54, 55, 56, 58, 59, 60, 61, 62, 63].contains(code)
    }
}
