//
//  EPGGrid.swift
//  DreamCAST TV
//
//  The Guide is a read-only window onto the current EPG time.
//  Only the channel-name column scrolls vertically. No swipes or remote
//  focus moves in programme cells can move the time ruler.
//

import SwiftUI

/// A fixed, clipped programme surface. The channel rail sends vertical
/// scroll requests and the clock keeps the displayed time parked near now.
/// The same offset is published to the ruler and frozen channel names.
struct EPGGrid: View, Equatable {
    let rows: [EPGChannelRow]
    let timeline: EPGTimeline
    let metrics: EPGMetrics
    let now: Date
    let sync: EPGScrollSync
    let dataVersion: Int
    let nowTarget: CGFloat
    let initialRowOffset: CGFloat
    let scrollRequest: EPGScrollRequest?
    let virtualFocus: EPGVirtualFocus?
    let onPlay: (EPGChannelRow, EPGProgramCell) -> Void
    let onWatchFromStart: (EPGChannelRow, EPGProgramCell) -> Void
    let onShowDetails: (EPGChannelRow, EPGProgramCell) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.dataVersion == rhs.dataVersion
            && lhs.rows.count == rhs.rows.count
            && lhs.nowTarget == rhs.nowTarget
            && lhs.initialRowOffset == rhs.initialRowOffset
            && lhs.scrollRequest == rhs.scrollRequest
            && lhs.virtualFocus == rhs.virtualFocus
            && lhs.timeline == rhs.timeline
    }

    @State private var parkedOffset = CGPoint.zero
    @State private var viewport = CGSize.zero
    @State private var didMount = false

    var body: some View {
        GeometryReader { geometry in
            EPGRows(
                rows: rows,
                timeline: timeline,
                metrics: metrics,
                now: now,
                sync: sync,
                dataVersion: dataVersion,
                virtualFocus: virtualFocus,
                onPlay: onPlay,
                onWatchFromStart: onWatchFromStart,
                onShowDetails: onShowDetails
            )
            .equatable()
            // The content stays in one render layer. No ScrollView lives in
            // this pane: only channel-name gestures / focus move the rows.
            .offset(x: -parkedOffset.x, y: -parkedOffset.y)
            .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: .topLeading
            )
            .clipped()
            .allowsHitTesting(false)
            .onAppear {
                updateViewport(geometry.size)
                guard !didMount else { return }
                didMount = true
                park(x: currentTimeOffset(), y: initialRowOffset, animated: false)
            }
            .onChange(of: geometry.size) { _, size in
                updateViewport(size)
            }
        }
        .onChange(of: initialRowOffset) { _, rowOffset in
            guard didMount else { return }
            park(x: currentTimeOffset(), y: rowOffset, animated: false)
        }
        .onChange(of: scrollRequest) { _, request in
            guard let request else { return }
            // Ignore requests to pan time. Only channel-rail Y survives.
            park(x: currentTimeOffset(), y: request.point.y, animated: request.animated)
        }
        .task {
            // Keep "now" in the same part of the ruler during long viewing
            // sessions. This never changes the current channel or playback.
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    break
                }
                guard !Task.isCancelled, didMount else { break }
                park(x: currentTimeOffset(), y: parkedOffset.y, animated: false)
            }
        }
    }

    /// Parks the current time a few minutes inside the leading edge.
    /// Unlike half-hour snapping, this keeps the NOW indicator steady.
    private func currentTimeOffset() -> CGFloat {
        timeline.x(
            for: Date().addingTimeInterval(-Double(metrics.nowLeadInMinutes) * 60)
        )
    }

    private func updateViewport(_ size: CGSize) {
        guard size.width > 0, size.height > 0,
              abs(size.width - viewport.width) > 1
              || abs(size.height - viewport.height) > 1 else { return }
        viewport = size
        park(
            x: didMount ? currentTimeOffset() : nowTarget,
            y: didMount ? parkedOffset.y : initialRowOffset,
            animated: false
        )
    }

    private func park(x: CGFloat, y: CGFloat, animated: Bool) {
        guard viewport.width > 0, viewport.height > 0 else { return }
        let contentHeight = metrics.contentHeight(rowCount: rows.count)
        let next = CGPoint(
            x: max(0, min(x, max(0, timeline.totalWidth - viewport.width))),
            y: max(0, min(y, max(0, contentHeight - viewport.height)))
        )
        // The grid, ruler and channel-name column must always use the
        // same offset. Publication is quantized by realization windows.
        let publish = {
            parkedOffset = next
            sync.offset = next
            sync.viewport = viewport
            sync.mirror = next
            let window = EPGRealizeWindow.around(
                offset: next.x,
                viewport: viewport.width,
                blockLength: 30 * metrics.pointsPerMinute
            )
            if sync.window != window { sync.window = window }
            let rowWindow = EPGRealizeWindow.around(
                offset: next.y,
                viewport: viewport.height,
                blockLength: 2 * (metrics.rowHeight + metrics.rowSpacing)
            )
            if sync.rowWindow != rowWindow { sync.rowWindow = rowWindow }
        }
        if animated {
            withAnimation(.easeOut(duration: 0.25), publish)
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction, publish)
        }
    }
}
