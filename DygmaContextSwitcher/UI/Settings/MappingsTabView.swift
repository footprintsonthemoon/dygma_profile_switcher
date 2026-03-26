import SwiftUI
import AppKit

struct MappingsTabView: View {
    @EnvironmentObject var profileSwitcher: ProfileSwitcher
    @EnvironmentObject var configStore: ConfigStore

    @State private var showPicker = false
    @State private var testFeedback: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            if configStore.config.mappings.isEmpty {
                if #available(macOS 14.0, *) {
                    ContentUnavailableView(
                        "No Mappings",
                        systemImage: "keyboard.badge.ellipsis",
                        description: Text("Add an app to automatically switch layers when it becomes active.")
                    )
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "keyboard.badge.ellipsis")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No Mappings")
                            .font(.headline)
                        Text("Add an app to automatically switch layers when it becomes active.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                }
            } else {
                List {
                    ForEach(configStore.config.mappings) { mapping in
                        MappingRow(mapping: mapping,
                                   onTest: { testMapping(mapping) },
                                   onUpdate: { updateMapping(mapping, profile: $0) },
                                   onDelete: { deleteMapping(mapping) })
                    }
                }
            }

            Divider()

            HStack {
                Button("Add App…") { showPicker = true }
                    .buttonStyle(.borderedProminent)
                Spacer()
                if let feedback = testFeedback {
                    Text(feedback)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            .padding(12)
        }
        .sheet(isPresented: $showPicker) {
            AppPickerSheet { bundleId, displayName in
                addMapping(bundleIdentifier: bundleId, displayName: displayName)
            }
        }
    }

    // MARK: - Actions

    private func testMapping(_ mapping: AppMapping) {
        testFeedback = "Testing…"
        Task {
            do {
                try await profileSwitcher.focusClient.applyProfile(mapping.profile)
                await MainActor.run { testFeedback = "Applied ✓" }
            } catch {
                await MainActor.run { testFeedback = "Error: \(error.localizedDescription)" }
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run { testFeedback = nil }
        }
    }

    private func updateMapping(_ mapping: AppMapping, profile: MappingProfile) {
        var updated = configStore.config
        if let idx = updated.mappings.firstIndex(where: { $0.id == mapping.id }) {
            updated.mappings[idx].profile = profile
            try? configStore.save(updated)
            profileSwitcher.reloadConfig()
        }
    }

    private func deleteMapping(_ mapping: AppMapping) {
        var updated = configStore.config
        updated.mappings.removeAll { $0.id == mapping.id }
        try? configStore.save(updated)
        profileSwitcher.reloadConfig()
    }

    private func addMapping(bundleIdentifier: String, displayName: String) {
        // Default: layer 0, brightness 110 — user edits from the list
        let profile = MappingProfile(layer: 0, ledBrightness: 110)
        let mapping = AppMapping(bundleIdentifier: bundleIdentifier,
                                 displayName: displayName,
                                 profile: profile)
        var updated = configStore.config
        // Avoid duplicates
        if !updated.mappings.contains(where: { $0.bundleIdentifier == bundleIdentifier }) {
            updated.mappings.append(mapping)
            try? configStore.save(updated)
            profileSwitcher.reloadConfig()
        }
    }
}

// MARK: - Mapping Row

struct MappingRow: View {
    let mapping: AppMapping
    let onTest: () -> Void
    let onUpdate: (MappingProfile) -> Void
    let onDelete: () -> Void

    @State private var appIcon: NSImage? = nil
    @State private var layer: Int = 1
    @State private var brightness: Int = 110

    var body: some View {
        HStack(spacing: 10) {
            // App icon
            Group {
                if let icon = appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 32, height: 32)
                        .cornerRadius(6)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.quaternary)
                        .frame(width: 32, height: 32)
                }
            }

            // App name + bundle ID
            VStack(alignment: .leading, spacing: 2) {
                Text(mapping.displayName).font(.body)
                Text(mapping.bundleIdentifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Layer stepper — displays 1-based (Bazecor numbering), stores 0-based internally
            HStack(spacing: 4) {
                Text("Layer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(layer)")
                    .font(.caption.monospacedDigit())
                    .frame(minWidth: 16, alignment: .trailing)
                Stepper("", value: $layer, in: 1...10, step: 1)
                    .labelsHidden()
                    .controlSize(.small)
                    .onChange(of: layer, perform: { newLayer in
                        var profile = mapping.profile
                        profile.layer = newLayer - 1
                        onUpdate(profile)
                    })
            }

            // Brightness stepper — range 0–255
            HStack(spacing: 4) {
                Text("Brightness")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(brightness)")
                    .font(.caption.monospacedDigit())
                    .frame(minWidth: 24, alignment: .trailing)
                Stepper("", value: $brightness, in: 0...255, step: 5)
                    .labelsHidden()
                    .controlSize(.small)
                    .onChange(of: brightness, perform: { newBrightness in
                        var profile = mapping.profile
                        profile.ledBrightness = newBrightness
                        onUpdate(profile)
                    })
            }

            Button("Test", action: onTest)
                .controlSize(.small)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .controlSize(.small)
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        }
        .onAppear {
            layer = (mapping.profile.layer ?? 0) + 1
            brightness = mapping.profile.ledBrightness ?? 110
            // Migrate existing mappings that have no brightness set
            if mapping.profile.ledBrightness == nil {
                var profile = mapping.profile
                profile.ledBrightness = 110
                onUpdate(profile)
            }
            loadIcon()
        }
    }

    private func loadIcon() {
        DispatchQueue.global(qos: .utility).async {
            let ws = NSWorkspace.shared
            // Try running apps first
            if let app = NSWorkspace.shared.runningApplications
                .first(where: { $0.bundleIdentifier == mapping.bundleIdentifier }),
               let icon = app.icon {
                DispatchQueue.main.async { appIcon = icon }
                return
            }
            // Fall back to installed app lookup
            if let appURL = ws.urlForApplication(withBundleIdentifier: mapping.bundleIdentifier) {
                let icon = ws.icon(forFile: appURL.path)
                DispatchQueue.main.async { appIcon = icon }
            }
        }
    }
}

// MARK: - App Picker Sheet

struct AppPickerSheet: View {
    let onSelect: (String, String) -> Void
    @Environment(\.dismiss) var dismiss
    @StateObject private var vm = AppPickerViewModel()

    var body: some View {
        NavigationStack {
            AppPickerView(viewModel: vm, onSelect: { bundleId, name in
                onSelect(bundleId, name)
                dismiss()
            })
            .navigationTitle("Choose App")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(width: 420, height: 520)
    }
}
