import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum InjectionMethod: Sendable {
    case keyboard
    case clipboard
}

final class TextInjectionEngine: @unchecked Sendable {

    private struct FocusedElementSnapshot {
        let bundleIdentifier: String?
        let role: String?
        let value: String?
        let isEditable: Bool
    }

    // MARK: - Public

    var method: InjectionMethod = .clipboard

    /// Inject text into the currently focused input field.
    func inject(_ text: String) -> InjectionOutcome {
        guard !text.isEmpty else { return .inserted }
        switch method {
        case .keyboard:
            injectViaKeyboard(text)
            return .inserted
        case .clipboard:
            return injectViaClipboard(text)
        }
    }

    /// Copy text to the system clipboard (used at session end).
    func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    // MARK: - Keyboard simulation

    private func injectViaKeyboard(_ text: String) {
        let utf16 = Array(text.utf16)
        let chunkSize = 16

        for offset in stride(from: 0, to: utf16.count, by: chunkSize) {
            let end = min(offset + chunkSize, utf16.count)
            var chunk = Array(utf16[offset..<end])
            let length = chunk.count

            guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            else { continue }

            keyDown.keyboardSetUnicodeString(stringLength: length, unicodeString: &chunk)
            keyUp.keyboardSetUnicodeString(stringLength: length, unicodeString: &chunk)

            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)

            if end < utf16.count {
                usleep(10_000)
            }
        }
    }

    // MARK: - Clipboard injection

    private func injectViaClipboard(_ text: String) -> InjectionOutcome {
        let beforePaste = captureFocusedElementSnapshot()

        copyToClipboard(text)
        usleep(50_000)
        simulatePaste()
        // Wait for the target app to process the paste event before returning.
        // CGEvent.post is async; without this delay, subsequent clipboard writes
        // (e.g. finalize's copyToClipboard) can overwrite the clipboard before
        // the target app reads it.
        usleep(100_000)
        let afterPaste = captureFocusedElementSnapshot()
        return inferInjectionOutcome(before: beforePaste, after: afterPaste, pastedText: text)
    }

    private func simulatePaste() {
        let vKeyCode: CGKeyCode = 9 // 'v'

        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: false)
        else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func captureFocusedElementSnapshot() -> FocusedElementSnapshot? {
        let frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        guard AXIsProcessTrusted() else {
            return FocusedElementSnapshot(
                bundleIdentifier: frontmostBundleID,
                role: nil,
                value: nil,
                isEditable: false
            )
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )
        guard status == .success, let focusedValue else {
            return FocusedElementSnapshot(
                bundleIdentifier: frontmostBundleID,
                role: nil,
                value: nil,
                isEditable: false
            )
        }

        let element = unsafeDowncast(focusedValue, to: AXUIElement.self)
        let role = copyStringAttribute(kAXRoleAttribute as CFString, from: element)
        let value = copyStringAttribute(kAXValueAttribute as CFString, from: element)
        let isEditable =
            isAttributeSettable(kAXSelectedTextRangeAttribute as CFString, on: element)
            || isAttributeSettable(kAXValueAttribute as CFString, on: element)
            || [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String,
            "AXSearchField",
        ].contains(role)

        return FocusedElementSnapshot(
            bundleIdentifier: frontmostBundleID,
            role: role,
            value: value,
            isEditable: isEditable
        )
    }

    private func isAttributeSettable(_ attribute: CFString, on element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        let status = AXUIElementIsAttributeSettable(element, attribute, &settable)
        return status == .success && settable.boolValue
    }

    private func copyStringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func inferInjectionOutcome(
        before: FocusedElementSnapshot?,
        after: FocusedElementSnapshot?,
        pastedText: String
    ) -> InjectionOutcome {
        // Optimistic: assume paste succeeded unless we can positively confirm
        // the focused element is non-editable AND value didn't change.
        // Most Electron/WebView apps (Claude, Slack, etc.) don't expose
        // Accessibility attributes reliably, so false negatives are common.
        guard let before, let after else {
            return .inserted
        }

        // If either snapshot says editable, trust it
        if before.isEditable || after.isEditable {
            return .inserted
        }

        // Value changed → paste worked
        if let beforeValue = before.value, let afterValue = after.value, beforeValue != afterValue {
            return .inserted
        }

        // Can confirm: non-editable role with no value change → clipboard only
        let nonEditableRoles: Set<String> = [
            kAXStaticTextRole as String,
            kAXImageRole as String,
            kAXGroupRole as String,
            kAXWindowRole as String,
        ]
        if let role = after.role, nonEditableRoles.contains(role),
           before.value == after.value {
            return .copiedToClipboard
        }

        // Default: assume success
        return .inserted
    }


}
