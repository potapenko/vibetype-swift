import SwiftUI

struct IOSHistoryHomeView: View {
    var body: some View {
        ContentUnavailableView {
            Label("History Unavailable", systemImage: "clock")
        } description: {
            Text(
                "Accepted results and recoverable failed attempts are not "
                + "displayed in this build."
            )
        }
        .navigationTitle("History")
        .accessibilityIdentifier(
            IOSContainingAppDestination.history.accessibilityIdentifier
        )
    }
}
