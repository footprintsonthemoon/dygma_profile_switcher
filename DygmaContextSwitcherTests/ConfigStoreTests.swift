import XCTest
@testable import DygmaContextSwitcher

final class ConfigStoreTests: XCTestCase {

    private var store: ConfigStore!
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = ConfigStore()
        // Remove any config file left by a previous test run so each test starts clean
        try? FileManager.default.removeItem(at: store.configFileURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: store.configFileURL)
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testDefaultsWhenNoFile() {
        // When no file exists, load returns default config
        store.load()
        XCTAssertEqual(store.config.version, 1)
        XCTAssertEqual(store.config.defaults.debounceMs, 150)
        XCTAssertTrue(store.config.mappings.isEmpty)
        XCTAssertTrue(store.config.device.autoDetect)
    }

    func testSaveAndLoadRoundtrip() throws {
        store.load()
        var config = store.config
        config.mappings.append(AppMapping(
            bundleIdentifier: "com.test.app",
            displayName: "Test App",
            profile: MappingProfile(layer: 3)
        ))
        try store.save(config)

        let store2 = ConfigStore()
        store2.load()
        XCTAssertEqual(store2.config.mappings.count, 1)
        XCTAssertEqual(store2.config.mappings[0].bundleIdentifier, "com.test.app")
        XCTAssertEqual(store2.config.mappings[0].profile.layer, 3)
    }

    func testCorruptJsonReturnsDefaults() {
        let url = store.configFileURL
        try! FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! "not valid json {{{".write(to: url, atomically: true, encoding: .utf8)
        store.load()
        XCTAssertEqual(store.config.version, 1)   // defaults
        XCTAssertTrue(store.config.mappings.isEmpty)
    }

    func testValidationRejectsOutOfRangeLayer() throws {
        store.load()
        var config = store.config
        config.mappings.append(AppMapping(
            bundleIdentifier: "com.bad.app",
            displayName: "Bad",
            profile: MappingProfile(layer: 99)  // invalid
        ))
        try store.save(config)
        let store2 = ConfigStore()
        store2.load()
        XCTAssertTrue(store2.config.mappings.isEmpty, "Out-of-range layer mapping should be removed")
    }

    func testValidationRemovesAllNilProfile() throws {
        store.load()
        var config = store.config
        config.mappings.append(AppMapping(
            bundleIdentifier: "com.empty.app",
            displayName: "Empty",
            profile: MappingProfile()   // all nil
        ))
        try store.save(config)
        let store2 = ConfigStore()
        store2.load()
        XCTAssertTrue(store2.config.mappings.isEmpty, "All-nil profile mapping should be removed")
    }

    func testConfigFileUsesFileManagerPaths() {
        // Path must not contain a literal "~" (should be expanded)
        let path = store.configFileURL.path
        XCTAssertFalse(path.contains("~"), "Config path must not contain unexpanded tilde")
        XCTAssertTrue(path.contains("Application Support"), "Config must be in Application Support")
    }
}
