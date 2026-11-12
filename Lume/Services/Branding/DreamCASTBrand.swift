import SwiftUI

/// User-facing names only. Keep Lume service identifiers and purchase IDs
/// untouched so existing data, account links and entitlements still work.
enum DreamCASTBrand {
    static var proTitle: LocalizedStringKey {
        #if os(iOS)
            "DreamCAST TV Pro"
        #else
            "Lume Pro"
        #endif
    }
}
