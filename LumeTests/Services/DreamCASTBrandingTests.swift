import Foundation
import Testing
@testable import Lume

struct DreamCASTBrandingTests {
    @Test func playerSettingsUseDreamCASTName() {
        #expect(PlayerEngineKind.lumeEngine.displayName == "DreamCAST TV Engine")
    }

    @Test func supportLinksLeadToTheFork() {
        #expect(SupportInfo.website == "https://github.com/skidazzit/DreamCAST-TV-2")
        #expect(SupportInfo.issuesURL?.absoluteString == "https://github.com/skidazzit/DreamCAST-TV-2/issues")
    }

    @Test func forkDoesNotSendReviewsToUpstreamListing() {
        #expect(SupportInfo.appStoreReviewURL == nil)
        #expect(SupportInfo.emailURL == nil)
        #expect(SupportInfo.discordURL == nil)
    }

    @Test func upstreamCodeStillReceivesCredit() {
        #expect(CreditsInfo.sourceCodeURL?.absoluteString == "https://github.com/skidazzit/DreamCAST-TV-2")
        #expect(CreditsInfo.upstreamSourceURL?.absoluteString == "https://github.com/bilipp/Lume")
    }
}
