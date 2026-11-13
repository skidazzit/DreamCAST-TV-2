#if os(tvOS)
import Darwin
import Foundation
import Network
import Observation
import SwiftUI

/// Short-lived LAN transfer, started only when the user selects Back Up/Restore.
/// Nothing is uploaded to a remote service. Each session has a random URL.
@MainActor
@Observable
final class DreamCASTTVLocalTransfer {
    private(set) var transferURL: String?
    private(set) var statusText = "Transfer is off"
    private(set) var pendingSettingsCount = 0
    private(set) var hasPendingRestore = false
    private(set) var resultText: String?

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var requests: [ObjectIdentifier: Data] = [:]
    private var sessionExpiry: Task<Void, Never>?
    private var pendingRestoreData: Data?
    private var token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    private let headerMarker = Data([13, 10, 13, 10])
    private let maxHeaderBytes = 16_384

    func start() {
        guard listener == nil else { return }
        guard let address = Self.localIPv4Address() else {
            statusText = "No local IP found. Connect Apple TV to your home network."
            return
        }
        do {
            let listener = try NWListener(using: .tcp, on: .any)
            self.listener = listener
            token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            statusText = "Starting local transfer…"
            resultText = nil
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        guard let port = listener.port else {
                            self.statusText = "Could not open the transfer port."
                            self.stop()
                            return
                        }
                        self.transferURL = "http://\(address):\(port.rawValue)/\(self.token)"
                        self.statusText = "Ready — open this address from your phone or Mac."
                    case .failed(let error):
                        self.statusText = "Transfer failed: \(error.localizedDescription)"
                        self.stop()
                    default:
                        break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in
                    self?.accept(connection)
                }
            }
            listener.start(queue: .main)
            // Do not leave a writable LAN endpoint running after Settings closes.
            sessionExpiry = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(600))
                guard !Task.isCancelled else { return }
                self?.stop()
            }
        } catch {
            statusText = "Transfer could not start: \(error.localizedDescription)"
            listener = nil
        }
    }

    func stop() {
        sessionExpiry?.cancel()
        sessionExpiry = nil
        listener?.cancel()
        listener = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
        requests.removeAll()
        transferURL = nil
        token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        if statusText.hasPrefix("Ready") || statusText.hasPrefix("Starting") {
            statusText = "Transfer is off"
        }
    }

    func dismissPendingRestore() {
        pendingRestoreData = nil
        pendingSettingsCount = 0
        hasPendingRestore = false
        resultText = "Restore cancelled. No settings were changed."
    }

    func approvePendingRestore() {
        guard let pendingRestoreData else { return }
        do {
            let count = try DreamCASTLocalSettingsBackup.restoreSettings(from: pendingRestoreData)
            resultText = "Restored \(count) settings. Restart DreamCAST TV to apply them."
            stop()
        } catch {
            resultText = "Could not restore settings: \(error.localizedDescription)"
        }
        self.pendingRestoreData = nil
        pendingSettingsCount = 0
        hasPendingRestore = false
    }

    private func accept(_ connection: NWConnection) {
        guard listener != nil else { connection.cancel(); return }
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        requests[id] = Data()
        connection.start(queue: .main)
        read(connection)
    }

    private func read(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self] data, _, completed, error in
            Task { @MainActor [weak self] in
                self?.received(data ?? Data(), on: connection, completed: completed || error != nil)
            }
        }
    }

    private func received(_ chunk: Data, on connection: NWConnection, completed: Bool) {
        let id = ObjectIdentifier(connection)
        guard var buffer = requests[id] else { return }
        buffer.append(chunk)
        let maximum = DreamCASTLocalSettingsBackup.maxBytes + maxHeaderBytes
        if buffer.count > maximum {
            respond(connection, status: "413 Payload Too Large", text: "Settings file is too large.")
            return
        }
        requests[id] = buffer
        guard let marker = buffer.range(of: headerMarker) else {
            if buffer.count > maxHeaderBytes || completed {
                respond(connection, status: "400 Bad Request", text: "Invalid request.")
            } else {
                read(connection)
            }
            return
        }
        guard marker.lowerBound <= maxHeaderBytes,
              let headers = String(data: buffer[..<marker.lowerBound], encoding: .utf8) else {
            respond(connection, status: "400 Bad Request", text: "Invalid headers.")
            return
        }
        let headerLines = headers.components(separatedBy: "\r\n")
        let request = (headerLines.first ?? "").split(separator: " ", omittingEmptySubsequences: true)
        guard request.count >= 2 else {
            respond(connection, status: "400 Bad Request", text: "Invalid request.")
            return
        }
        let method = String(request[0])
        let path = String(request[1]).components(separatedBy: "?").first ?? ""
        let lengthLine = headerLines.first { $0.lowercased().hasPrefix("content-length:") }
        let contentLength = lengthLine.flatMap {
            Int($0.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces))
        }
        if method == "POST" && (contentLength == nil || contentLength! > DreamCASTLocalSettingsBackup.maxBytes || contentLength! < 1) {
            respond(connection, status: "413 Payload Too Large", text: "Invalid file size.")
            return
        }
        let length = method == "POST" ? (contentLength ?? 0) : 0
        let needed = marker.upperBound + length
        if buffer.count < needed {
            if completed { respond(connection, status: "400 Bad Request", text: "Incomplete upload.") }
            else { read(connection) }
            return
        }

        // Prevent requests to guessed paths or attempts from unrelated sites.
        // The 128-bit token is only shown on the TV and in the paired browser.
        let sessionPath = "/\(token)"
        guard path == sessionPath || path == sessionPath + "/download"
                || path == sessionPath + "/restore" else {
            respond(connection, status: "404 Not Found", text: "Not found.")
            return
        }
        if let origin = headerLines.first(where: { $0.lowercased().hasPrefix("origin:") }) {
            let source = origin.dropFirst("origin:".count).trimmingCharacters(in: .whitespaces)
            let host = transferURL.flatMap { URL(string: $0) }.flatMap { $0.host() }
            let port = listener?.port?.rawValue
            if let host, let port, source != "http://\(host):\(port)" {
                respond(connection, status: "403 Forbidden", text: "Untrusted origin.")
                return
            }
        }

        switch (method, path) {
        case ("GET", sessionPath):
            respond(connection, status: "200 OK", contentType: "text/html; charset=utf-8",
                    body: Data(Self.portalHTML.utf8))
        case ("GET", sessionPath + "/download"):
            do {
                let backup = try DreamCASTLocalSettingsBackup.exportSettings()
                respond(connection, status: "200 OK", contentType: "application/json",
                        body: backup, attachment: true)
            } catch {
                respond(connection, status: "500 Internal Server Error", text: "Could not prepare settings file.")
            }
        case ("POST", sessionPath + "/restore"):
            guard !hasPendingRestore else {
                respond(connection, status: "409 Conflict", text: "Confirm or cancel the pending restore on Apple TV.")
                return
            }
            let body = buffer.subdata(in: marker.upperBound..<needed)
            do {
                let count = try DreamCASTLocalSettingsBackup.inspectRestore(body)
                pendingRestoreData = body
                pendingSettingsCount = count
                hasPendingRestore = true
                respond(connection, status: "202 Accepted",
                        text: "File received. Confirm Restore on your Apple TV. No settings have changed yet.")
            } catch {
                respond(connection, status: "400 Bad Request", text: "Invalid DreamCAST TV settings file.")
            }
        default:
            respond(connection, status: "405 Method Not Allowed", text: "Method not allowed.")
        }
    }

    private func respond(_ connection: NWConnection, status: String, text: String) {
        respond(connection, status: status, contentType: "text/plain; charset=utf-8",
                body: Data(text.utf8))
    }

    private func respond(
        _ connection: NWConnection,
        status: String,
        contentType: String,
        body: Data,
        attachment: Bool = false
    ) {
        let id = ObjectIdentifier(connection)
        requests.removeValue(forKey: id)
        let disposition = attachment
            ? "Content-Disposition: attachment; filename=\"DreamCAST-TV-settings.json\"\r\n" : ""
        let headers = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\n"
            + disposition
            + "Connection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\n"
            + "Content-Security-Policy: default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'\r\n\r\n"
        var payload = Data(headers.utf8)
        payload.append(body)
        connection.send(content: payload, completion: .contentProcessed { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.connections.removeValue(forKey: id)
                connection.cancel()
            }
        })
    }

    private static let portalHTML = """
    <!doctype html><html lang="en"><head><meta name="viewport" content="width=device-width,initial-scale=1">
    <meta charset="utf-8"><title>DreamCAST TV | Local Backup</title>
    <style>body{font:17px system-ui;background:#0c1323;color:#fff;max-width:650px;margin:30px auto;padding:20px}
    section{background:#202b41;border-radius:14px;padding:24px;margin:16px 0}
    a,button{display:inline-block;background:#12c8c8;color:#07131c;padding:13px 18px;border-radius:9px;
    text-decoration:none;font:600 17px system-ui;border:0;cursor:pointer}
    p{line-height:1.5}input{font:16px system-ui;max-width:100%;margin-bottom:15px}
    #message{white-space:pre-wrap}</style></head>
    <body><h1>DreamCAST TV</h1><p>Local settings backup &amp; restore</p>
    <section><h2>Back Up Settings</h2><p>Save the JSON file to this phone or computer.</p>
    <a href="./download" download>Download Settings</a></section>
    <section><h2>Restore Settings</h2>
    <p>Choose a DreamCAST TV settings JSON file. You must approve it on the TV.</p>
    <input id="file" type="file" accept=".json,application/json"><br>
    <button id="restore" type="button">Send to Apple TV</button><p id="message"></p></section>
    <p>Passwords, account keys, playlists and watch history are not in this file.
    Close this page and stop the transfer on Apple TV when finished.</p>
    <script>
    document.getElementById('restore').onclick=async()=>{
      const file=document.getElementById('file').files[0];
      const message=document.getElementById('message');
      if(!file){message.textContent='Choose a JSON file first.';return;}
      if(file.size>8000000){message.textContent='File exceeds 8 MB.';return;}
      message.textContent='Sending...';
      try{
        const response=await fetch(location.pathname+'/restore',
          {method:'POST',headers:{'Content-Type':'application/json'},body:await file.arrayBuffer()});
        message.textContent=await response.text();
      }catch(e){message.textContent='Could not connect to Apple TV.';}
    };
    </script></body></html>
    """

    /// The TV and phone must use the same local network. Never show loopback
    /// or link-local addresses to the user.
    private static func localIPv4Address() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return nil }
        defer { freeifaddrs(first) }
        var matches: [(priority: Int, address: String)] = []
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let item = pointer {
            let iface = item.pointee
            defer { pointer = iface.ifa_next }
            guard let address = iface.ifa_addr,
                  address.pointee.sa_family == sa_family_t(AF_INET),
                  iface.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                  iface.ifa_flags & UInt32(IFF_UP) != 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len),
                              &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: host)
            guard !ip.hasPrefix("169.254.") else { continue }
            let name = String(cString: iface.ifa_name)
            let priority = name == "en0" ? 0 : name == "en1" ? 1 : 2
            matches.append((priority, ip))
        }
        return matches.sorted { $0.priority < $1.priority }.first?.address
    }
}

struct TVLocalBackupSettingsPane: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var transfer = DreamCASTTVLocalTransfer()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            TVSettingsSectionLabel("Local Backup & Restore")
            Text("Back up DreamCAST TV settings to a JSON file. Restore from the same file on another device.")
                .foregroundStyle(.secondary)
                .font(.title3)
            Text("Passwords, account keys, playlists and watched history are not saved. Existing media stays unchanged.")
                .foregroundStyle(.secondary)
                .font(.subheadline)
            if transfer.transferURL == nil {
                Button {
                    transfer.start()
                } label: {
                    Label("Start Local Backup & Restore", systemImage: "square.and.arrow.up.on.square")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(TVSettingsRowButtonStyle())
            } else {
                HStack(alignment: .top, spacing: 32) {
                    QRCodeView(string: transfer.transferURL ?? "")
                        .frame(width: 225, height: 225)
                        .padding(16)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Open on a phone or computer on the same network:")
                            .font(.headline)
                        Text(verbatim: transfer.transferURL ?? "")
                            .font(.system(size: 22, weight: .semibold, design: .monospaced))
                            .textSelection(.enabled)
                        Text("Use the web page to download or upload your settings JSON.")
                            .foregroundStyle(.secondary)
                    }
                }
                Button("Stop Local Transfer", systemImage: "stop.circle") {
                    transfer.stop()
                }
                .buttonStyle(TVSettingsRowButtonStyle())
            }
            Text(verbatim: transfer.statusText)
                .foregroundStyle(.secondary)
            if let resultText = transfer.resultText {
                Text(verbatim: resultText)
                    .foregroundStyle(.primary)
                    .font(.title3)
            }
            Text("Transfers stop when you leave this page, or after 10 minutes. Use a trusted private network.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .focusSection()
        .onDisappear { transfer.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { transfer.stop() }
        }
        .alert("Restore Settings?", isPresented: Binding(
            get: { transfer.hasPendingRestore },
            set: { if !$0 && transfer.hasPendingRestore { transfer.dismissPendingRestore() } }
        )) {
            Button("Restore", role: .destructive) { transfer.approvePendingRestore() }
            Button("Cancel", role: .cancel) { transfer.dismissPendingRestore() }
        } message: {
            Text("Restore \(transfer.pendingSettingsCount) settings from this file? Your existing media stays unchanged. Restart the app afterward.")
        }
    }
}
#endif
