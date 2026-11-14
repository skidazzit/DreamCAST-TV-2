@testable import Lume
import Testing

struct EPGGuideEntryTests {
    private let ids = ["a", "b", "c", "d"]

    @Test func `lands on the previewed channel at its remembered row`() {
        #expect(EPGGuideEntry.landingRow(previewedStreamID: "c", previewedRowIndex: 2, rowIDs: ids, topVisibleRow: 0) == 2)
    }

    @Test func `finds the previewed channel when its row moved`() {
        #expect(EPGGuideEntry.landingRow(previewedStreamID: "d", previewedRowIndex: 1, rowIDs: ids, topVisibleRow: 0) == 3)
        #expect(EPGGuideEntry.landingRow(previewedStreamID: "b", previewedRowIndex: 9, rowIDs: ids, topVisibleRow: 0) == 1)
        #expect(EPGGuideEntry.landingRow(previewedStreamID: "a", previewedRowIndex: nil, rowIDs: ids, topVisibleRow: 3) == 0)
    }

    @Test func `falls back to the top visible row without a preview`() {
        #expect(EPGGuideEntry.landingRow(previewedStreamID: nil, previewedRowIndex: nil, rowIDs: ids, topVisibleRow: 2) == 2)
    }

    @Test func `falls back to the top visible row when the previewed channel is gone`() {
        #expect(EPGGuideEntry.landingRow(previewedStreamID: "z", previewedRowIndex: 1, rowIDs: ids, topVisibleRow: 1) == 1)
    }

    @Test func `clamps the fallback row into the guide`() {
        #expect(EPGGuideEntry.landingRow(previewedStreamID: nil, previewedRowIndex: nil, rowIDs: ids, topVisibleRow: 12) == 3)
        #expect(EPGGuideEntry.landingRow(previewedStreamID: nil, previewedRowIndex: nil, rowIDs: ids, topVisibleRow: -1) == 0)
    }

    @Test func `an empty guide has nowhere to land`() {
        #expect(EPGGuideEntry.landingRow(previewedStreamID: "a", previewedRowIndex: 0, rowIDs: [], topVisibleRow: 0) == nil)
    }
}

struct GuidePreviewRetunePolicyTests {
    private let newGroup = ["sports-1", "sports-2"]

    @Test func `opening Live TV selects the last watched channel if visible`() {
        #expect(GuidePreviewRetunePolicy.rowIndex(
            preferredID: "sports-2", currentID: nil, adoptedID: nil,
            rowIDs: newGroup
        ) == 1)
    }

    @Test func `switching a TV group never starts its first channel`() {
        #expect(GuidePreviewRetunePolicy.rowIndex(
            preferredID: "news-playing", currentID: "news-playing",
            adoptedID: "news-playing", rowIDs: newGroup
        ) == nil)
    }

    @Test func `switching groups even with matching preview keeps the current decoder`() {
        #expect(GuidePreviewRetunePolicy.rowIndex(
            preferredID: "sports-1", currentID: "sports-1",
            adoptedID: "sports-1", rowIDs: newGroup
        ) == nil)
    }

    @Test func `full screen handoff may update its returned channel`() {
        #expect(GuidePreviewRetunePolicy.rowIndex(
            preferredID: "sports-2", currentID: "news-playing",
            adoptedID: "sports-2", rowIDs: newGroup
        ) == 1)
    }

    @Test func `an empty channel group cannot retune the player`() {
        #expect(GuidePreviewRetunePolicy.rowIndex(
            preferredID: "news-playing", currentID: "news-playing",
            adoptedID: "news-playing", rowIDs: []
        ) == nil)
    }
}
