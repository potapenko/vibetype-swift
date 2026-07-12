import SwiftUI

struct IOSDestinationLoadingView: View {
    let title: String

    var body: some View {
        ProgressView(title)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct IOSDestinationLoadFailureView: View {
    let title: String
    let description: String
    let isRetrying: Bool
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(description)
        } actions: {
            Button(action: retry) {
                if isRetrying {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Retrying…")
                    }
                } else {
                    Text("Try Again")
                }
            }
            .accessibilityLabel(isRetrying ? "Retrying" : "Try Again")
            .disabled(isRetrying)
        }
    }
}

struct IOSSaveFailureSection: View {
    let subject: String

    var body: some View {
        Section {
            Label {
                Text(
                    "Changes weren’t saved. The previous \(subject.lowercased()) "
                    + "remains active. Repeat the specific change to try again."
                )
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
