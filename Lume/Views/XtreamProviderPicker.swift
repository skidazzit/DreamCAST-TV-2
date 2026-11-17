import SwiftUI

/// Provider addresses come from the build's .env mapping, never user input.
struct XtreamProvider: Identifiable {
    let id: String
    let name: String
    let serverURL: String

    static let available: [XtreamProvider] = [
        ("DREAMCAST", "DreamCAST TV"),
        ("KLEPTO", "Klepto TV"),
        ("STRONG", "Strong"),
        ("IPTVEDITOR", "IPTVeditor")
    ].compactMap { id, name in
        guard let address = Bundle.main.object(forInfoDictionaryKey: "XtreamProvider\(id)URL") as? String else {
            return nil
        }
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        return XtreamProvider(id: id, name: name, serverURL: trimmed)
    }
}

struct XtreamProviderPicker: View {
    @Binding var serverURL: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Server Provider", selection: $serverURL) {
                Text("Select a provider").tag("")
                ForEach(XtreamProvider.available) { provider in
                    Text(verbatim: provider.name).tag(provider.serverURL)
                }
            }
            #if !os(tvOS)
                .pickerStyle(.menu)
            #endif
            if XtreamProvider.available.isEmpty {
                Text("No servers are set up. Contact app support.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
