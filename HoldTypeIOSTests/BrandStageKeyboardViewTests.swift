import Testing
import UIKit

@Suite(.serialized)
@MainActor
struct BrandStageKeyboardViewTests {
    @Test func renderExposesTheApprovedControlsAndRoutesEachActionOnce() throws {
        let view = makeView(width: 393)
        var historyCount = 0
        var latestCount = 0
        var punctuation: [String] = []
        var spaceCount = 0
        var deleteStartCount = 0
        var deleteStopCount = 0
        var returnCount = 0

        view.onHistoryRequested = { historyCount += 1 }
        view.onLatestRequested = { latestCount += 1 }
        view.onPunctuationRequested = { punctuation.append($0) }
        view.onSpaceRequested = { spaceCount += 1 }
        view.onDeleteStarted = { deleteStartCount += 1 }
        view.onDeleteStopped = { deleteStopCount += 1 }
        view.onReturnRequested = { returnCount += 1 }

        view.render(
            presentation(
                latestIsEnabled: true,
                returnKey: .title("Send")
            )
        )
        layout(view)

        let status = try #require(
            view.descendant(
                UILabel.self,
                identifier: "keyboard.brand-stage.status"
            )
        )
        #expect(status.text == "Ready")
        #expect(status.accessibilityLabel == "Keyboard status")
        #expect(status.accessibilityValue == "Ready")

        let history = try button("keyboard.brand-stage.history", in: view)
        let latest = try button("keyboard.brand-stage.latest", in: view)
        let period = try button(
            "keyboard.brand-stage.punctuation.period",
            in: view
        )
        let comma = try button(
            "keyboard.brand-stage.punctuation.comma",
            in: view
        )
        let question = try button(
            "keyboard.brand-stage.punctuation.question mark",
            in: view
        )
        let exclamation = try button(
            "keyboard.brand-stage.punctuation.exclamation mark",
            in: view
        )
        let space = try button("keyboard.brand-stage.space", in: view)
        let delete = try button("keyboard.brand-stage.delete", in: view)
        let returnButton = try button("keyboard.brand-stage.return", in: view)

        #expect(latest.isEnabled)
        #expect(returnButton.configuration?.title == "Send")
        #expect(returnButton.accessibilityLabel == "Send")

        history.sendActions(for: .touchUpInside)
        latest.sendActions(for: .touchUpInside)
        period.sendActions(for: .touchUpInside)
        comma.sendActions(for: .touchUpInside)
        question.sendActions(for: .touchUpInside)
        exclamation.sendActions(for: .touchUpInside)
        space.sendActions(for: .touchUpInside)
        delete.sendActions(for: .touchDown)
        delete.sendActions(for: .touchUpInside)
        returnButton.sendActions(for: .touchUpInside)

        #expect(historyCount == 1)
        #expect(latestCount == 1)
        #expect(punctuation == [".", ",", "?", "!"])
        #expect(spaceCount == 1)
        #expect(deleteStartCount == 1)
        #expect(deleteStopCount == 1)
        #expect(returnCount == 1)
    }

    @Test func narrowPhoneKeepsEveryEditingControlAtLeast44PointsWide()
        throws {
        for width: CGFloat in [320, 375, 390, 393, 430] {
            let view = makeView(width: width)
            view.render(presentation(showsInputModeSwitchKey: true))
            layout(view)

            for identifier in [
                "keyboard.brand-stage.next-keyboard",
                "keyboard.brand-stage.delete",
                "keyboard.brand-stage.return",
            ] {
                let control = try button(identifier, in: view)
                #expect(control.bounds.width >= 43.9)
                #expect(control.bounds.height >= 43.9)
            }
        }
    }

    @Test func accessibilityCategoryExpandsTopActionsAndBoundsSymbols()
        throws {
        let view = makeView(width: 393)
        view.render(presentation())
        view.updatePreferredHeight(
            for: UITraitCollection(
                preferredContentSizeCategory: .accessibilityLarge
            )
        )
        layout(view)

        let history = try button("keyboard.brand-stage.history", in: view)
        let latest = try button("keyboard.brand-stage.latest", in: view)
        let delete = try button("keyboard.brand-stage.delete", in: view)
        let returnButton = try button("keyboard.brand-stage.return", in: view)

        #expect(history.bounds.width >= 103.9)
        #expect(latest.bounds.width == history.bounds.width)
        #expect(history.configuration?.title == "History")
        #expect(latest.configuration?.title == "Latest")
        let boundedSymbol = UIImage.SymbolConfiguration(
            pointSize: 20,
            weight: .regular
        )
        #expect(
            delete.configuration?.preferredSymbolConfigurationForImage?
                .isEqual(boundedSymbol) == true
        )
        #expect(
            returnButton.configuration?.preferredSymbolConfigurationForImage?
                .isEqual(boundedSymbol) == true
        )
    }

    @Test func dynamicColorsChangeWithoutChangingControlGeometry() throws {
        let view = makeView(width: 393)
        view.render(presentation())
        layout(view)

        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        let lightBackground = try #require(view.backgroundColor)
            .resolvedColor(with: light)
        let darkBackground = try #require(view.backgroundColor)
            .resolvedColor(with: dark)
        #expect(lightBackground != darkBackground)

        let history = try button("keyboard.brand-stage.history", in: view)
        let keyColor = try #require(
            history.configuration?.baseBackgroundColor
        )
        #expect(
            keyColor.resolvedColor(with: light)
                != keyColor.resolvedColor(with: dark)
        )

        let originalFrames = controlFrames(in: view)
        view.overrideUserInterfaceStyle = .dark
        layout(view)
        #expect(controlFrames(in: view) == originalFrames)
    }

    @Test func systemInputModeSwitcherCanRemoveTheInRowGlobe() throws {
        let view = makeView(width: 393)
        view.render(presentation(showsInputModeSwitchKey: false))
        layout(view)

        let globe = try button(
            "keyboard.brand-stage.next-keyboard",
            in: view
        )
        let space = try button("keyboard.brand-stage.space", in: view)
        let delete = try button("keyboard.brand-stage.delete", in: view)
        let returnButton = try button("keyboard.brand-stage.return", in: view)

        #expect(globe.isHidden)
        #expect(space.bounds.width > delete.bounds.width)
        #expect(delete.bounds.width >= 43.9)
        #expect(returnButton.bounds.width >= 43.9)
    }

    private func makeView(width: CGFloat) -> BrandStageKeyboardView {
        let view = BrandStageKeyboardView(
            frame: CGRect(x: 0, y: 0, width: width, height: 302)
        )
        view.bounds = CGRect(x: 0, y: 0, width: width, height: 302)
        return view
    }

    private func layout(_ view: BrandStageKeyboardView) {
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    private func presentation(
        latestIsEnabled: Bool = false,
        returnKey: KeyboardReturnKeyPresentation = .returnSymbol,
        showsInputModeSwitchKey: Bool = true
    ) -> BrandStageKeyboardPresentation {
        BrandStageKeyboardPresentation(
            status: .ready,
            latestIsEnabled: latestIsEnabled,
            returnKey: returnKey,
            returnIsEnabled: true,
            showsInputModeSwitchKey: showsInputModeSwitchKey
        )
    }

    private func button(
        _ identifier: String,
        in view: UIView
    ) throws -> UIButton {
        try #require(
            view.descendant(UIButton.self, identifier: identifier)
        )
    }

    private func controlFrames(in view: UIView) -> [String: CGRect] {
        var result: [String: CGRect] = [:]
        view.visitDescendants { descendant in
            guard let identifier = descendant.accessibilityIdentifier,
                  identifier.hasPrefix("keyboard.brand-stage.") else {
                return
            }
            result[identifier] = descendant.frame
        }
        return result
    }
}

@MainActor
private extension UIView {
    func descendant<View: UIView>(
        _ type: View.Type,
        identifier: String
    ) -> View? {
        if let match = self as? View,
           accessibilityIdentifier == identifier {
            return match
        }

        for subview in subviews {
            if let match = subview.descendant(
                type,
                identifier: identifier
            ) {
                return match
            }
        }
        return nil
    }

    func visitDescendants(_ visit: (UIView) -> Void) {
        visit(self)
        subviews.forEach { $0.visitDescendants(visit) }
    }
}
