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
        var automaticVoiceActions: [KeyboardVoiceAction] = []
        var quickInsertions: [String] = []
        var spaceCount = 0
        var deleteStartCount = 0
        var deleteStopCount = 0
        var returnCount = 0

        view.onLatestRequested = { latestCount += 1 }
        view.onAutomaticVoiceActionChanged = {
            automaticVoiceActions.append($0)
        }
        view.onQuickInsertRequested = { quickInsertions.append($0) }
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
        let quickInsertToggle = try button(
            "keyboard.brand-stage.quick-insert-toggle",
            in: view
        )
        let auto = try button("keyboard.brand-stage.auto", in: view)
        let quickInsertStage = try #require(
            view.descendant(
                UIStackView.self,
                identifier: "keyboard.brand-stage.quick-insert"
            )
        )
        #expect(
            view.descendant(
                UILabel.self,
                identifier: "keyboard.brand-stage.quick-insert-title"
            ) == nil
        )
        let microphone = try button("keyboard.brand-stage.voice", in: view)
        let activity = try #require(
            view.descendant(
                KeyboardVoiceActivityIndicatorView.self,
                identifier: "keyboard.brand-stage.voice-indicator"
            )
        )
        let logo = try #require(
            view.descendant(
                UIImageView.self,
                identifier: "keyboard.brand-stage.logo"
            )
        )
        #expect(quickInsertToggle.accessibilityLabel == "Open Quick Insert")
        #expect(auto.isEnabled)
        #expect(auto.configuration?.title == "Auto")
        #expect(
            auto.configuration?.image?.isEqual(
                UIImage(systemName: "chevron.down")
            ) == true
        )
        #expect(auto.accessibilityValue == "Off")
        #expect(!auto.showsMenuAsPrimaryAction)
        #expect(auto.menu == nil)
        let automaticModesPanel = try #require(
            view.descendant(
                UIView.self,
                identifier: "keyboard.brand-stage.auto-modes"
            )
        )
        #expect(isEffectivelyHidden(automaticModesPanel))
        #expect(
            view.descendant(
                UIButton.self,
                identifier: "keyboard.brand-stage.translate"
            ) == nil
        )
        #expect(
            view.descendant(
                UIButton.self,
                identifier: "keyboard.brand-stage.improve"
            ) == nil
        )
        #expect(isEffectivelyHidden(quickInsertStage))
        #expect(!isEffectivelyHidden(microphone))
        #expect(microphone.bounds.width >= 127.9)
        #expect(microphone.bounds.height >= 127.9)
        #expect(activity.phase == .ready)
        #expect(isEffectivelyHidden(logo))
        #expect(
            frame(of: auto, in: view).minX
                - frame(of: quickInsertToggle, in: view).maxX >= 3.9
        )

        quickInsertToggle.sendActions(for: .touchUpInside)
        layout(view)

        let period = try button(
            "keyboard.brand-stage.quick-insert.punctuation.period",
            in: view
        )
        let laugh = try button(
            "keyboard.brand-stage.quick-insert.emoji.laugh",
            in: view
        )
        let space = try button("keyboard.brand-stage.space", in: view)
        let delete = try button("keyboard.brand-stage.delete", in: view)
        let returnButton = try button("keyboard.brand-stage.return", in: view)

        #expect(latest.isEnabled)
        #expect(quickInsertToggle.accessibilityLabel == "Close Quick Insert")
        #expect(!isEffectivelyHidden(quickInsertStage))
        #expect(isEffectivelyHidden(microphone))
        assertFullTopActionTitle(latest)
        #expect(space.configuration?.title == "space")
        #expect(returnButton.configuration?.title == "Send")
        #expect(returnButton.accessibilityLabel == "Send")

        latest.sendActions(for: .touchUpInside)
        period.sendActions(for: .touchUpInside)
        layout(view)
        #expect(isEffectivelyHidden(quickInsertStage))
        #expect(!isEffectivelyHidden(microphone))

        quickInsertToggle.sendActions(for: .touchUpInside)
        layout(view)
        laugh.sendActions(for: .touchUpInside)
        layout(view)
        #expect(isEffectivelyHidden(quickInsertStage))
        view.toggleAutomaticTranslation()
        view.render(
            presentation(
                automaticVoiceAction: .translate,
                latestIsEnabled: true,
                returnKey: .title("Send")
            )
        )
        view.toggleAutomaticCorrection()
        view.render(
            presentation(
                automaticVoiceAction: .translateAndImprove,
                latestIsEnabled: true,
                returnKey: .title("Send")
            )
        )
        layout(view)
        space.sendActions(for: .touchUpInside)
        delete.sendActions(for: .touchDown)
        delete.sendActions(for: .touchUpInside)
        returnButton.sendActions(for: .touchUpInside)

        #expect(latestCount == 1)
        #expect(automaticVoiceActions == [.translate, .translateAndImprove])
        #expect(auto.configuration?.title == "Auto 2")
        #expect(auto.accessibilityValue == "Translate, Correct")
        #expect(quickInsertions == [".", "😂"])
        #expect(quickInsertToggle.accessibilityLabel == "Open Quick Insert")
        #expect(isEffectivelyHidden(quickInsertStage))
        #expect(!isEffectivelyHidden(microphone))
        #expect(spaceCount == 1)
        #expect(deleteStartCount == 1)
        #expect(deleteStopCount == 1)
        #expect(returnCount == 1)
    }

    @Test func quickInsertClosesBackToTheCentralVoiceIndicator() throws {
        let view = makeView(width: 393)
        view.render(presentation())
        layout(view)

        let toggle = try button(
            "keyboard.brand-stage.quick-insert-toggle",
            in: view
        )
        let microphone = try button("keyboard.brand-stage.voice", in: view)
        let quickInsert = try #require(
            view.descendant(
                UIStackView.self,
                identifier: "keyboard.brand-stage.quick-insert"
            )
        )

        #expect(!isEffectivelyHidden(microphone))
        #expect((try button("keyboard.brand-stage.auto", in: view)).isEnabled)
        toggle.sendActions(for: .touchUpInside)
        layout(view)
        #expect(isEffectivelyHidden(microphone))
        #expect(!isEffectivelyHidden(quickInsert))

        toggle.sendActions(for: .touchUpInside)
        layout(view)
        #expect(!isEffectivelyHidden(microphone))
        #expect(isEffectivelyHidden(quickInsert))
    }

    @Test func activeVoiceClosesAndDisablesQuickInsert() throws {
        let view = makeView(width: 393)
        view.render(presentation())
        layout(view)

        let toggle = try button(
            "keyboard.brand-stage.quick-insert-toggle",
            in: view
        )
        let quickInsert = try #require(
            view.descendant(
                UIStackView.self,
                identifier: "keyboard.brand-stage.quick-insert"
            )
        )
        toggle.sendActions(for: .touchUpInside)
        layout(view)
        #expect(!isEffectivelyHidden(quickInsert))

        view.render(
            presentation(
                status: .listening,
                voiceStage: .listening,
                cancelIsVisible: true
            )
        )
        layout(view)

        #expect(isEffectivelyHidden(quickInsert))
        #expect(!toggle.isEnabled)
        #expect(
            !(try button("keyboard.brand-stage.auto", in: view)).isEnabled
        )
        #expect(toggle.accessibilityLabel == "Open Quick Insert")
        let microphone = try button("keyboard.brand-stage.voice", in: view)
        #expect(!isEffectivelyHidden(microphone))
        #expect(microphone.accessibilityValue == "Listening")
        let activity = try #require(
            view.descendant(
                KeyboardVoiceActivityIndicatorView.self,
                identifier: "keyboard.brand-stage.voice-indicator"
            )
        )
        #expect(activity.phase == .listening)
    }

    @Test func autoIsEnabledWhenReadyAndDisabledDuringActiveVoice()
        throws {
        let readyView = makeView(width: 393)
        readyView.render(presentation(voiceStage: .ready))
        #expect(
            (try button("keyboard.brand-stage.auto", in: readyView)).isEnabled
        )

        for stage in [
            KeyboardVoiceStagePresentation.opening,
            KeyboardVoiceStagePresentation.starting,
            .listening,
            .processing,
        ] {
            let view = makeView(width: 393)
            view.render(presentation(voiceStage: stage))
            #expect(
                !(try button("keyboard.brand-stage.auto", in: view)).isEnabled
            )
        }
    }

    @Test func autoPanelUsesPersistentVoiceStyleSwitchRows() throws {
        let view = makeView(width: 393)
        var automaticVoiceActions: [KeyboardVoiceAction] = []
        view.onAutomaticVoiceActionChanged = {
            automaticVoiceActions.append($0)
        }
        view.render(presentation())
        layout(view)

        let auto = try button("keyboard.brand-stage.auto", in: view)
        let panel = try #require(
            view.descendant(
                UIView.self,
                identifier: "keyboard.brand-stage.auto-modes"
            )
        )
        let translateSwitch = try switchControl(
            "keyboard.brand-stage.auto-mode.translate",
            in: view
        )
        let correctSwitch = try switchControl(
            "keyboard.brand-stage.auto-mode.correct",
            in: view
        )
        let translateTitle = try #require(
            view.descendant(
                UILabel.self,
                identifier: "keyboard.brand-stage.auto-mode-title.translate"
            )
        )
        let correctTitle = try #require(
            view.descendant(
                UILabel.self,
                identifier: "keyboard.brand-stage.auto-mode-title.correct"
            )
        )

        #expect(isEffectivelyHidden(panel))
        auto.sendActions(for: .touchUpInside)
        layout(view)

        #expect(!isEffectivelyHidden(panel))
        #expect(panel.bounds.width >= 279.9)
        #expect(panel.bounds.height >= 116.9)
        #expect(translateTitle.text == "Translate Result")
        #expect(correctTitle.text == "Correct Result")
        #expect(translateSwitch.accessibilityLabel == "Auto Translate")
        #expect(correctSwitch.accessibilityLabel == "Auto Correct")
        #expect(!translateSwitch.isOn)
        #expect(!correctSwitch.isOn)

        translateSwitch.setOn(true, animated: false)
        translateSwitch.sendActions(for: .valueChanged)
        #expect(automaticVoiceActions == [.translate])
        #expect(!isEffectivelyHidden(panel))

        view.render(presentation(automaticVoiceAction: .translate))
        layout(view)
        #expect(translateSwitch.isOn)
        #expect(!correctSwitch.isOn)
        #expect(!isEffectivelyHidden(panel))

        correctSwitch.setOn(true, animated: false)
        correctSwitch.sendActions(for: .valueChanged)
        #expect(automaticVoiceActions == [.translate, .translateAndImprove])
        #expect(!isEffectivelyHidden(panel))

        view.render(
            presentation(automaticVoiceAction: .translateAndImprove)
        )
        layout(view)
        #expect(translateSwitch.isOn)
        #expect(correctSwitch.isOn)
        #expect(!isEffectivelyHidden(panel))

        auto.sendActions(for: .touchUpInside)
        layout(view)
        #expect(isEffectivelyHidden(panel))
    }

    @Test func autoTriggerKeepsAMinimumWidthAndExpandsBeforeClipping()
        throws {
        let view = makeView(width: 393)
        view.render(presentation())
        layout(view)

        let auto = try button("keyboard.brand-stage.auto", in: view)
        #expect(auto.bounds.width >= 91.9)
        assertFullTopActionTitle(auto)

        view.traitOverrides.preferredContentSizeCategory =
            .accessibilityExtraExtraExtraLarge
        view.render(
            presentation(automaticVoiceAction: .translateAndImprove)
        )
        layout(view)

        #expect(auto.bounds.width >= 91.9)
        #expect(auto.bounds.width + 0.5 >= auto.intrinsicContentSize.width)
        assertFullTopActionTitle(auto)
        #expect(auto.configuration?.title == "Auto 2")
    }

    @Test func autoPanelClosesForQuickInsertAndActiveVoice() throws {
        let view = makeView(width: 393)
        view.render(presentation())
        layout(view)

        let auto = try button("keyboard.brand-stage.auto", in: view)
        let quickInsert = try button(
            "keyboard.brand-stage.quick-insert-toggle",
            in: view
        )
        let panel = try #require(
            view.descendant(
                UIView.self,
                identifier: "keyboard.brand-stage.auto-modes"
            )
        )
        let outsideDismissControl = try #require(
            view.descendant(
                UIControl.self,
                identifier: "keyboard.brand-stage.auto-modes-dismiss"
            )
        )

        auto.sendActions(for: .touchUpInside)
        layout(view)
        #expect(!isEffectivelyHidden(panel))

        outsideDismissControl.sendActions(for: .touchUpInside)
        layout(view)
        #expect(isEffectivelyHidden(panel))

        auto.sendActions(for: .touchUpInside)
        quickInsert.sendActions(for: .touchUpInside)
        layout(view)
        #expect(isEffectivelyHidden(panel))

        quickInsert.sendActions(for: .touchUpInside)
        auto.sendActions(for: .touchUpInside)
        layout(view)
        #expect(!isEffectivelyHidden(panel))

        view.render(
            presentation(
                status: .listening,
                voiceStage: .listening,
                cancelIsVisible: true
            )
        )
        layout(view)
        #expect(isEffectivelyHidden(panel))
        #expect(!auto.isEnabled)
    }

    @Test func narrowPhoneKeepsEveryEditingControlAtLeast44PointsWide()
        throws {
        for width: CGFloat in [320, 375, 390, 393, 430] {
            let view = makeView(width: width)
            view.render(presentation(showsInputModeSwitchKey: true))
            layout(view)

            for identifier in [
                "keyboard.brand-stage.quick-insert-toggle",
                "keyboard.brand-stage.auto",
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

    @Test func quickInsertRowsKeepEveryChoiceAtLeast44PointsSquare() throws {
        for width: CGFloat in [320, 375, 393, 430] {
            let view = makeView(width: width)
            view.render(presentation())
            layout(view)
            let toggle = try button(
                "keyboard.brand-stage.quick-insert-toggle",
                in: view
            )
            toggle.sendActions(for: .touchUpInside)
            layout(view)

            for item in KeyboardQuickInsertCatalog.punctuation {
                let control = try button(
                    "keyboard.brand-stage.quick-insert.punctuation.\(item.id)",
                    in: view
                )
                #expect(control.bounds.width >= 43.9)
                #expect(control.bounds.height >= 43.9)
            }
            for item in KeyboardQuickInsertCatalog.emojiPrimary {
                let control = try button(
                    "keyboard.brand-stage.quick-insert.emoji.\(item.id)",
                    in: view
                )
                #expect(control.bounds.width >= 43.9)
                #expect(control.bounds.height >= 43.9)
            }
            for item in KeyboardQuickInsertCatalog.emojiSecondary {
                let control = try button(
                    "keyboard.brand-stage.quick-insert.emoji-secondary.\(item.id)",
                    in: view
                )
                #expect(control.bounds.width >= 43.9)
                #expect(control.bounds.height >= 43.9)
            }
            assertVisibleHierarchyHasNoAmbiguity(view)
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

    @Test func fullAccessStatusKeepsIndicatorAndHasNoRecoveryCopy()
        throws {
        let view = makeView(width: 393)
        view.render(
            presentation(
                status: .fullAccessRequired,
                voiceStage: .ready
            )
        )
        layout(view)

        let microphone = try button("keyboard.brand-stage.voice", in: view)

        #expect(!isEffectivelyHidden(microphone))
        #expect(microphone.isEnabled)
        #expect(
            view.descendant(
                UIStackView.self,
                identifier: "keyboard.brand-stage.recovery"
            ) == nil
        )
    }

    @Test func startingAndProcessingKeepTheCentralVoiceIndicatorVisible()
        throws {
        let view = makeView(width: 393)

        view.render(
            presentation(
                status: .starting,
                voiceStage: .starting,
                cancelIsVisible: true
            )
        )
        layout(view)

        let microphone = try button("keyboard.brand-stage.voice", in: view)
        let cancel = try button("keyboard.brand-stage.cancel", in: view)
        #expect(!isEffectivelyHidden(microphone))
        #expect(!microphone.isEnabled)
        #expect(microphone.accessibilityValue == "Starting")
        #expect(
            view.descendant(
                UILabel.self,
                identifier: "keyboard.brand-stage.progress"
            ) == nil
        )
        #expect(!isEffectivelyHidden(cancel))

        view.render(
            presentation(
                status: .processing,
                voiceStage: .processing,
                cancelIsVisible: true
            )
        )
        layout(view)

        let activity = try #require(
            view.descendant(
                KeyboardVoiceActivityIndicatorView.self,
                identifier: "keyboard.brand-stage.voice-indicator"
            )
        )
        #expect(!isEffectivelyHidden(microphone))
        #expect(!microphone.isEnabled)
        #expect(microphone.accessibilityValue == "Recognizing")
        #expect(activity.phase == .recognizing)
        #expect(
            view.descendant(
                UILabel.self,
                identifier: "keyboard.brand-stage.progress"
            ) == nil
        )
        #expect(!isEffectivelyHidden(cancel))
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

                #expect(logo.bounds.width >= 24)
                #expect(logo.bounds.height >= 24)
                #expect(isEffectivelyHidden(logo))
                #expect(!isEffectivelyHidden(voice))
                #expect(voice.bounds.width >= 87.9)
                #expect(voice.bounds.height >= 87.9)
                #expect(globe.isHidden == !showsGlobe)

                let visibleIdentifiers = compactControlIdentifiers(
                    showsGlobe: showsGlobe
                )
                var boundedViews: [UIView] = [voice]
                for identifier in visibleIdentifiers {
                    let control = try button(identifier, in: view)
                    #expect(control.bounds.width >= 43.9)
                    #expect(control.bounds.height >= 43.9)
                    #expect(!isEffectivelyHidden(control))
                    boundedViews.append(control)
                }

                let space = try button("keyboard.brand-stage.space", in: view)
                #expect(
                    frame(of: voice, in: view).maxX
                        < frame(of: space, in: view).minX
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
        let space = try button("keyboard.brand-stage.space", in: view)
        let initialFrames = controlFrames(in: view)

        #expect(
            frame(of: voice, in: view).maxX
                < frame(of: space, in: view).minX
        )

        fixture.host.frame.size.height = 302
        view.updatePreferredHeight(
            for: regularPhoneTraits(userInterfaceStyle: .light)
        )
        layout(fixture)

        #expect(
            frame(of: voice, in: view).maxY
                < frame(of: space, in: view).minY
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
                < frame(of: space, in: view).minX
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
        window.rootViewController = hostController
        window.isHidden = false
        hostController.view.frame = window.bounds
        hostController.view.layoutIfNeeded()
        hostController.additionalSafeAreaInsets = UIEdgeInsets(
            top: safeAreaInsets.top - hostController.view.safeAreaInsets.top,
            left: safeAreaInsets.left,
            bottom: safeAreaInsets.bottom,
            right: safeAreaInsets.right
        )

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
        automaticVoiceAction: KeyboardVoiceAction = .standard,
        latestIsEnabled: Bool = false,
        cancelIsVisible: Bool = false,
        returnKey: KeyboardReturnKeyPresentation = .returnSymbol,
        showsInputModeSwitchKey: Bool = true
    ) -> BrandStageKeyboardPresentation {
        BrandStageKeyboardPresentation(
            status: status,
            voiceStage: voiceStage,
            automaticVoiceAction: automaticVoiceAction,
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

    private func switchControl(
        _ identifier: String,
        in view: UIView
    ) throws -> UISwitch {
        try #require(
            view.descendant(UISwitch.self, identifier: identifier)
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
            "keyboard.brand-stage.quick-insert-toggle",
            "keyboard.brand-stage.auto",
            "keyboard.brand-stage.latest",
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
            #expect(
                controlFrame.maxY <= safeBounds.maxY,
                "\(descendant.accessibilityIdentifier ?? String(describing: type(of: descendant)))"
            )
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
