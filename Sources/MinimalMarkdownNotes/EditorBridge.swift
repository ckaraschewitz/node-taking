import AppKit
import SwiftUI

@MainActor
final class EditorBridge: ObservableObject {
    weak var textView: NSTextView?
    @Published private(set) var focusRequest = UUID()

    func register(textView: NSTextView) {
        self.textView = textView
    }

    func requestFocus() {
        focusRequest = UUID()
    }

    func apply(_ action: FormatAction) {
        textView?.applyMarkdownAction(action)
    }
}

struct MarkdownEditorView: NSViewRepresentable {
    @Binding var text: String
    @ObservedObject var bridge: EditorBridge

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, bridge: bridge)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = false

        let textView = NSTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textContainerInset = NSSize(width: 0, height: 12)
        textView.delegate = context.coordinator
        textView.string = text

        scrollView.documentView = textView
        bridge.register(textView: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        bridge.register(textView: textView)

        if textView.string != text {
            textView.string = text
        }

        if context.coordinator.lastFocusRequest != bridge.focusRequest {
            context.coordinator.lastFocusRequest = bridge.focusRequest
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        let bridge: EditorBridge
        var lastFocusRequest = UUID()

        init(text: Binding<String>, bridge: EditorBridge) {
            _text = text
            self.bridge = bridge
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}

private extension NSTextView {
    func applyMarkdownAction(_ action: FormatAction) {
        switch action {
        case .bold:
            wrapSelection(prefix: "**", suffix: "**")
        case .italic:
            wrapSelection(prefix: "*", suffix: "*")
        case .h1:
            prefixLines(with: "# ")
        case .h2:
            prefixLines(with: "## ")
        case .h3:
            prefixLines(with: "### ")
        case .bulletList:
            prefixLines(with: "- ")
        case .numberedList:
            prefixNumberedList()
        case .blockquote:
            prefixLines(with: "> ")
        case .codeBlock:
            wrapSelection(prefix: "```\n", suffix: "\n```")
        }
    }

    func wrapSelection(prefix: String, suffix: String) {
        let range = selectedRange()
        let current = string as NSString
        let selected = current.substring(with: range)
        let replacement = prefix + selected + suffix
        replace(range: range, with: replacement, selectedRange: NSRange(location: range.location + prefix.count, length: range.length))
    }

    func prefixLines(with prefix: String) {
        let range = selectedRange()
        let current = string as NSString
        let lineRange = current.lineRange(for: range)
        let lines = current.substring(with: lineRange).split(separator: "\n", omittingEmptySubsequences: false)
        let transformed = lines.map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return String(line) }
            return prefix + trimmed.replacingOccurrences(of: "^[#>\\-0-9.\\s]+", with: "", options: .regularExpression)
        }.joined(separator: "\n")
        replace(range: lineRange, with: transformed, selectedRange: NSRange(location: lineRange.location, length: transformed.count))
    }

    func prefixNumberedList() {
        let range = selectedRange()
        let current = string as NSString
        let lineRange = current.lineRange(for: range)
        let lines = current.substring(with: lineRange).split(separator: "\n", omittingEmptySubsequences: false)
        var index = 1
        let transformed = lines.map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return String(line) }
            defer { index += 1 }
            return "\(index). " + trimmed.replacingOccurrences(of: "^[#>\\-0-9.\\s]+", with: "", options: .regularExpression)
        }.joined(separator: "\n")
        replace(range: lineRange, with: transformed, selectedRange: NSRange(location: lineRange.location, length: transformed.count))
    }

    func replace(range: NSRange, with replacement: String, selectedRange newSelectedRange: NSRange) {
        guard shouldChangeText(in: range, replacementString: replacement) else { return }
        textStorage?.replaceCharacters(in: range, with: replacement)
        didChangeText()
        setSelectedRange(newSelectedRange)
    }
}
