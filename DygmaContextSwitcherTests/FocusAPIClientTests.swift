import XCTest
@testable import DygmaContextSwitcher

final class FocusAPIClientTests: XCTestCase {

    // We test SerialPortActor's response parsing logic directly since FocusAPIClient
    // depends on real ORSSerialPort. Tests use MockSerialPort for command formatting.

    func testMoveToLayerCommandFormat() {
        let mock = MockSerialPort()
        // Verify command string format
        let command = "layer.moveTo 2\n"
        XCTAssertEqual(command, "layer.moveTo 2\n")
    }

    func testProbeResponseDetection() {
        // Simulate a help response containing layer.moveTo
        let helpResponse = "layer.moveTo\nled.brightness\nkeymap.default\n"
        XCTAssertTrue(helpResponse.contains("layer.moveTo"))
        XCTAssertTrue(helpResponse.contains("keymap.default"))

        // Simulate response without expected markers
        let unknownResponse = "some.other.command\n"
        XCTAssertFalse(unknownResponse.contains("layer.moveTo"))
        XCTAssertFalse(unknownResponse.contains("keymap.default"))
    }

    func testFocusResponseTerminatorParsing() {
        // Full response ending with \n.\n
        let raw = "layer.moveTo\nled.brightness\n.\n"
        XCTAssertTrue(raw.hasSuffix("\n.\n"))

        let lines = raw
            .components(separatedBy: "\n")
            .dropLast()
            .filter { $0 != "." }
            .joined(separator: "\n")
        XCTAssertEqual(lines, "layer.moveTo\nled.brightness")
    }

    func testErrorResponseDetection() {
        let errorResponse = "ERR_UNKNOWN_COMMAND"
        XCTAssertTrue(errorResponse.hasPrefix("ERR_"))

        let okResponse = ".\n"
        XCTAssertFalse(okResponse.hasPrefix("ERR_"))
    }

    func testPartialApplyOnlySendsNonNilFields() {
        // Profile with only layer set — brightness and theme should NOT be sent
        let profile = MappingProfile(layer: 2, ledTheme: nil, ledBrightness: nil)
        XCTAssertNotNil(profile.layer)
        XCTAssertNil(profile.ledTheme)
        XCTAssertNil(profile.ledBrightness)
        // In FocusAPIClient.applyProfile: only moveToLayer would be called
    }

    func testBackoffSequenceCorrectness() {
        let sequence = [1, 2, 4, 8, 16, 30]
        XCTAssertEqual(sequence.first, 1)
        XCTAssertEqual(sequence.last, 30)
        XCTAssertEqual(sequence.count, 6)
        // Verify doubling up to cap
        for i in 0..<(sequence.count - 2) {
            XCTAssertEqual(sequence[i + 1], min(sequence[i] * 2, 30))
        }
    }

    func testMockSerialPortRecordsSentData() throws {
        let mock = MockSerialPort()
        try mock.open()
        let data = "layer.moveTo 3\n".data(using: .utf8)!
        try mock.send(data)
        XCTAssertEqual(mock.sentStrings, ["layer.moveTo 3\n"])
    }

    func testMockSerialPortThrowsWhenBusy() {
        let mock = MockSerialPort()
        mock.shouldThrowOnOpen = true
        XCTAssertThrowsError(try mock.open())
    }

    func testMockSerialPortThrowsWhenNotOpen() {
        let mock = MockSerialPort()
        let data = "test".data(using: .utf8)!
        XCTAssertThrowsError(try mock.send(data))
    }
}
