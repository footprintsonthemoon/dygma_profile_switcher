import Foundation

// MARK: - Root Configuration

struct AppConfig: Codable {
    var version: Int
    var device: DeviceConfig
    var defaults: DefaultProfile
    var mappings: [AppMapping]
    var runtime: RuntimePreferences
    var logging: LoggingConfig

    init() {
        version = 1
        device = DeviceConfig()
        defaults = DefaultProfile()
        mappings = []
        runtime = RuntimePreferences()
        logging = LoggingConfig()
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version  = try c.decodeIfPresent(Int.self,                forKey: .version)  ?? 1
        device   = try c.decodeIfPresent(DeviceConfig.self,       forKey: .device)   ?? DeviceConfig()
        defaults = try c.decodeIfPresent(DefaultProfile.self,     forKey: .defaults) ?? DefaultProfile()
        mappings = try c.decodeIfPresent([AppMapping].self,       forKey: .mappings) ?? []
        runtime  = try c.decodeIfPresent(RuntimePreferences.self, forKey: .runtime)  ?? RuntimePreferences()
        logging  = try c.decodeIfPresent(LoggingConfig.self,      forKey: .logging)  ?? LoggingConfig()
    }
}

// MARK: - Device

struct DeviceConfig: Codable {
    var autoDetect: Bool
    var serial: SerialConfig

    init() {
        autoDetect = true
        serial = SerialConfig()
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        autoDetect = try c.decodeIfPresent(Bool.self,       forKey: .autoDetect) ?? true
        serial     = try c.decodeIfPresent(SerialConfig.self, forKey: .serial)   ?? SerialConfig()
    }
}

struct SerialConfig: Codable {
    var portPath: String?
    var baudRate: Int

    init() {
        portPath = nil
        baudRate = 115_200
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        portPath = try c.decodeIfPresent(String.self, forKey: .portPath)
        baudRate = try c.decodeIfPresent(Int.self,    forKey: .baudRate) ?? 115_200
    }
}

// MARK: - Default Profile

struct DefaultProfile: Codable {
    var layer: Int?
    var ledTheme: String?
    var ledBrightness: Int?
    var debounceMs: Int

    init() {
        layer = 0
        ledTheme = nil
        ledBrightness = 110
        debounceMs = 150
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        layer         = try c.decodeIfPresent(Int.self,    forKey: .layer)
        ledTheme      = try c.decodeIfPresent(String.self, forKey: .ledTheme)
        ledBrightness = try c.decodeIfPresent(Int.self,    forKey: .ledBrightness)
        debounceMs    = try c.decodeIfPresent(Int.self,    forKey: .debounceMs) ?? 150
    }
}

// MARK: - App Mapping

struct AppMapping: Codable, Identifiable {
    var id: UUID
    var bundleIdentifier: String
    var displayName: String
    var profile: MappingProfile

    init(bundleIdentifier: String, displayName: String, profile: MappingProfile) {
        self.id = UUID()
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.profile = profile
    }

    enum CodingKeys: String, CodingKey {
        case id, bundleIdentifier, displayName, profile
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id               = try c.decodeIfPresent(UUID.self,           forKey: .id)               ?? UUID()
        bundleIdentifier = try c.decode(String.self,                  forKey: .bundleIdentifier)
        displayName      = try c.decode(String.self,                  forKey: .displayName)
        profile          = try c.decode(MappingProfile.self,          forKey: .profile)
    }
}

struct MappingProfile: Codable {
    var layer: Int?
    var ledTheme: String?
    var ledBrightness: Int?

    /// Returns true if at least one field is set (invariant: all-nil is invalid)
    var hasAnyField: Bool { layer != nil || ledTheme != nil || ledBrightness != nil }

    init(layer: Int? = nil, ledTheme: String? = nil, ledBrightness: Int? = nil) {
        self.layer = layer
        self.ledTheme = ledTheme
        self.ledBrightness = ledBrightness
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        layer         = try c.decodeIfPresent(Int.self,    forKey: .layer)
        ledTheme      = try c.decodeIfPresent(String.self, forKey: .ledTheme)
        ledBrightness = try c.decodeIfPresent(Int.self,    forKey: .ledBrightness)
    }
}


// MARK: - Runtime Preferences

struct RuntimePreferences: Codable {
    var enabled: Bool
    var closePortWhenDisabled: Bool

    init() {
        enabled = true
        closePortWhenDisabled = true
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled               = try c.decodeIfPresent(Bool.self, forKey: .enabled)               ?? true
        closePortWhenDisabled = try c.decodeIfPresent(Bool.self, forKey: .closePortWhenDisabled) ?? true
    }
}

// MARK: - Logging

struct LoggingConfig: Codable {
    var level: LogLevel
    var path: String

    init() {
        level = .info
        path = "~/Library/Logs/DygmaContext/"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        level = try c.decodeIfPresent(LogLevel.self, forKey: .level) ?? .info
        path  = try c.decodeIfPresent(String.self,   forKey: .path)  ?? "~/Library/Logs/DygmaContext/"
    }
}

enum LogLevel: String, Codable, CaseIterable {
    case debug, info, warning, error
}
