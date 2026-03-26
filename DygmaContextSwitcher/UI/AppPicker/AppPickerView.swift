import SwiftUI

/// Picker UI showing running apps with icons.
/// No text entry — user selects from list or browses /Applications.
struct AppPickerView: View {
    @ObservedObject var viewModel: AppPickerViewModel
    let onSelect: (String, String) -> Void

    @State private var searchText = ""

    private var filtered: [AppInfo] {
        guard !searchText.isEmpty else { return viewModel.apps }
        return viewModel.apps.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search apps…", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            if viewModel.isLoading {
                ProgressView("Loading apps…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                if #available(macOS 14.0, *) {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    Text("No results for \"\(searchText)\"")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                List(filtered) { app in
                    Button {
                        onSelect(app.id, app.displayName)
                    } label: {
                        HStack(spacing: 10) {
                            Image(nsImage: app.icon)
                                .resizable()
                                .frame(width: 32, height: 32)
                                .cornerRadius(6)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.displayName).font(.body)
                                Text(app.id)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            HStack {
                Button("Browse Installed Apps…") {
                    viewModel.browseInstalledApp(onSelect: onSelect)
                }
                .controlSize(.small)
                Spacer()
                Button("Refresh") { viewModel.loadRunningApps() }
                    .controlSize(.small)
            }
            .padding(10)
        }
        .onAppear { viewModel.loadRunningApps() }
    }
}
