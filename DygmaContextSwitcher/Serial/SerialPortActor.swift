import Foundation
import Darwin

/// Main-actor-isolated serial port using POSIX file I/O + DispatchSource for async reading.
/// DispatchSource fires on DispatchQueue.main when data is available, avoiding any thread/actor
/// mismatch that ORSSerialPort's delegate pattern can suffer under Swift concurrency.
@MainActor
final class SerialPortActor {

    private var fd: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var responseBuffer = Data()
    private var pendingContinuation: CheckedContinuation<String, Error>?
    private var timeoutTask: Task<Void, Never>?

    static let commandTimeoutSeconds: TimeInterval = 2.0

    // MARK: - Connection

    func connect(portPath: String, baudRate: Int = 115_200) async throws {
        disconnect()

        // Open the serial port non-blocking
        let newFd = Darwin.open(portPath, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard newFd >= 0 else {
            throw SerialPortError.portBusy(portPath)
        }

        // Configure baud rate and raw mode via termios
        var tio = termios()
        tcgetattr(newFd, &tio)
        cfmakeraw(&tio)
        cfsetspeed(&tio, speed_t(baudRate))
        tio.c_cflag |= tcflag_t(CLOCAL | CREAD)
        guard tcsetattr(newFd, TCSANOW, &tio) == 0 else {
            Darwin.close(newFd)
            throw SerialPortError.portBusy(portPath)
        }

        // Flush stale input/output
        tcflush(newFd, TCIOFLUSH)

        fd = newFd

        // DispatchSource fires on DispatchQueue.main whenever bytes are readable
        let source = DispatchSource.makeReadSource(fileDescriptor: newFd, queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            var buf = [UInt8](repeating: 0, count: 4096)
            let n = Darwin.read(self.fd, &buf, 4096)
            if n > 0 {
                AppLogger.shared.log("Serial read \(n) bytes", level: .info)
                self.processIncomingData(Data(buf.prefix(n)))
            }
        }
        source.resume()
        readSource = source

        // Brief warm-up — USB CDC devices may need settling time after open
        try? await Task.sleep(nanoseconds: 200_000_000)
    }

    func disconnect() {
        cancelPending(with: SerialPortError.notOpen)
        readSource?.cancel()
        readSource = nil
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
        responseBuffer = Data()
    }

    var isConnected: Bool { fd >= 0 }

    // MARK: - Send Command

    /// Sends a Focus API command and waits for the `\n.\n` terminator.
    /// Throws `FocusError.timeout` if no complete response arrives within 2 seconds.
    func sendCommand(_ text: String) async throws -> String {
        guard fd >= 0 else { throw SerialPortError.notOpen }

        guard let data = (text + "\n").data(using: .utf8) else {
            throw SerialPortError.sendFailed("encoding")
        }

        responseBuffer = Data()

        return try await withCheckedThrowingContinuation { continuation in
            self.pendingContinuation = continuation

            // Arm timeout
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(SerialPortActor.commandTimeoutSeconds * 1_000_000_000))
                self?.cancelPending(with: FocusError.timeout)
            }

            AppLogger.shared.log("Sending command: \(text)", level: .info)

            // Blocking write is safe — at 115200 baud a short command takes < 1 ms
            data.withUnsafeBytes { ptr in
                _ = Darwin.write(self.fd, ptr.baseAddress!, data.count)
            }
        }
    }

    // MARK: - Internal

    private func cancelPending(with error: Error) {
        timeoutTask?.cancel()
        timeoutTask = nil
        if let c = pendingContinuation {
            pendingContinuation = nil
            c.resume(throwing: error)
        }
    }

    private func processIncomingData(_ data: Data) {
        responseBuffer.append(data)
        guard let raw = String(data: responseBuffer, encoding: .utf8) else { return }

        // Normalize CRLF → LF (Dygma Defy uses mixed line endings)
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
                            .replacingOccurrences(of: "\r", with: "\n")

        // Focus API: response ends with a line containing exactly "."
        if normalized.hasSuffix("\n.\n") || normalized == ".\n" || normalized.hasSuffix("\n.") {
            timeoutTask?.cancel()
            timeoutTask = nil
            let lines = normalized
                .components(separatedBy: "\n")
                .filter { $0 != "." && !$0.isEmpty }
                .joined(separator: "\n")
            let c = pendingContinuation
            pendingContinuation = nil
            responseBuffer = Data()
            c?.resume(returning: lines)
        }
    }
}

// MARK: - Errors

enum FocusError: Error, LocalizedError {
    case timeout
    case deviceRemoved
    case commandError(String)

    var errorDescription: String? {
        switch self {
        case .timeout:              return "Focus API command timed out (2s)"
        case .deviceRemoved:        return "Keyboard was disconnected"
        case .commandError(let m):  return "Keyboard returned error: \(m)"
        }
    }
}
