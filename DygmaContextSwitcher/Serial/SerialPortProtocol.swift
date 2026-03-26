import Foundation

/// Abstraction over a serial port connection.
/// Used for dependency injection and unit testing without real hardware.
protocol SerialPortProtocol: AnyObject {
    /// Opens the port exclusively. Throws if busy or unavailable.
    func open() throws
    /// Closes the port, releasing exclusive access.
    func close()
    /// Writes raw bytes to the open port.
    func send(_ data: Data) throws
    /// Whether the port is currently open.
    var isOpen: Bool { get }
    /// Delegate receiving incoming data and disconnect events.
    var portDelegate: (any SerialPortDelegate)? { get set }
}

protocol SerialPortDelegate: AnyObject {
    /// Called when bytes arrive from the device.
    func didReceiveData(_ data: Data)
    /// Called when the device is removed (USB unplug).
    func portWasRemovedFromSystem()
}

// MARK: - Errors

enum SerialPortError: Error, LocalizedError {
    case portBusy(String)
    case sendFailed(String)
    case notOpen

    var errorDescription: String? {
        switch self {
        case .portBusy(let path):   return "Serial port '\(path)' is busy (is Bazecor open?)"
        case .sendFailed(let msg):  return "Send failed: \(msg)"
        case .notOpen:              return "Port is not open"
        }
    }
}
