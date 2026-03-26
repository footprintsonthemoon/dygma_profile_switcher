import Foundation
import Combine

/// Loads and saves the app configuration atomically.
/// All paths are resolved at runtime via FileManager — no hardcoded user paths.
final class ConfigStore: ObservableObject {

    static let shared = ConfigStore()

    @Published private(set) var config: AppConfig = AppConfig()
    @Published private(set) var isFirstLaunch: Bool = false

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private let decoder = JSONDecoder()

    // MARK: - File Paths (resolved at runtime)

    var configFileURL: URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("DygmaContext", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    // MARK: - Load

    func load() {
        createDirectoryIfNeeded()

        guard FileManager.default.fileExists(atPath: configFileURL.path) else {
            config = AppConfig()
            isFirstLaunch = true
            try? save(config)
            return
        }

        do {
            let data = try Data(contentsOf: configFileURL)
            var loaded = try decoder.decode(AppConfig.self, from: data)
            loaded = migrate(loaded)
            validate(&loaded)
            config = loaded
        } catch {
            AppLogger.shared.log("Config load failed: \(error.localizedDescription). Using defaults.", level: .warning)
            config = AppConfig()
        }
    }

    // MARK: - Save

    @discardableResult
    func save(_ updated: AppConfig) throws -> AppConfig {
        createDirectoryIfNeeded()
        let data = try encoder.encode(updated)
        // Atomic write: write to temp file then replace
        let tmp = configFileURL.appendingPathExtension("tmp")
        try data.write(to: tmp, options: .atomic)
        _ = try FileManager.default.replaceItemAt(configFileURL, withItemAt: tmp)
        config = updated
        return updated
    }

    // MARK: - Validation

    private func validate(_ c: inout AppConfig) {
        // Layer range 0–9
        if let l = c.defaults.layer, !(0...9).contains(l) {
            AppLogger.shared.log("defaults.layer \(l) out of range 0-9 — reset to 0", level: .warning)
            c.defaults.layer = 0
        }
        // BaudRate positive
        if c.device.serial.baudRate <= 0 {
            AppLogger.shared.log("baudRate \(c.device.serial.baudRate) invalid — reset to 115200", level: .warning)
            c.device.serial.baudRate = 115_200
        }
        // Each mapping profile must have at least one field
        c.mappings = c.mappings.filter { m in
            if !m.profile.hasAnyField {
                AppLogger.shared.log("Mapping '\(m.displayName)' has all-nil profile — removed", level: .warning)
                return false
            }
            if let l = m.profile.layer, !(0...9).contains(l) {
                AppLogger.shared.log("Mapping '\(m.displayName)' layer \(l) out of range — removed", level: .warning)
                return false
            }
            return true
        }
        // Unique bundle IDs
        var seen = Set<String>()
        c.mappings = c.mappings.filter { m in
            guard seen.insert(m.bundleIdentifier).inserted else {
                AppLogger.shared.log("Duplicate mapping for '\(m.bundleIdentifier)' — removed", level: .warning)
                return false
            }
            return true
        }
    }

    // MARK: - Migration

    private func migrate(_ c: AppConfig) -> AppConfig {
        var updated = c
        // Future: if c.version < 2 { ... }
        updated.version = 1
        return updated
    }

    // MARK: - Directory

    private func createDirectoryIfNeeded() {
        let dir = configFileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir,
                                                     withIntermediateDirectories: true)
        }
    }
}
