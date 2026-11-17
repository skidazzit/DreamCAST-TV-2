import SwiftUI

@Observable
final class XtreamProviderStore {
    static let shared = XtreamProviderStore()
    var providers = XtreamProvider.available

    func refresh() async {
        await XtreamProviderRefresh.shared.refresh()
        providers = XtreamProvider.available
    }
}

struct XtreamProviderPicker: View {
    @Binding var serverURL: String
    @State private var store = XtreamProviderStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Server Provider", selection: $serverURL) {
                Text("Select a provider").tag("")
                ForEach(store.providers) { provider in
                    Text(verbatim: provider.name).tag(provider.serverURL)
                }
            }
            #if !os(tvOS)
                .pickerStyle(.menu)
            #endif
            if store.providers.isEmpty {
                Text("No servers are set up. Contact app support.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .task { await store.refresh() }
        .onChange(of: store.providers.map(\.serverURL)) { _, _ in
            // Keep a selected provider selected if its address changed while open.
            guard !serverURL.isEmpty else { return }
            if let provider = XtreamProviderDirectory.provider(address: serverURL) {
                serverURL = provider.enabled ? provider.serverURL : ""
            }
        }
    }
}
