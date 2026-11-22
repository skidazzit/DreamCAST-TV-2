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

    #if os(tvOS)
    @State private var isExpanded = false
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            #if os(tvOS)
            Text("SERVER PROVIDER")
                .font(.system(size: TVSettingsMetrics.labelFontSize, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.78))
                .padding(.horizontal, TVSettingsMetrics.rowHPadding)

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 16) {
                    Image(systemName: "server.rack")
                        .foregroundStyle(.white)
                    Text(store.providers.first(where: { $0.serverURL == serverURL })?.name
                         ?? "Select a server provider")
                        .lineLimit(1)
                        .foregroundStyle(.white)
                    Spacer(minLength: 8)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.white.opacity(0.78))
                }
                .font(.system(size: 25, weight: .medium))
                .padding(.horizontal, 22)
                .frame(height: 68)
            }
            .buttonStyle(TVPlaylistFieldButtonStyle(cornerRadius: 16))
            .accessibilityLabel("Server provider")
            .accessibilityValue(store.providers.first(where: { $0.serverURL == serverURL })?.name
                                ?? "None selected")
            .accessibilityHint("Press Select to expand or collapse the provider list")

            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(store.providers) { provider in
                        Button {
                            serverURL = provider.serverURL
                            withAnimation(.easeInOut(duration: 0.18)) {
                                isExpanded = false
                            }
                        } label: {
                            HStack(spacing: 16) {
                                Text(verbatim: provider.name)
                                    .font(.system(size: 24, weight: .medium))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Spacer()
                                if serverURL == provider.serverURL {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(.horizontal, 22)
                            .frame(height: 62)
                        }
                        .buttonStyle(TVPlaylistFieldButtonStyle(cornerRadius: 12))
                    }
                }
                .padding(12)
                .background(DreamCASTVisualSettings.theme.gradient,
                            in: RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(DreamCASTVisualSettings.theme.selectionAccent.opacity(0.35),
                                      lineWidth: 1)
                }
            }
            #else
            Picker("Server Provider", selection: $serverURL) {
                Text("Select a provider").tag("")
                ForEach(store.providers) { provider in
                    Text(verbatim: provider.name).tag(provider.serverURL)
                }
            }
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
