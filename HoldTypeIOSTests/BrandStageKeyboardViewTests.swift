import Testing
import UIKit

@Suite(.serialized)
@MainActor
struct BrandStageKeyboardViewTests {
    private static let compactLandscapeWidths: [CGFloat] = [
        667,
        812,
        844,
        852,
        932,
    ]

    @Test func renderExposesTheApprovedControlsAndRoutesEachActionOnce() throws {
        let view = makeView(width: 393)
        var latestCount = 0
        var punctuation: [String] = []
        var spaceCount = 0
        var deleteStartCount = 0
        var deleteStopCount = 0
        var returnCount = 0

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

        let stage = try #require(
            view.descendant(
                UIView.self,
                identifier: "keyboard.brand-stage.stage"
            )
        )
        #expect(stage.accessibilityValue == "Ready")
        #expect(
            view.descendant(
                UILabel.self,
                identifier: "keyboard.brand-stage.status"
            ) == nil
        )

        #expect(
            view.descendant(
                UIButton.self,
                identifier: "keyboard.brand-stage.settings"
            ) == nil
        )
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
        assertFullTopActionTitle(latest)
        #expect(space.configuration?.title == "space")
        #expect(returnButton.configuration?.title == "Send")
        #expect(returnButton.accessibilityLabel == "Send")

        latest.sendActions(for: .touchUpInside)
        period.sendActions(for: .touchUpInside)
        comma.sendActions(for: .touchUpInside)
        question.sendActions(for: .touchUpInside)
        exclamation.sendActions(for: .touchUpInside)
        space.sendActions(for: .touchUpInside)
        delete.sendActions(for: .touchDown)
        delete.sendActions(for: .touchUpInside)
        returnButton.sendActions(for: .touchUpInside)

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

        let latest = try button("keyboard.brand-stage.latest", in: view)
        let delete = try button("keyboard.brand-stage.delete", in: view)
        let returnButton = try button("keyboard.brand-stage.return", in: view)

        #expect(latest.bounds.width >= 95.9)
        assertFullTopActionTitle(latest)
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

    @Test func topActionsUseIntrinsicTextWidthOnNarrowPhones() throws {
        for width: CGFloat in [320, 375, 393, 430] {
            let view = makeView(width: width)
            view.render(presentation(latestIsEnabled: true))
            layout(view)

            let latest = try button(
                "keyboard.brand-stage.latest",
                in: view
            )

            #expect(latest.bounds.width >= 95.9)
            assertFullTopActionTitle(latest)
        }
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

        let latest = try button("keyboard.brand-stage.latest", in: view)
        let keyColor = try #require(
            latest.configuration?.baseBackgroundColor
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

    @Test func unavailableVoiceReplacesTheMicrophoneWithCompleteRecoveryCopy()
        throws {
        let view = makeView(width: 393)
        view.render(
            presentation(
                status: .sessionNotRunning,
                voiceStage: .recovery(.startSession)
            )
        )
        layout(view)

        let microphone = try button("keyboard.brand-stage.voice", in: view)
        let recovery = try #require(
            view.descendant(
                UIStackView.self,
                identifier: "keyboard.brand-stage.recovery"
            )
        )
        let title = try #require(
            view.descendant(
                UILabel.self,
                identifier: "keyboard.brand-stage.recovery-title"
            )
        )
        let detail = try #require(
            view.descendant(
                UILabel.self,
                identifier: "keyboard.brand-stage.recovery-detail"
            )
        )

        #expect(isEffectivelyHidden(microphone))
        #expect(!isEffectivelyHidden(recovery))
        #expect(title.text == "Start a voice session")
        #expect(
            detail.text
                == "Open HoldType → Voice → Keyboard Dictation Session → Start Keyboard Session. Then return here."
        )
    }

    @Test func startingAndProcessingUseProgressInsteadOfAnActiveMicrophone()
        throws {
        let view = makeView(width: 393)

        for stage: KeyboardVoiceStagePresentation in [.starting, .processing] {
            view.render(
                presentation(
                    status: stage == .starting ? .starting : .processing,
                    voiceStage: stage,
                    cancelIsVisible: true
                )
            )
            layout(view)

            let microphone = try button(
                "keyboard.brand-stage.voice",
                in: view
            )
            let progress = try #require(
                view.descendant(
                    UILabel.self,
                    identifier: "keyboard.brand-stage.progress"
                )
            )
            let cancel = try button(
                "keyboard.brand-stage.processing-cancel",
                in: view
            )
            #expect(isEffectivelyHidden(microphone))
            #expect(!isEffectivelyHidden(progress))
            #expect(!isEffectivelyHidden(cancel))
        }
    }

    @Test func fullAccessRecoveryEmphasizesTheCompleteRouteAndKeepsShortcutSecondary()
        throws {
        let view = makeView(width: 393)
        view.render(
            presentation(
                status: .fullAccessRequired,
                voiceStage: .recovery(.enableFullAccess)
            )
        )
        layout(view)

        let route = try #require(
            view.descendant(
                UILabel.self,
                identifier: "keyboard.brand-stage.recovery-detail"
            )
        )
        let followUp = try #require(
            view.descendant(
                UILabel.self,
                identifier: "keyboard.brand-stage.recovery-follow-up"
            )
        )
        let shortcut = try #require(
            view.descendant(
                UILabel.self,
                identifier: "keyboard.brand-stage.recovery-shortcut"
            )
        )

        #expect(
            route.text
                == "iPhone Settings → General → Keyboard → Keyboards → HoldType → Allow Full Access."
        )
        #expect(route.font.fontDescriptor.symbolicTraits.contains(.traitBold))
        #expect(followUp.text == "Then open HoldType and start a session.")
        #expect(shortcut.text == "Shortcut: hold 🌐 → Keyboard Settings.")
        #expect(!isEffectivelyHidden(route))
        #expect(!isEffectivelyHidden(followUp))
        #expect(!isEffectivelyHidden(shortcut))
    }

    @Test func compactPhoneLandscapeKeepsVoiceIdentityAndControlsInBounds()
        throws {
        for showsGlobe in [true, false] {
            for width in Self.compactLandscapeWidths {
                let fixture = makeCompactLandscapeFixture(
                    width: width,
                    showsInputModeSwitchKey: showsGlobe
                )
                let view = fixture.view
                let logo = try #require(
                    view.descendant(
                        UIImageView.self,
                        identifier: "keyboard.brand-stage.logo"
                    )
                )
                let voice = try #require(
                    view.descendant(
                        UIView.self,
                        identifier: "keyboard.brand-stage.voice"
                    )
                )
                let globe = try button(
                    "keyboard.brand-stage.next-keyboard",
                    in: view
                )

                #expect(
                    abs(frame(of: logo, in: view).midX - view.bounds.midX) < 1
                )
                #expect(logo.bounds.width >= 24)
                #expect(logo.bounds.height >= 24)
                #expect(!isEffectivelyHidden(logo))
                #expect(!isEffectivelyHidden(voice))
                #expect(voice.bounds.width >= 79.9)
                #expect(voice.bounds.height >= 79.9)
                #expect(globe.isHidden == !showsGlobe)

                let visibleIdentifiers = compactControlIdentifiers(
                    showsGlobe: showsGlobe
                )
                var boundedViews: [UIView] = [logo, voice]
                for identifier in visibleIdentifiers {
                    let control = try button(identifier, in: view)
                    #expect(control.bounds.width >= 43.9)
                    #expect(control.bounds.height >= 43.9)
                    #expect(!isEffectivelyHidden(control))
                    boundedViews.append(control)
                }

                let period = try button(
                    "keyboard.brand-stage.punctuation.period",
                    in: view
                )
                #expect(
                    frame(of: voice, in: view).maxX
                        < frame(of: period, in: view).minX
                )
                assertViewsStayInBounds(boundedViews, of: view)
                assertVisibleHierarchyHasNoAmbiguity(view)
            }
        }
    }

    @Test func compactPhoneLandscapeKeepsLightAndDarkGeometry() throws {
        for showsGlobe in [true, false] {
            for width in Self.compactLandscapeWidths {
                let fixture = makeCompactLandscapeFixture(
                    width: width,
                    showsInputModeSwitchKey: showsGlobe
                )
                let view = fixture.view
                let lightFrames = controlFrames(in: view)

                view.overrideUserInterfaceStyle = .dark
                view.updatePreferredHeight(
                    for: compactPhoneTraits(userInterfaceStyle: .dark)
                )
                layout(fixture)

                #expect(view.overrideUserInterfaceStyle == .dark)
                #expect(controlFrames(in: view) == lightFrames)
                let voice = try #require(
                    view.descendant(
                        UIView.self,
                        identifier: "keyboard.brand-stage.voice"
                    )
                )
                #expect(!isEffectivelyHidden(voice))
                let globe = try button(
                    "keyboard.brand-stage.next-keyboard",
                    in: view
                )
                #expect(globe.isHidden == !showsGlobe)
            }
        }
    }

    @Test func safeAreaAndCompactRegularRoundTripPreserveTheComposition()
        throws {
        let landscapeInsets = UIEdgeInsets(
            top: 0,
            left: 44,
            bottom: 21,
            right: 44
        )
        let fixture = makeCompactLandscapeFixture(
            width: 844,
            showsInputModeSwitchKey: true
        )
        let view = fixture.view
        let voice = try #require(
            view.descendant(
                UIView.self,
                identifier: "keyboard.brand-stage.voice"
            )
        )
        let period = try button(
            "keyboard.brand-stage.punctuation.period",
            in: view
        )
        let initialFrames = controlFrames(in: view)

        #expect(
            frame(of: voice, in: view).maxX
                < frame(of: period, in: view).minX
        )

        fixture.host.frame.size.height = 302
        view.updatePreferredHeight(
            for: regularPhoneTraits(userInterfaceStyle: .light)
        )
        layout(fixture)

        #expect(
            frame(of: voice, in: view).maxY
                < frame(of: period, in: view).minY
        )
        #expect(!isEffectivelyHidden(voice))

        fixture.host.frame.size.height = 176
        view.updatePreferredHeight(
            for: compactPhoneTraits(userInterfaceStyle: .light)
        )
        layout(fixture)

        #expect(controlFrames(in: view) == initialFrames)
        #expect(
            frame(of: voice, in: view).maxX
                < frame(of: period, in: view).minX
        )

        let safeAreaFixture = makeSafeAreaLandscapeFixture(
            width: 844,
            safeAreaInsets: landscapeInsets
        )
        defer { safeAreaFixture.window.isHidden = true }
        #expect(safeAreaFixture.view.safeAreaInsets.left >= 43.9)
        #expect(safeAreaFixture.view.safeAreaInsets.bottom >= 20.9)
        assertInteractiveControlsStayInsideHorizontalAndBottomSafeArea(
            safeAreaFixture.view
        )
    }

    private func makeView(width: CGFloat) -> BrandStageKeyboardView {
        let view = BrandStageKeyboardView(
            frame: CGRect(x: 0, y: 0, width: width, height: 302)
        )
        view.bounds = CGRect(x: 0, y: 0, width: width, height: 302)
        return view
    }

    private func makeCompactLandscapeFixture(
        width: CGFloat,
        showsInputModeSwitchKey: Bool
    ) -> BrandStageLandscapeFixture {
        let host = UIView(
            frame: CGRect(x: 0, y: 0, width: width, height: 176)
        )
        let view = BrandStageKeyboardView(frame: host.bounds)
        view.overrideUserInterfaceStyle = .light

        host.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            view.topAnchor.constraint(equalTo: host.topAnchor),
            view.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
        view.render(
            presentation(
                latestIsEnabled: true,
                showsInputModeSwitchKey: showsInputModeSwitchKey
            )
        )

        let fixture = BrandStageLandscapeFixture(host: host, view: view)
        view.updatePreferredHeight(
            for: compactPhoneTraits(userInterfaceStyle: .light)
        )
        layout(fixture)
        return fixture
    }

    private func makeSafeAreaLandscapeFixture(
        width: CGFloat,
        safeAreaInsets: UIEdgeInsets
    ) -> BrandStageSafeAreaFixture {
        let window = UIWindow(
            frame: CGRect(
                x: 0,
                y: 0,
                width: width,
                height: 176 + safeAreaInsets.bottom
            )
        )
        let hostController = UIViewController()
        hostController.additionalSafeAreaInsets = safeAreaInsets
        window.rootViewController = hostController
        window.isHidden = false
        hostController.view.frame = window.bounds

        let view = BrandStageKeyboardView(frame: hostController.view.bounds)
        hostController.view.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(
                equalTo: hostController.view.leadingAnchor
            ),
            view.trailingAnchor.constraint(
                equalTo: hostController.view.trailingAnchor
            ),
            view.topAnchor.constraint(equalTo: hostController.view.topAnchor),
            view.bottomAnchor.constraint(
                equalTo: hostController.view.bottomAnchor
            ),
        ])
        view.render(presentation(latestIsEnabled: true))
        hostController.view.layoutIfNeeded()
        view.updatePreferredHeight(
            for: compactPhoneTraits(userInterfaceStyle: .light)
        )
        hostController.view.layoutIfNeeded()

        return BrandStageSafeAreaFixture(
            window: window,
            view: view
        )
    }

    private func layout(_ view: BrandStageKeyboardView) {
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    private func layout(_ fixture: BrandStageLandscapeFixture) {
        fixture.host.setNeedsLayout()
        fixture.host.layoutIfNeeded()
        fixture.view.setNeedsLayout()
        fixture.view.layoutIfNeeded()
    }

    private func compactPhoneTraits(
        userInterfaceStyle: UIUserInterfaceStyle
    ) -> UITraitCollection {
        UITraitCollection(
            traitsFrom: [
                UITraitCollection(userInterfaceIdiom: .phone),
                UITraitCollection(horizontalSizeClass: .compact),
                UITraitCollection(verticalSizeClass: .compact),
                UITraitCollection(userInterfaceStyle: userInterfaceStyle),
            ]
        )
    }

    private func regularPhoneTraits(
        userInterfaceStyle: UIUserInterfaceStyle
    ) -> UITraitCollection {
        UITraitCollection(
            traitsFrom: [
                UITraitCollection(userInterfaceIdiom: .phone),
                UITraitCollection(horizontalSizeClass: .compact),
                UITraitCollection(verticalSizeClass: .regular),
                UITraitCollection(userInterfaceStyle: userInterfaceStyle),
            ]
        )
    }

    private func presentation(
        status: KeyboardVoiceStatus = .ready,
        voiceStage: KeyboardVoiceStagePresentation = .ready,
        latestIsEnabled: Bool = false,
        cancelIsVisible: Bool = false,
        returnKey: KeyboardReturnKeyPresentation = .returnSymbol,
        showsInputModeSwitchKey: Bool = true
    ) -> BrandStageKeyboardPresentation {
        BrandStageKeyboardPresentation(
            status: status,
            voiceStage: voiceStage,
            latestIsEnabled: latestIsEnabled,
            cancelIsVisible: cancelIsVisible,
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

    private func assertFullTopActionTitle(_ button: UIButton) {
        guard let titleLabel = button.titleLabel else {
            Issue.record("Top action is missing its title label")
            return
        }
        #expect(
            titleLabel.bounds.width + 0.5
                >= titleLabel.intrinsicContentSize.width
        )
    }

    private func controlFrames(in view: UIView) -> [String: CGRect] {
        var result: [String: CGRect] = [:]
        view.visitDescendants { descendant in
            guard let identifier = descendant.accessibilityIdentifier,
                  identifier.hasPrefix("keyboard.brand-stage."),
                  !isEffectivelyHidden(descendant) else {
                return
            }
            result[identifier] = descendant.frame
        }
        return result
    }

    private func compactControlIdentifiers(showsGlobe: Bool) -> [String] {
        var identifiers = [
            "keyboard.brand-stage.latest",
            "keyboard.brand-stage.punctuation.period",
            "keyboard.brand-stage.punctuation.comma",
            "keyboard.brand-stage.punctuation.question mark",
            "keyboard.brand-stage.punctuation.exclamation mark",
            "keyboard.brand-stage.space",
            "keyboard.brand-stage.delete",
            "keyboard.brand-stage.return",
        ]
        if showsGlobe {
            identifiers.append("keyboard.brand-stage.next-keyboard")
        }
        return identifiers
    }

    private func frame(of descendant: UIView, in ancestor: UIView) -> CGRect {
        descendant.convert(descendant.bounds, to: ancestor)
    }

    private func isEffectivelyHidden(_ view: UIView) -> Bool {
        var current: UIView? = view
        while let candidate = current {
            if candidate.isHidden || candidate.alpha <= 0.01 {
                return true
            }
            current = candidate.superview
        }
        return false
    }

    private func assertViewsStayInBounds(
        _ descendants: [UIView],
        of view: UIView
    ) {
        let toleratedBounds = view.bounds.insetBy(dx: -0.5, dy: -0.5)
        for descendant in descendants {
            #expect(toleratedBounds.contains(frame(of: descendant, in: view)))
        }
    }

    private func assertVisibleHierarchyHasNoAmbiguity(_ view: UIView) {
        view.visitDescendants { descendant in
            guard !isEffectivelyHidden(descendant) else { return }
            #expect(!descendant.hasAmbiguousLayout)
        }
    }

    private func assertInteractiveControlsStayInsideHorizontalAndBottomSafeArea(
        _ view: UIView
    ) {
        let safeBounds = view.bounds.inset(by: view.safeAreaInsets)
            .insetBy(dx: -0.5, dy: -0.5)
        view.visitDescendants { descendant in
            guard descendant is UIControl,
                  !isEffectivelyHidden(descendant) else {
                return
            }
            let controlFrame = frame(of: descendant, in: view)
            #expect(controlFrame.minX >= safeBounds.minX)
            #expect(controlFrame.maxX <= safeBounds.maxX)
            #expect(controlFrame.maxY <= safeBounds.maxY)
        }
    }
}

@MainActor
private struct BrandStageLandscapeFixture {
    let host: UIView
    let view: BrandStageKeyboardView
}

@MainActor
private struct BrandStageSafeAreaFixture {
    let window: UIWindow
    let view: BrandStageKeyboardView
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
