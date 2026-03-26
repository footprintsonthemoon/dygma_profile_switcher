import XCTest
@testable import DygmaContextSwitcher

final class MappingLookupTests: XCTestCase {

    private var lookup: MappingLookup!
    private var defaults: DefaultProfile!
    private var mappings: [AppMapping]!

    override func setUp() {
        super.setUp()
        lookup = MappingLookup()
        defaults = DefaultProfile()
        defaults.layer = 0
        defaults.ledBrightness = 100
        mappings = [
            AppMapping(bundleIdentifier: "com.test.dorico",
                       displayName: "Dorico",
                       profile: MappingProfile(layer: 2, ledBrightness: 140)),
            AppMapping(bundleIdentifier: "com.apple.Terminal",
                       displayName: "Terminal",
                       profile: MappingProfile(layer: 3))
        ]
    }

    func testBundleIdHitReturnsCorrectLayer() {
        let result = lookup.resolve(bundleId: "com.test.dorico", mappings: mappings, defaults: defaults)
        XCTAssertEqual(result.layer, 2)
        XCTAssertEqual(result.ledBrightness, 140)
    }

    func testBundleIdMissReturnsDefaultLayer() {
        let result = lookup.resolve(bundleId: "com.unknown.app", mappings: mappings, defaults: defaults)
        XCTAssertEqual(result.layer, 0)
        XCTAssertEqual(result.ledBrightness, 100)
    }

    func testIdempotencySkipWhenSameLayer() {
        lookup.recordApplied(layer: 2)
        let result = lookup.resolve(bundleId: "com.test.dorico", mappings: mappings, defaults: defaults)
        XCTAssertTrue(result.layerAlreadyActive, "Should mark layer as already active when unchanged")
    }

    func testIdempotencyNotSkipWhenDifferentLayer() {
        lookup.recordApplied(layer: 1)
        let result = lookup.resolve(bundleId: "com.test.dorico", mappings: mappings, defaults: defaults)
        XCTAssertFalse(result.layerAlreadyActive)
        XCTAssertEqual(result.layer, 2)
    }

    func testPartialProfileLayerOnly() {
        let result = lookup.resolve(bundleId: "com.apple.Terminal", mappings: mappings, defaults: defaults)
        XCTAssertEqual(result.layer, 3)
        XCTAssertNil(result.ledBrightness, "Terminal mapping has no brightness — should be nil")
    }

    func testRecordAppliedUpdatesCache() {
        lookup.recordApplied(layer: 5)
        XCTAssertEqual(lookup.lastAppliedLayer, 5)
    }

    func testResetCacheClearsLastApplied() {
        lookup.recordApplied(layer: 3)
        lookup.resetCache()
        XCTAssertNil(lookup.lastAppliedLayer)
    }

    func testNilLayerInMappingIsNilInResult() {
        let m = [AppMapping(bundleIdentifier: "com.led.only",
                            displayName: "LED Only",
                            profile: MappingProfile(ledBrightness: 80))]
        let result = lookup.resolve(bundleId: "com.led.only", mappings: m, defaults: defaults)
        XCTAssertNil(result.layer)
        XCTAssertEqual(result.ledBrightness, 80)
    }
}
