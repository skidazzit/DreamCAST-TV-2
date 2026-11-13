//
//  SupportInfo.swift
//  Lume
//
//  Canonical support / contact links, shared by the iOS Settings list (tappable
//  Link rows) and the tvOS About pane (read-only text plus a scannable QR code,
//  since Apple TV can't open a URL itself). One source of truth so the two
//  surfaces can never drift.
//

import Foundation

nonisolated enum SupportInfo {
    static let website = "https://github.com/skidazzit/DreamCAST-TV-2"
    static let issues = "https://github.com/skidazzit/DreamCAST-TV-2/issues"
    static let email = "" // No DreamCAST TV support email is configured.
    static let discord = "" // Do not route fork users to the upstream community.

    /// App Store listing, and the deep link that opens straight to the
    /// write-a-review composer (`?action=write-review`).
    static let appStore = "" // Original Lume App Store listing is not this fork.
    static let appStoreReview = ""

    /// How to install and run a LumeRecorder server, linked from the Recording
    /// Server settings.
    static let recorderGuide = "https://github.com/bilipp/LumeRecorder"

    /// Scheme-stripped forms for compact on-screen display.
    static let websiteDisplay = "github.com/skidazzit/DreamCAST-TV-2"
    static let discordDisplay = ""
    static let appStoreDisplay = ""
    static let recorderGuideDisplay = "Recorder setup guide"

    static var websiteURL: URL? {
        URL(string: website)
    }

    static var issuesURL: URL? { URL(string: issues) }

    static var recorderGuideURL: URL? {
        URL(string: recorderGuide)
    }

    static var discordURL: URL? {
        discord.isEmpty ? nil : URL(string: discord)
    }

    static var emailURL: URL? {
        email.isEmpty ? nil : URL(string: "mailto:\(email)")
    }

    static var appStoreReviewURL: URL? {
        appStoreReview.isEmpty ? nil : URL(string: appStoreReview)
    }

    /// Marketing version (`CFBundleShortVersionString`, e.g. "2.1.0"), sourced
    /// from the build's `MARKETING_VERSION` rather than a hardcoded string so
    /// the iOS and tvOS About panes always reflect the shipped version.
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}
