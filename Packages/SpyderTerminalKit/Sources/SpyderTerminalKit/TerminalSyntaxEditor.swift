#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit

/// Native iOS editor with live syntax colors. No code evaluation or network calls.
@available(iOS 17.0, *)
struct SpyderSyntaxEditor: UIViewRepresentable {
    @Binding var text: String
    let palette: TerminalThemePalette
    let fontSize: Int
    let multiline: Bool
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView(frame: .zero)
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.spellCheckingType = .no
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.accessibilityIdentifier = "spyder.terminal.commandInput"
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        updateEditor(view)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        view.isScrollEnabled = multiline
        view.returnKeyType = multiline ? .default : .go
        guard view.markedTextRange == nil else { return }
        if view.text != text { view.text = text }
        updateEditor(view)
    }

    private func updateEditor(_ view: UITextView) {
        // Don't disrupt Cyrillic keyboard composition or dictation.
        guard view.markedTextRange == nil else { return }
        let font = UIFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
        let input = view.text ?? ""
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: UIColor(palette.foreground)
        ]
        let output = NSMutableAttributedString(string: input, attributes: attributes)
        var offset = 0
        for token in TerminalSyntax.tokenize(input) {
            let count = (token.text as NSString).length
            if count > 0 {
                output.addAttribute(.foregroundColor,
                    value: UIColor(palette.color(for: token.kind)),
                    range: NSRange(location: offset, length: count))
            }
            offset += count
        }
        let currentSelection = view.selectedRange
        if !(view.attributedText?.isEqual(to: output) ?? false) { view.attributedText = output }
        let start = min(currentSelection.location, output.length)
        view.selectedRange = NSRange(location: start, length: min(currentSelection.length, output.length - start))
        view.typingAttributes = attributes
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SpyderSyntaxEditor
        init(_ parent: SpyderSyntaxEditor) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            parent.updateEditor(textView)
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            if text == "\n" && !parent.multiline {
                parent.onSubmit()
                return false
            }
            return true
        }
    }
}
#endif
