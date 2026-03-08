import AppKit
import Foundation

class TextInserter {
    private let queue = DispatchQueue(label: "skrivned.inserter", qos: .userInteractive)

    func insert(text: String) {
        queue.async { [self] in
            self.doInsert(text: text)
        }
    }

    private func doInsert(text: String) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        let lines = text.components(separatedBy: "\n")
        for (lineIndex, line) in lines.enumerated() {
            if lineIndex > 0 {
                postReturnKey(source: source)
                usleep(2000)
            }
            insertLine(line, source: source)
        }
    }

    private func insertLine(_ text: String, source: CGEventSource) {
        let utf16 = Array(text.utf16)
        guard !utf16.isEmpty else { return }

        let chunkSize = 16
        var offset = 0
        while offset < utf16.count {
            let end = min(offset + chunkSize, utf16.count)
            let chunk = Array(utf16[offset..<end])

            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { break }

            // Clear all modifier flags so held keys (Option, etc.) don't contaminate
            keyDown.flags = []
            keyUp.flags = []

            chunk.withUnsafeBufferPointer { buffer in
                keyDown.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: buffer.baseAddress!)
                keyUp.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: buffer.baseAddress!)
            }

            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)

            offset = end
            if offset < utf16.count {
                usleep(2000)
            }
        }
    }

    private func postReturnKey(source: CGEventSource) {
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false) else { return }
        keyDown.flags = []
        keyUp.flags = []
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
