import SwiftUI
import UIKit

enum IOSVoiceDraftTypographyTier: Equatable {
    case large
    case compact
}

struct IOSVoiceDraftTypographyPolicy {
    static let compactPointSize: CGFloat = 18
    static let returnHeadroomInLines: CGFloat = 1.5

    static func resolve(
        current: IOSVoiceDraftTypographyTier,
        largeContentHeight: CGFloat,
        viewportHeight: CGFloat,
        largeLineHeight: CGFloat,
        usesAccessibilitySize: Bool
    ) -> IOSVoiceDraftTypographyTier {
        guard !usesAccessibilitySize else { return .large }
        guard viewportHeight > 0 else { return current }

        switch current {
        case .large:
            return largeContentHeight > viewportHeight ? .compact : .large
        case .compact:
            let returnThreshold = viewportHeight
                - (largeLineHeight * returnHeadroomInLines)
            return largeContentHeight <= returnThreshold ? .large : .compact
        }
    }
}

enum IOSVoiceDraftScrollCommand: Equatable {
    case none
    case top
    case bottom
}

enum IOSVoiceDraftFocusCommand: Equatable {
    case none
    case becomeFirstResponder
    case resignFirstResponder
}

struct IOSVoiceDraftFocusPolicy {
    static func resolve(
        wantsFocus: Bool,
        isEditable: Bool,
        isFirstResponder: Bool
    ) -> IOSVoiceDraftFocusCommand {
        let shouldBeFirstResponder = wantsFocus && isEditable
        if shouldBeFirstResponder, !isFirstResponder {
            return .becomeFirstResponder
        }
        if !shouldBeFirstResponder, isFirstResponder {
            return .resignFirstResponder
        }
        return .none
    }
}

struct IOSVoiceDraftFollowTailState: Equatable {
    private(set) var isFollowingTail = true
    private(set) var hasUnseenAppend = false

    mutating func receive(
        _ change: IOSVoiceDraftContentChangeKind,
        wasAtBottom: Bool
    ) -> IOSVoiceDraftScrollCommand {
        switch change {
        case .append:
            guard isFollowingTail, wasAtBottom else {
                hasUnseenAppend = true
                return .none
            }
            hasUnseenAppend = false
            return .bottom
        case .replace:
            isFollowingTail = true
            hasUnseenAppend = false
            return .top
        case .preservePosition:
            return .none
        }
    }

    mutating func suspend() {
        isFollowingTail = false
    }

    mutating func userScrolled(isAtBottom: Bool) {
        isFollowingTail = isAtBottom
        if isAtBottom {
            hasUnseenAppend = false
        }
    }

    mutating func jumpToLatest() {
        isFollowingTail = true
        hasUnseenAppend = false
    }
}

struct IOSVoiceDraftTextViewport: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var showsJumpToLatest: Bool

    let isEditable: Bool
    let contentChange: IOSVoiceDraftContentChange
    let scrollToLatestRequest: Int
    let usesAccessibilitySize: Bool
    let reduceMotion: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> IOSVoiceDraftUITextView {
        let textView = IOSVoiceDraftUITextView()
        textView.backgroundColor = .clear
        textView.textColor = .label
        textView.tintColor = .systemBlue
        textView.font = context.coordinator.largeFont(for: textView)
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = UIEdgeInsets(
            top: 8,
            left: 0,
            bottom: 8,
            right: 0
        )
        textView.textContainer.lineFragmentPadding = 0
        textView.keyboardDismissMode = .interactive
        textView.alwaysBounceVertical = false
        textView.showsVerticalScrollIndicator = true
        textView.isScrollEnabled = true
        textView.isSelectable = true
        textView.accessibilityLabel = "Current Draft"
        textView.accessibilityIdentifier = "ios.voice.draft.editor"
        textView.delegate = context.coordinator
        textView.text = text
        textView.onExternalTextAssignment = {
            [weak coordinator = context.coordinator] value in
            coordinator?.acceptExternalTextAssignment(value)
        }
        textView.onAccessibilityScroll = {
            [weak coordinator = context.coordinator] view in
            coordinator?.finishAccessibilityScroll(view)
        }
        textView.onLayout = { [weak coordinator = context.coordinator] view in
            coordinator?.reconcileTypography(in: view, animated: false)
        }
        return textView
    }

    func updateUIView(
        _ textView: IOSVoiceDraftUITextView,
        context: Context
    ) {
        let coordinator = context.coordinator
        coordinator.parent = self

        let wasAtBottom = coordinator.isAtBottom(textView)
        let receivedNewContentChange = coordinator.lastContentChangeRevision
            != contentChange.revision

        if textView.text != text {
            textView.ignoresExternalTextAssignments = true
            textView.text = text
            textView.ignoresExternalTextAssignments = false
        }

        if receivedNewContentChange, contentChange.kind == .replace {
            coordinator.typographyTier = .large
        }
        coordinator.reconcileTypography(
            in: textView,
            animated: receivedNewContentChange && !reduceMotion
        )

        if receivedNewContentChange {
            coordinator.applyContentChange(
                contentChange,
                wasAtBottom: wasAtBottom,
                to: textView
            )
        }

        if coordinator.lastScrollToLatestRequest != scrollToLatestRequest {
            coordinator.lastScrollToLatestRequest = scrollToLatestRequest
            coordinator.followTailState.jumpToLatest()
            coordinator.scrollToBottom(textView, animated: !reduceMotion)
        }

        textView.isEditable = isEditable
        textView.isSelectable = true
        coordinator.scheduleFocusReconciliation(
            in: textView,
            wantsFocus: isFocused,
            isEditable: isEditable
        )

        coordinator.reportJumpToLatestVisibility()
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: IOSVoiceDraftTextViewport
        var typographyTier = IOSVoiceDraftTypographyTier.large
        var followTailState = IOSVoiceDraftFollowTailState()
        var lastContentChangeRevision = -1
        var lastScrollToLatestRequest = 0

        private var lastReportedJumpToLatest = false
        private var isApplyingTypography = false
        private var desiredFocus = false
        private var focusReconciliationIsScheduled = false

        init(parent: IOSVoiceDraftTextViewport) {
            self.parent = parent
            lastScrollToLatestRequest = parent.scrollToLatestRequest
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            desiredFocus = true
            followTailState.suspend()
            parent.isFocused = true
            reportJumpToLatestVisibility()
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            desiredFocus = false
            parent.isFocused = false
            guard let textView = textView as? IOSVoiceDraftUITextView else {
                return
            }
            reconcileTypography(
                in: textView,
                animated: !parent.reduceMotion
            )
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func acceptExternalTextAssignment(_ value: String) {
            parent.text = value
        }

        func finishAccessibilityScroll(_ scrollView: UIScrollView) {
            finishUserScroll(scrollView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard textView.selectedRange.length > 0 else { return }
            followTailState.suspend()
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            followTailState.suspend()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard scrollView.isDragging else { return }
            followTailState.userScrolled(
                isAtBottom: isAtBottom(scrollView)
            )
            reportJumpToLatestVisibility()
        }

        func scrollViewDidEndDragging(
            _ scrollView: UIScrollView,
            willDecelerate decelerate: Bool
        ) {
            guard !decelerate else { return }
            finishUserScroll(scrollView)
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            finishUserScroll(scrollView)
        }

        func scheduleFocusReconciliation(
            in textView: IOSVoiceDraftUITextView,
            wantsFocus: Bool,
            isEditable: Bool
        ) {
            desiredFocus = wantsFocus && isEditable
            guard !focusReconciliationIsScheduled else { return }
            focusReconciliationIsScheduled = true

            // Responder changes query the SwiftUI hosting view. Performing one
            // inside updateUIView re-enters its active AttributeGraph update.
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self else { return }
                self.focusReconciliationIsScheduled = false
                guard let textView else { return }
                switch IOSVoiceDraftFocusPolicy.resolve(
                    wantsFocus: self.desiredFocus,
                    isEditable: textView.isEditable,
                    isFirstResponder: textView.isFirstResponder
                ) {
                case .none:
                    break
                case .becomeFirstResponder:
                    textView.becomeFirstResponder()
                case .resignFirstResponder:
                    textView.resignFirstResponder()
                }
            }
        }

        func reconcileTypography(
            in textView: IOSVoiceDraftUITextView,
            animated: Bool
        ) {
            guard !isApplyingTypography,
                  !textView.isFirstResponder,
                  textView.bounds.width > 0,
                  textView.bounds.height > 0 else {
                return
            }

            let largeFont = largeFont(for: textView)
            let largeContentHeight = measuredContentHeight(
                textView.text,
                in: textView,
                font: largeFont
            )
            let resolved = IOSVoiceDraftTypographyPolicy.resolve(
                current: typographyTier,
                largeContentHeight: largeContentHeight,
                viewportHeight: textView.bounds.height,
                largeLineHeight: largeFont.lineHeight,
                usesAccessibilitySize: parent.usesAccessibilitySize
            )
            let desiredFont = resolved == .large
                ? largeFont
                : compactFont(for: textView)

            guard resolved != typographyTier
                    || textView.font != desiredFont else {
                return
            }

            let wasAtBottom = isAtBottom(textView)
            typographyTier = resolved
            isApplyingTypography = true
            let changes = {
                textView.font = desiredFont
                textView.layoutManager.ensureLayout(
                    for: textView.textContainer
                )
                textView.layoutIfNeeded()
            }
            if animated {
                UIView.transition(
                    with: textView,
                    duration: 0.2,
                    options: [.transitionCrossDissolve, .allowAnimatedContent],
                    animations: changes
                )
            } else {
                changes()
            }
            isApplyingTypography = false

            if followTailState.isFollowingTail, wasAtBottom {
                scrollToBottom(textView, animated: false)
            }
        }

        func largeFont(for textView: UITextView) -> UIFont {
            UIFont.preferredFont(
                forTextStyle: .title3,
                compatibleWith: textView.traitCollection
            )
        }

        private func compactFont(for textView: UITextView) -> UIFont {
            UIFontMetrics(forTextStyle: .body).scaledFont(
                for: UIFont.systemFont(
                    ofSize: IOSVoiceDraftTypographyPolicy.compactPointSize
                ),
                compatibleWith: textView.traitCollection
            )
        }

        private func measuredContentHeight(
            _ text: String,
            in textView: UITextView,
            font: UIFont
        ) -> CGFloat {
            let horizontalInsets = textView.textContainerInset.left
                + textView.textContainerInset.right
                + (textView.textContainer.lineFragmentPadding * 2)
            let availableWidth = max(
                1,
                textView.bounds.width - horizontalInsets
            )
            let measured = (text as NSString).boundingRect(
                with: CGSize(
                    width: availableWidth,
                    height: .greatestFiniteMagnitude
                ),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font],
                context: nil
            )
            return ceil(measured.height)
                + textView.textContainerInset.top
                + textView.textContainerInset.bottom
        }

        fileprivate func applyContentChange(
            _ change: IOSVoiceDraftContentChange,
            wasAtBottom: Bool,
            to textView: UITextView
        ) {
            lastContentChangeRevision = change.revision
            let command = followTailState.receive(
                change.kind,
                wasAtBottom: wasAtBottom
            )
            switch command {
            case .none:
                break
            case .top:
                scrollToTop(textView, animated: !parent.reduceMotion)
            case .bottom:
                scrollToBottom(textView, animated: !parent.reduceMotion)
            }
            reportJumpToLatestVisibility()
        }

        fileprivate func isAtBottom(_ scrollView: UIScrollView) -> Bool {
            let visibleBottom = scrollView.contentOffset.y
                + scrollView.bounds.height
                - scrollView.adjustedContentInset.bottom
            return scrollView.contentSize.height <= visibleBottom + 12
        }

        fileprivate func scrollToBottom(
            _ scrollView: UIScrollView,
            animated: Bool
        ) {
            scrollView.layoutIfNeeded()
            let minimumOffset = -scrollView.adjustedContentInset.top
            let maximumOffset = max(
                minimumOffset,
                scrollView.contentSize.height
                    - scrollView.bounds.height
                    + scrollView.adjustedContentInset.bottom
            )
            scrollView.setContentOffset(
                CGPoint(x: scrollView.contentOffset.x, y: maximumOffset),
                animated: animated
            )
            reportJumpToLatestVisibility()
        }

        private func scrollToTop(
            _ scrollView: UIScrollView,
            animated: Bool
        ) {
            scrollView.setContentOffset(
                CGPoint(
                    x: scrollView.contentOffset.x,
                    y: -scrollView.adjustedContentInset.top
                ),
                animated: animated
            )
        }

        private func finishUserScroll(_ scrollView: UIScrollView) {
            followTailState.userScrolled(
                isAtBottom: isAtBottom(scrollView)
            )
            reportJumpToLatestVisibility()
        }

        fileprivate func reportJumpToLatestVisibility() {
            let isVisible = followTailState.hasUnseenAppend
                && !parent.isFocused
            guard isVisible != lastReportedJumpToLatest else { return }
            lastReportedJumpToLatest = isVisible
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.parent.showsJumpToLatest = isVisible
            }
        }
    }
}

final class IOSVoiceDraftUITextView: UITextView {
    var onLayout: ((IOSVoiceDraftUITextView) -> Void)?
    var onExternalTextAssignment: ((String) -> Void)?
    var onAccessibilityScroll: ((IOSVoiceDraftUITextView) -> Void)?
    var ignoresExternalTextAssignments = false

    override var text: String! {
        didSet {
            guard !ignoresExternalTextAssignments,
                  text != oldValue else {
                return
            }
            onExternalTextAssignment?(text ?? "")
        }
    }

    override var accessibilityValue: String? {
        get { text }
        set {
            let value = newValue ?? ""
            guard text != value else { return }
            text = value
        }
    }

    override func accessibilityScroll(
        _ direction: UIAccessibilityScrollDirection
    ) -> Bool {
        let didScroll = super.accessibilityScroll(direction)
        if didScroll {
            onAccessibilityScroll?(self)
        }
        return didScroll
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(self)
    }
}

extension IOSVoiceDraftTextViewport: CustomReflectable {
    var customMirror: Mirror { Mirror(self, children: [:]) }
}
