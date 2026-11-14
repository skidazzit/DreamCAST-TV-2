//
//  KSHostedPlayerSurface.swift
//  Lume
//
//  Renders a KSPlayer session handed between the tvOS Guide preview and full
//  screen (see `PreviewPlayerHandle`) through a Lume-owned container instead of
//  `KSVideoPlayer`, whose `dismantleUIView` resets the player unconditionally —
//  which would kill a stream full screen has just adopted — and which would
//  return the running player view as its own root, still pinned by the
//  preview's Auto Layout.
//

#if os(tvOS)
    import KSPlayer
    import SwiftUI
    import UIKit

    struct KSHostedPlayerSurface: UIViewRepresentable {
        enum Mode {
            /// The Guide preview: leaves the player running when dismantled,
            /// and stops touching it once `handle` no longer belongs to the
            /// preview.
            case preview(PreviewPlayerHandle)
            /// Full screen's surface for an adopted session: follows URL changes
            /// (in-player channel surfing) the way `KSVideoPlayer` does, and
            /// resets the player when dismantled.
            case adopted(PreviewPlayerHandle?)

            var resetsOnDismantle: Bool {
                if case .adopted = self { true } else { false }
            }
        }

        final class Host {
            let player: KSVideoPlayer.Coordinator
            let resetsOnDismantle: Bool
            let returnHandle: PreviewPlayerHandle?
            // Hold the exact KSPlayer render UIView while full screen borrows
            // it. Calling makeView again after Back may reinitialize playback.
            var retainedView: UIView?

            init(player: KSVideoPlayer.Coordinator, resetsOnDismantle: Bool, returnHandle: PreviewPlayerHandle?) {
                self.player = player
                self.resetsOnDismantle = resetsOnDismantle
                self.returnHandle = returnHandle
            }
        }

        let coordinator: KSVideoPlayer.Coordinator
        let url: URL
        let options: KSOptions
        let mode: Mode
        /// A changing value makes SwiftUI update the existing UIKit host on
        /// return from full screen, without replacing the decoder or view.
        var returnGeneration: Int = 0
        let onStateChanged: (KSPlayerLayer, KSPlayerState) -> Void
        var onPlay: ((TimeInterval, TimeInterval) -> Void)?

        func makeCoordinator() -> Host {
            let returnHandle: PreviewPlayerHandle?
            if case let .adopted(handle) = mode { returnHandle = handle } else { returnHandle = nil }
            return Host(player: coordinator, resetsOnDismantle: mode.resetsOnDismantle, returnHandle: returnHandle)
        }

        func makeUIView(context: Context) -> UIView {
            let container = UIView()
            container.backgroundColor = .black
            container.clipsToBounds = true
            // SwiftUI may recreate the preview host while the full-screen
            // cover owns the video. Never ask KSPlayer for a view in that
            // state: doing so can steal the render surface from full screen.
            if case let .preview(handle) = mode,
               handle.owner == .fullScreen || handle.owner == .returning {
                return container
            }

            attachCallbacks()
            let surface = coordinator.makeView(url: url, options: options)
            context.coordinator.retainedView = surface
            switch mode {
            case let .preview(handle):
                handle.activeKSRenderView = surface
            case let .adopted(handle):
                if handle?.owner != .released { handle?.activeKSRenderView = surface }
            }
            host(surface, in: container)
            return container
        }

        func updateUIView(_ container: UIView, context: Context) {
            switch mode {
            case let .preview(handle):
                // Never re-adds the player view: after a handoff it lives in
                // full screen's hierarchy, and pulling it back would blank
                // full screen.
                guard handle.owner == .preview else { return }
                _ = returnGeneration // Explicitly consume the handoff revision.
                attachCallbacks()
                // A prior full-screen view may leave the preview container
                // with a non-video subview during UIKit dismissal. Checking
                // just "subviews.isEmpty" can then leave a BLACK preview even
                // though the same decoder is still playing.
                //
                // Compare the *actual* retained render view to its parent.
                // Reattach that exact view after handoff: do not call
                // makeView again on a running stream.
                // The fullscreen host may have received a newer UIView from
                // the same decoder. Prefer that actual, most recent render
                // surface instead of the preview host's old black one.
                if let retained = handle.activeKSRenderView ?? context.coordinator.retainedView {
                    context.coordinator.retainedView = retained
                    if retained.superview !== container {
                        host(retained, in: container)
                        container.setNeedsLayout()
                        container.layoutIfNeeded()
                    }
                    handle.activeKSRenderView = retained
                } else {
                    let surface = coordinator.makeView(url: url, options: options)
                    context.coordinator.retainedView = surface
                    handle.activeKSRenderView = surface
                    host(surface, in: container)
                }
            case let .adopted(handle):
                attachCallbacks()
                guard coordinator.playerLayer?.url != url else { return }
                let surface = coordinator.makeView(url: url, options: options)
                context.coordinator.retainedView = surface
                if handle?.owner != .released { handle?.activeKSRenderView = surface }
                host(surface, in: container)
            }
        }

        static func dismantleUIView(_: UIView, coordinator host: Host) {
            // UIKit can dismantle the fullscreen UIView before the parent
            // receives onDisappear. The guide's handle still owns this exact
            // coordinator, even while owner == .fullScreen. Never reset it.
            if host.resetsOnDismantle,
               host.returnHandle == nil || host.returnHandle?.owner == .released {
                host.player.resetPlayer()
            }
        }

        private func attachCallbacks() {
            coordinator.onStateChanged = onStateChanged
            if let onPlay {
                coordinator.onPlay = onPlay
            }
        }

        private func host(_ playerView: UIView, in container: UIView) {
            guard playerView.superview !== container else { return }
            container.subviews.forEach { $0.removeFromSuperview() }
            playerView.removeFromSuperview()
            playerView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(playerView)
            NSLayoutConstraint.activate([
                playerView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                playerView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                playerView.topAnchor.constraint(equalTo: container.topAnchor),
                playerView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        }
    }
#endif
