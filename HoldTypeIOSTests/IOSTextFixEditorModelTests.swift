import Foundation
import HoldTypeDomain
import Testing
@testable import HoldTypeIOS

@MainActor
struct IOSTextFixEditorModelTests {
    @Test func loadMustSucceedBeforeTheEditorCanWrite() async {
        let store = IOSTextFixEditorTestStore()
        await store.setLoadShouldFail(true)
        let callbacks = IOSTextFixEditorCallbackRecorder()
        let model = makeModel(store: store, callbacks: callbacks)

        #expect(!(await model.load()))
        #expect(model.catalog == nil)
        #expect(model.failure == .loadFailed)
        #expect(!model.beginNewCustomAction(id: "custom.blocked"))
        #expect(
            model.failure
                == .changeRejected(.catalogNotLoaded)
        )
        #expect(!(await model.restoreDefaults()))
        #expect(await store.saveCount() == 0)
        #expect(callbacks.unsavedStates.isEmpty)
        #expect(callbacks.blockingStates == [true, false])
    }

    @Test func searchFindsTitlesAndPrivatePromptsWithoutChangingCatalog()
        async
    {
        let store = IOSTextFixEditorTestStore()
        let model = makeModel(store: store)

        #expect(await model.load())
        model.searchText = "shorter"
        #expect(model.filteredActions.map(\.id) == ["default.make-shorter"])

        model.searchText = "clean Markdown"
        #expect(model.filteredActions.map(\.id) == ["default.markdown"])

        model.searchText = "  "
        #expect(model.filteredActions == TextFixCatalog.defaults.actions)
        #expect(await store.saveCount() == 0)
    }

    @Test func builtInsStayPinnedAndRejectEveryWritePath() async {
        let store = IOSTextFixEditorTestStore()
        let model = makeModel(store: store)
        #expect(await model.load())

        #expect(
            !(await model.setCustomActionEnabled(
                id: TextFixAction.translateIdentifier,
                isEnabled: false
            ))
        )
        #expect(model.failure == .changeRejected(.builtInReadOnly))
        #expect(
            !(await model.deleteCustomAction(
                id: TextFixAction.fixIdentifier
            ))
        )
        #expect(model.failure == .changeRejected(.builtInReadOnly))
        #expect(
            !model.beginEditingCustomAction(
                id: TextFixAction.translateIdentifier
            )
        )
        #expect(model.failure == .changeRejected(.builtInReadOnly))
        #expect(
            model.catalog?.actions.prefix(2).map(\.id) == [
                TextFixAction.translateIdentifier,
                TextFixAction.fixIdentifier,
            ]
        )
        #expect(await store.saveCount() == 0)
    }

    @Test func newDraftPersistsExactFieldsAndPublishesSceneState()
        async throws
    {
        let store = IOSTextFixEditorTestStore()
        let callbacks = IOSTextFixEditorCallbackRecorder()
        let model = makeModel(store: store, callbacks: callbacks)
        let id = IOSTextFixEditorDraft.newIdentifier(
            uuid: UUID(
                uuid: (0x31, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)
            )
        )

        #expect(await model.load())
        #expect(model.beginNewCustomAction(id: id))
        var draft = try #require(model.activeDraft)
        draft.title = "Exact Custom Fix"
        draft.prompt = "  Preserve this prompt exactly.  "
        draft.icon = .formal
        draft.isEnabled = false
        #expect(model.updateActiveDraft(draft))
        #expect(model.hasUnsavedChanges)
        #expect(callbacks.unsavedStates == [true])
        #expect(model.beginNewCustomAction(id: id))
        #expect(model.activeDraft == draft)

        #expect(await model.saveActiveDraft())
        let saved = await store.latestSavedCatalog()?.action(id: id)
        #expect(saved?.title == "Exact Custom Fix")
        #expect(saved?.prompt == "  Preserve this prompt exactly.  ")
        #expect(saved?.icon == .formal)
        #expect(saved?.isEnabled == false)
        #expect(model.activeDraft == nil)
        #expect(!model.hasUnsavedChanges)
        #expect(callbacks.unsavedStates == [true, false])
        #expect(callbacks.blockingStates == [true, false, true, false])
    }

    @Test func failedSaveRollsBackCatalogAndRetainsEditableDraft()
        async throws
    {
        let original = TextFixCatalog.defaults
        let store = IOSTextFixEditorTestStore(catalog: original)
        let callbacks = IOSTextFixEditorCallbackRecorder()
        let model = makeModel(store: store, callbacks: callbacks)
        #expect(await model.load())
        #expect(
            model.beginEditingCustomAction(
                id: "default.improve-writing"
            )
        )
        var draft = try #require(model.activeDraft)
        draft.title = "Unsaved Canary"
        #expect(model.updateActiveDraft(draft))
        await store.setSaveShouldFail(true)

        #expect(!(await model.saveActiveDraft()))
        #expect(model.catalog == original)
        #expect(model.activeDraft?.title == "Unsaved Canary")
        #expect(model.failure == .saveFailed)
        #expect(model.hasUnsavedChanges)
        #expect(await store.saveCount() == 0)

        model.discardActiveDraft()
        #expect(model.activeDraft == nil)
        #expect(!model.hasUnsavedChanges)
        #expect(callbacks.unsavedStates == [true, false])
    }

    @Test func invalidDraftNeverReachesPersistence() async throws {
        let original = TextFixCatalog.defaults
        let store = IOSTextFixEditorTestStore(catalog: original)
        let model = makeModel(store: store)
        #expect(await model.load())
        #expect(model.beginNewCustomAction(id: "custom.invalid"))
        var draft = try #require(model.activeDraft)
        draft.title = String(
            repeating: "a",
            count: TextFixAction.maximumTitleCharacterCount + 1
        )
        draft.prompt = "Valid prompt"
        #expect(model.updateActiveDraft(draft))

        #expect(!(await model.saveActiveDraft()))
        #expect(
            model.failure
                == .changeRejected(
                    .invalidDraft(
                        .titleTooLong(
                            maximumCharacterCount:
                                TextFixAction.maximumTitleCharacterCount
                        )
                    )
                )
        )
        #expect(model.catalog == original)
        #expect(model.activeDraft == draft)
        #expect(await store.saveCount() == 0)
    }

    @Test func listMutationsPersistToggleOrderDeleteAndRestore()
        async throws
    {
        let store = IOSTextFixEditorTestStore()
        let model = makeModel(store: store)
        #expect(await model.load())
        let firstID = try #require(model.catalog?.customActions.first?.id)
        let customCount = try #require(model.catalog?.customActions.count)

        #expect(
            await model.setCustomActionEnabled(
                id: firstID,
                isEnabled: false
            )
        )
        #expect(
            await model.moveCustomActions(
                fromOffsets: IndexSet(integer: 0),
                toOffset: customCount
            )
        )
        #expect(
            model.catalog?.customActions.last?.id == firstID
        )

        #expect(
            await model.deleteCustomAction(id: "default.summarize")
        )
        #expect(model.catalog?.action(id: "default.summarize") == nil)
        #expect(await model.restoreDefaults())
        #expect(
            model.catalog?.customActions.last?.id == "default.summarize"
        )
        #expect(
            model.catalog?.actions.prefix(2).map(\.id) == [
                TextFixAction.translateIdentifier,
                TextFixAction.fixIdentifier,
            ]
        )
        #expect(await store.saveCount() == 4)
    }

    private func makeModel(
        store: IOSTextFixEditorTestStore,
        callbacks: IOSTextFixEditorCallbackRecorder? = nil
    ) -> IOSTextFixEditorModel {
        IOSTextFixEditorModel(
            client: store.client(),
            onUnsavedStateChange: {
                callbacks?.recordUnsaved($0)
            },
            onBlockingStateChange: {
                callbacks?.recordBlocking($0)
            }
        )
    }
}
