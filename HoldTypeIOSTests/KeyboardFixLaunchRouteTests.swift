import Foundation
import Testing
@testable import HoldTypeIOS

private typealias AppKeyboardFixLaunchRoute =
    HoldTypeIOS.KeyboardFixLaunchRoute

struct KeyboardFixLaunchRouteTests {
    @Test func canonicalRouteRoundTripsOneOpaqueRequestIdentifier() throws {
        let requestID = UUID()
        let route = AppKeyboardFixLaunchRoute(
            requestID: requestID
        )
        let url = try #require(route.url)

        #expect(
            url.absoluteString
                == "holdtype://keyboard-fix/"
                    + requestID.uuidString.lowercased()
        )
        #expect(AppKeyboardFixLaunchRoute(url: url) == route)
    }

    @Test func noncanonicalOrPayloadBearingRoutesFailClosed() throws {
        let requestID = try #require(
            UUID(uuidString: "abcdefab-cdef-abcd-efab-cdefabcdefab")
        )
        let lowercase = requestID.uuidString.lowercased()
        let candidates = [
            "holdtype://keyboard-fix/\(requestID.uuidString.uppercased())",
            "holdtype://keyboard-fix/\(lowercase)?source=secret",
            "holdtype://keyboard-fix/\(lowercase)#fragment",
            "holdtype://user@keyboard-fix/\(lowercase)",
            "holdtype://keyboard-fix/\(lowercase)/extra",
            "holdtype://keyboard-fix/not-a-uuid",
            "https://keyboard-fix/\(lowercase)",
        ]

        for candidate in candidates {
            let url = try #require(URL(string: candidate))
            #expect(AppKeyboardFixLaunchRoute(url: url) == nil)
        }
    }
}
