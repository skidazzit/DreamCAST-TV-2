import Foundation
import Testing
@testable import Lume

#if os(tvOS)
struct DreamCASTLocalBackupTests {
    @Test func archiveMatchesTheIOSVersionOneFormat() throws {
        let data = try DreamCASTLocalSettingsBackup.exportSettings()
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(root["formatVersion"] as? Int == 1)
        #expect(root["preferences"] is [String: Any])
        #expect(try DreamCASTLocalSettingsBackup.inspectRestore(data) >= 0)
    }

    @Test func exportSkipsTokensAndSyncAccountSettings() throws {
        let normal = "dreamcast.backup.test.pref"
        let secret = "dreamcast.backup.test.apiKey"
        let sync = "lumecloud.deviceID"
        let defaults = UserDefaults.standard
        let oldNormal = defaults.object(forKey: normal)
        let oldSecret = defaults.object(forKey: secret)
        let oldSync = defaults.object(forKey: sync)
        defer {
            if let oldNormal { defaults.set(oldNormal, forKey: normal) }
            else { defaults.removeObject(forKey: normal) }
            if let oldSecret { defaults.set(oldSecret, forKey: secret) }
            else { defaults.removeObject(forKey: secret) }
            if let oldSync { defaults.set(oldSync, forKey: sync) }
            else { defaults.removeObject(forKey: sync) }
        }
        defaults.set(true, forKey: normal)
        defaults.set("do-not-export", forKey: secret)
        defaults.set("do-not-export", forKey: sync)
        let backup = try DreamCASTLocalSettingsBackup.exportSettings()
        let root = try #require(JSONSerialization.jsonObject(with: backup) as? [String: Any])
        let preferences = try #require(root["preferences"] as? [String: Any])
        #expect(preferences[normal] != nil)
        #expect(preferences[secret] == nil)
        #expect(preferences[sync] == nil)
    }

    @Test func rejectsInvalidBackupBeforeChangingAnything() throws {
        let malformed = Data(#"{"formatVersion":2,"createdAt":0,"preferences":{}}"#.utf8)
        #expect(throws: Error.self) {
            _ = try DreamCASTLocalSettingsBackup.inspectRestore(malformed)
        }
        let tooLarge = Data(repeating: 0, count: DreamCASTLocalSettingsBackup.maxBytes + 1)
        #expect(throws: Error.self) {
            _ = try DreamCASTLocalSettingsBackup.inspectRestore(tooLarge)
        }
    }
}
#endif
