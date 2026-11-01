import SwiftUI
import UIKit

enum InvoiceRichText {
    private static let htmlPrefix = "<!-- easybid-rich-text -->"

    static func attributedString(from storedValue: String, fontSize: CGFloat = 15) -> NSAttributedString {
        guard !storedValue.isEmpty else {
            return NSAttributedString(string: "", attributes: baseAttributes(fontSize: fontSize))
        }

        let parsed: NSAttributedString
        if storedValue.hasPrefix(htmlPrefix),
           let data = storedValue.dropFirst(htmlPrefix.count).data(using: .utf8),
           let html = try? NSAttributedString(
               data: data,
               options: [
                   .documentType: NSAttributedString.DocumentType.html,
                   .characterEncoding: String.Encoding.utf8.rawValue,
               ],
               documentAttributes: nil
           ) {
            parsed = html
        } else {
            parsed = NSAttributedString(string: storedValue, attributes: baseAttributes(fontSize: fontSize))
        }

        let normalized = NSMutableAttributedString(attributedString: parsed)
        let fullRange = NSRange(location: 0, length: normalized.length)
        normalized.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            let sourceFont = value as? UIFont ?? .systemFont(ofSize: fontSize)
            var traits = sourceFont.fontDescriptor.symbolicTraits
            traits.remove(.traitCondensed)
            traits.remove(.traitExpanded)
            let descriptor = UIFont.systemFont(ofSize: fontSize).fontDescriptor.withSymbolicTraits(traits)
                ?? UIFont.systemFont(ofSize: fontSize).fontDescriptor
            normalized.addAttribute(.font, value: UIFont(descriptor: descriptor, size: fontSize), range: range)
        }
        normalized.addAttribute(.foregroundColor, value: UIColor.label, range: fullRange)
        return normalized
    }

    static func storageString(from attributedString: NSAttributedString) -> String {
        guard !attributedString.string.isEmpty else { return "" }
        let range = NSRange(location: 0, length: attributedString.length)
        guard let data = try? attributedString.data(
            from: range,
            documentAttributes: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ]
        ), let html = String(data: data, encoding: .utf8) else {
            return attributedString.string
        }
        return htmlPrefix + html
    }

    static func plainText(from storedValue: String) -> String {
        attributedString(from: storedValue).string
    }

    static func isEmpty(_ storedValue: String) -> Bool {
        plainText(from: storedValue).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func baseAttributes(fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
        [
            .font: UIFont.systemFont(ofSize: fontSize),
            .foregroundColor: UIColor.label,
        ]
    }
}

@MainActor
@Observable
final class InvoiceDescriptionEditorController {
    weak var textView: UITextView?

    func toggleBold() {
        toggleFontTrait(.traitBold)
    }

    func toggleItalic() {
        toggleFontTrait(.traitItalic)
    }

    func toggleBullets() {
        toggleList(ordered: false)
    }

    func toggleNumbering() {
        toggleList(ordered: true)
    }

    private func toggleFontTrait(_ trait: UIFontDescriptor.SymbolicTraits) {
        guard let textView else { return }
        let selection = textView.selectedRange

        if selection.length == 0 {
            let currentFont = textView.typingAttributes[.font] as? UIFont ?? .systemFont(ofSize: 15)
            textView.typingAttributes[.font] = toggledFont(currentFont, trait: trait)
            textView.becomeFirstResponder()
            return
        }

        let value = NSMutableAttributedString(attributedString: textView.attributedText)
        value.enumerateAttribute(.font, in: selection) { fontValue, range, _ in
            let font = fontValue as? UIFont ?? .systemFont(ofSize: 15)
            value.addAttribute(.font, value: toggledFont(font, trait: trait), range: range)
        }
        textView.attributedText = value
        textView.selectedRange = selection
        textView.delegate?.textViewDidChange?(textView)
        textView.becomeFirstResponder()
    }

    private func toggledFont(_ font: UIFont, trait: UIFontDescriptor.SymbolicTraits) -> UIFont {
        var traits = font.fontDescriptor.symbolicTraits
        if traits.contains(trait) {
            traits.remove(trait)
        } else {
            traits.insert(trait)
        }
        let descriptor = font.fontDescriptor.withSymbolicTraits(traits) ?? font.fontDescriptor
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }

    private func toggleList(ordered: Bool) {
        guard let textView else { return }
        let value = NSMutableAttributedString(attributedString: textView.attributedText)
        let originalSelection = textView.selectedRange
        let source = value.string as NSString
        let lineRange = source.lineRange(for: originalSelection)
        let selectedText = source.substring(with: lineRange)
        let keepsTrailingNewline = selectedText.hasSuffix("\n")
        var lines = selectedText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if keepsTrailingNewline, lines.last == "" { lines.removeLast() }

        let allAlreadyListed = !lines.isEmpty && lines.allSatisfy { line in
            ordered ? hasNumberPrefix(line) : line.trimmingCharacters(in: .whitespaces).hasPrefix("• ")
        }

        let updatedLines = lines.enumerated().map { index, line in
            let clean = removingListPrefix(from: line)
            guard !allAlreadyListed else { return clean }
            return ordered ? "\(index + 1). \(clean)" : "• \(clean)"
        }
        var replacement = updatedLines.joined(separator: "\n")
        if keepsTrailingNewline { replacement += "\n" }

        let attributes = value.length > 0
            ? value.attributes(at: min(lineRange.location, value.length - 1), effectiveRange: nil)
            : InvoiceRichText.baseAttributes(fontSize: 15)
        value.replaceCharacters(in: lineRange, with: NSAttributedString(string: replacement, attributes: attributes))
        textView.attributedText = value
        textView.selectedRange = NSRange(location: lineRange.location, length: (replacement as NSString).length)
        textView.delegate?.textViewDidChange?(textView)
        textView.becomeFirstResponder()
    }

    private func hasNumberPrefix(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let separator = trimmed.firstIndex(of: ".") else { return false }
        let prefix = trimmed[..<separator]
        let suffix = trimmed[trimmed.index(after: separator)...]
        return !prefix.isEmpty && prefix.allSatisfy(\.isNumber) && suffix.hasPrefix(" ")
    }

    private func removingListPrefix(from line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("• ") {
            return String(trimmed.dropFirst(2))
        }
        guard hasNumberPrefix(trimmed), let separator = trimmed.firstIndex(of: ".") else {
            return trimmed
        }
        let contentStart = trimmed.index(separator, offsetBy: 2, limitedBy: trimmed.endIndex) ?? trimmed.endIndex
        return String(trimmed[contentStart...])
    }
}

struct InvoiceDescriptionEditor: UIViewRepresentable {
    @Binding var storedValue: String
    let controller: InvoiceDescriptionEditorController

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = UIEdgeInsets(top: 14, left: 10, bottom: 14, right: 10)
        textView.textContainer.lineFragmentPadding = 0
        textView.attributedText = InvoiceRichText.attributedString(from: storedValue)
        textView.typingAttributes = InvoiceRichText.baseAttributes(fontSize: 15)
        textView.accessibilityLabel = "Invoice description"
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        controller.textView = textView
        context.coordinator.lastStoredValue = storedValue
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        controller.textView = textView
        context.coordinator.parent = self
        guard storedValue != context.coordinator.lastStoredValue else { return }
        textView.attributedText = InvoiceRichText.attributedString(from: storedValue)
        context.coordinator.lastStoredValue = storedValue
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: InvoiceDescriptionEditor
        var lastStoredValue = ""

        init(parent: InvoiceDescriptionEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            let stored = InvoiceRichText.storageString(from: textView.attributedText)
            lastStoredValue = stored
            parent.storedValue = stored
        }
    }
}
