import Foundation
@testable import DygmaContextSwitcher

/// Mock serial port for unit tests. No hardware required.
final class MockSerialPort: SerialPortProtocol {

    // MARK: - Configuration

    var shouldThrowOnOpen = false
    var shouldThrowOnSend = false

    // MARK: - Observations

    private(set) var openCallCount = 0
    private(set) var closeCallCount = 0
    private(set) var sentData: [Data] = []

    var sentStrings: [String] { sentData.compactMap { String(data: $0, encoding: .utf8) } }

    // MARK: - SerialPortProtocol

    var isOpen = false
    weak var portDelegate: (any SerialPortDelegate)?

    func open() throws {
        openCallCount += 1
        if shouldThrowOnOpen {
            throw SerialPortError.portBusy("/dev/cu.mock")
        }
        isOpen = true
    }

    func close() {
        closeCallCount += 1
        isOpen = false
    }

    func send(_ data: Data) throws {
        guard isOpen else { throw SerialPortError.notOpen }
        if shouldThrowOnSend { throw SerialPortError.sendFailed("mock error") }
        sentData.append(data)
    }

    // MARK: - Test Helpers

    /// Fires the delegate as if the device responded with `response`.
    func simulateResponse(_ response: String) {
        guard let data = response.data(using: .utf8) else { return }
        portDelegate?.didReceiveData(data)
    }

    /// Fires the delegate as if the device was unplugged.
    func simulateRemoval() {
        portDelegate?.portWasRemovedFromSystem()
    }

    func reset() {
        openCallCount = 0
        closeCallCount = 0
        sentData = []
        isOpen = false
        shouldThrowOnOpen = false
        shouldThrowOnSend = false
    }
}
