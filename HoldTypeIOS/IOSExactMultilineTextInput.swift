import SwiftUI
import UIKit

struct IOSExactMultilineTextInput: UIViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    @Binding var text: String
    let accessibilityLabel: String

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        Self.configure(
            textView,
            accessibilityLabel: accessibilityLabel,
            isEnabled: isEnabled
        )
        textView.delegate = context.coordinator
        textView.text = text
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        if textView.text != text {
            textView.text = text
        }
        textView.accessibilityLabel = accessibilityLabel
        Self.setInteraction(textView, isEnabled: isEnabled)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UITextView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width else { return nil }
        let fittingSize = uiView.sizeThatFits(
            CGSize(
                width: width,
                height: .greatestFiniteMagnitude
            )
        )
        let lineHeight = uiView.font?.lineHeight ?? 20
        let verticalInsets = uiView.textContainerInset.top
            + uiView.textContainerInset.bottom
        let minimumHeight = ceil((lineHeight * 2) + verticalInsets)
        let maximumHeight = ceil((lineHeight * 6) + verticalInsets)
        return CGSize(
            width: width,
            height: min(
                max(fittingSize.height, minimumHeight),
                maximumHeight
            )
        )
    }

    static func configure(
        _ textView: UITextView,
        accessibilityLabel: String,
        isEnabled: Bool = true
    ) {
        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = UIEdgeInsets(
            top: 6,
            left: 0,
            bottom: 6,
            right: 0
        )
        textView.textContainer.lineFragmentPadding = 0
        textView.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )

        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.spellCheckingType = .no
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.textContentType = nil
        textView.inlinePredictionType = .no
        if #available(iOS 18.0, *) {
            textView.mathExpressionCompletionType = .no
            textView.writingToolsBehavior = .none
        }

        textView.accessibilityLabel = accessibilityLabel
        setInteraction(textView, isEnabled: isEnabled)
    }

    static func setInteraction(
        _ textView: UITextView,
        isEnabled: Bool
    ) {
        textView.isEditable = isEnabled
        textView.isSelectable = isEnabled
        textView.isUserInteractionEnabled = isEnabled
        if isEnabled {
            textView.accessibilityTraits.remove(.notEnabled)
        } else {
            if textView.isFirstResponder {
                textView.resignFirstResponder()
            }
            textView.accessibilityTraits.insert(.notEnabled)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: IOSExactMultilineTextInput

        init(parent: IOSExactMultilineTextInput) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }
    }
}

extension IOSExactMultilineTextInput: CustomReflectable {
    var customMirror: Mirror { Mirror(self, children: [:]) }
}
