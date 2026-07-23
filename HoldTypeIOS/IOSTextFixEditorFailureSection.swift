import SwiftUI

struct IOSTextFixEditorFailureSection: View {
    let failure: IOSTextFixEditorFailure
    let dismiss: () -> Void

    var body: some View {
        Section {
            Label(
                message,
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.footnote)
            .foregroundStyle(.red)

            Button("Dismiss", action: dismiss)
        }
    }

    private var message: String {
        switch failure {
        case .loadFailed:
            "Fixes could not be loaded."
        case .saveFailed:
            "The change was not saved. Your saved catalog is unchanged."
        case .changeRejected:
            "That change is unavailable. Your saved catalog is unchanged."
        }
    }
}

#Preview("Fixes save failure") {
    Form {
        IOSTextFixEditorFailureSection(
            failure: .saveFailed,
            dismiss: {}
        )
    }
}
