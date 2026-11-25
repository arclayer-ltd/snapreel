import XCTest
@testable import Snapreel

/// The test host is the real app, so this fails if the target or its host is misconfigured.
final class AppBundleTests: XCTestCase {
    func testHostIsSnapreel() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "co.arclayer.snapreel")
    }
}
