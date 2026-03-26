import Foundation

/// Pure mapping lookup: bundle ID → partial profile to apply.
/// Stateless except for the idempotency cache (lastAppliedLayer).
final class MappingLookup {

    /// Last layer index that was successfully sent — used to avoid redundant layer commands.
    private(set) var lastAppliedLayer: Int? = nil

    // MARK: - Lookup

    struct ResolvedProfile {
        let layer: Int?
        let ledBrightness: Int?
        let ledTheme: String?
        /// True if layer is identical to lastAppliedLayer — skip layer command.
        let layerAlreadyActive: Bool
    }

    /// Resolves which profile fields to apply for the given active app.
    /// Returns nil fields for unspecified values (non-destructive partial apply).
    func resolve(
        bundleId: String,
        mappings: [AppMapping],
        defaults: DefaultProfile
    ) -> ResolvedProfile {
        let profile: MappingProfile
        if let match = mappings.first(where: { $0.bundleIdentifier == bundleId }) {
            profile = match.profile
        } else {
            // Fall back to defaults. Layer always falls back to 0 (first layer) so
            // switching to an unmapped app reliably returns to the base layer.
            profile = MappingProfile(
                layer: defaults.layer ?? 0,
                ledTheme: defaults.ledTheme,
                ledBrightness: defaults.ledBrightness
            )
        }

        // Fall back to defaults for fields not set in the mapping
        let resolvedBrightness = profile.ledBrightness ?? defaults.ledBrightness
        let resolvedTheme = profile.ledTheme ?? defaults.ledTheme

        let layerAlreadyActive: Bool
        if let requested = profile.layer, requested == lastAppliedLayer {
            layerAlreadyActive = true
        } else {
            layerAlreadyActive = false
        }

        return ResolvedProfile(
            layer: profile.layer,
            ledBrightness: resolvedBrightness,
            ledTheme: resolvedTheme,
            layerAlreadyActive: layerAlreadyActive
        )
    }

    /// Updates the cached last-applied layer after a successful apply.
    func recordApplied(layer: Int?) {
        if let layer { lastAppliedLayer = layer }
    }

    /// Resets idempotency state (e.g., after reconnect).
    func resetCache() {
        lastAppliedLayer = nil
    }
}
