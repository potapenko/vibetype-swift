import SwiftUI

struct IOSTextFixEditorLoadFailureView: View {
    let failure: IOSTextFixEditorFailure?
    let isRetrying: Bool
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(
                failure == .loadFailed
                    ? "Fixes Unavailable"
                    : "Fixes Not Loaded",
                systemImage: "exclamationmark.triangle"
            )
        } description: {
            Text(
                "HoldType couldn’t read the saved Fixes catalog. "
                    + "No replacement catalog was written."
            )
        } actions: {
            Button(isRetrying ? "Loading…" : "Try Again", action: retry)
                .disabled(isRetrying)
        }
        .accessibilityIdentifier("ios.fixes.editor.load-failure")
    }
}
#Preview("Fixes load failure") {
    IOSTextFixEditorLoadFailureView(
        failure: .loadFailed,
        isRetrying: false,
        retry: {}
    )
}
