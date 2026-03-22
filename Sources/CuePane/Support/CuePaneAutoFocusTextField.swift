import AppKit
import SwiftUI

struct CuePaneAutoFocusTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var font: NSFont
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField(string: text)
        textField.placeholderString = placeholder
        textField.isBordered = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.drawsBackground = true
        textField.focusRingType = .default
        textField.font = font
        textField.delegate = context.coordinator
        textField.target = context.coordinator
        textField.action = #selector(Coordinator.submit)

        context.coordinator.attach(textField)
        context.coordinator.scheduleFocus()
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        nsView.placeholderString = placeholder
        nsView.font = font
        context.coordinator.onSubmit = onSubmit
        context.coordinator.attach(nsView)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding private var text: String
        var onSubmit: () -> Void

        private weak var textField: NSTextField?
        private var hasFocused = false

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            _text = text
            self.onSubmit = onSubmit
        }

        func attach(_ textField: NSTextField) {
            if self.textField !== textField {
                self.textField = textField
                hasFocused = false
            }
        }

        func scheduleFocus() {
            Task { @MainActor [weak self] in
                self?.focusIfPossible()
            }

            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(80))
                self?.focusIfPossible()
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            text = textField?.stringValue ?? text
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if
                commandSelector == #selector(NSResponder.insertNewline(_:)) ||
                commandSelector == #selector(NSResponder.insertLineBreak(_:))
            {
                onSubmit()
                return true
            }

            return false
        }

        @objc
        func submit() {
            onSubmit()
        }

        private func focusIfPossible() {
            guard !hasFocused, let textField, let window = textField.window else {
                return
            }

            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(textField)
            textField.selectText(nil)
            hasFocused = true
        }
    }
}
