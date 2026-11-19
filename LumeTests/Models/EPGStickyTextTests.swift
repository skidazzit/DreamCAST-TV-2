import CoreGraphics
import Foundation
@testable import Lume
import Testing

struct EPGStickyTextTests {
    @Test func `a fully visible block does not shift its text`() {
        #expect(EPGStickyText.shift(blockMinX: 0, blockWidth: 180, inset: 10) == 0)
        #expect(EPGStickyText.shift(blockMinX: 240, blockWidth: 180, inset: 10) == 0)
    }

    @Test func `a block scrolled past the leading edge shifts by the hidden amount`() {
        #expect(EPGStickyText.shift(blockMinX: -40, blockWidth: 180, inset: 10) == 40)
    }

    @Test func `the shift is capped inside the block`() {
        // 180 wide, 10 inset either side -> the text never travels past 160.
        #expect(EPGStickyText.shift(blockMinX: -400, blockWidth: 180, inset: 10) == 160)
    }

    @Test func `a two-hour programme keeps its title visible after its start scrolls out`() {
        // 5–7 PM programme; guide is showing 6 PM onward, with 4 points/minute.
        // The original 5 PM title is 240 points left of the viewport.
        let width: CGFloat = 120 * 4
        #expect(EPGStickyText.shift(
            blockMinX: -240, blockWidth: width, inset: 12
        ) == 240)
    }

    @Test func `sticky title follows a long event until its right edge`() {
        // A multi-hour event can extend far beyond the visible timeline.
        #expect(EPGStickyText.shift(
            blockMinX: -960, blockWidth: 1600, inset: 14
        ) == 960)
        // Near its end, the cap keeps the text within the same event tile.
        #expect(EPGStickyText.shift(
            blockMinX: -1599, blockWidth: 1600, inset: 14
        ) == 1572)
    }

    @Test func `a block narrower than its own insets never shifts`() {
        #expect(EPGStickyText.shift(blockMinX: -40, blockWidth: 12, inset: 10) == 0)
    }
}
