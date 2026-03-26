import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var profileSwitcher: ProfileSwitcher
    @EnvironmentObject var configStore: ConfigStore

    var body: some View {
        TabView {
            StatusTabView()
                .tabItem { Label("Status", systemImage: "info.circle") }

            MappingsTabView()
                .tabItem { Label("Mappings", systemImage: "keyboard") }

            DeviceTabView()
                .tabItem { Label("Device", systemImage: "cable.connector") }

            LogsTabView()
                .tabItem { Label("Logs", systemImage: "doc.text") }
        }
        .frame(minWidth: 580, minHeight: 420)
        .padding(8)
        .environmentObject(profileSwitcher)
        .environmentObject(configStore)
    }
}
