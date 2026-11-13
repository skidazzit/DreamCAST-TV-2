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

#if os(tvOS) || os(iOS)
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
            attachCallbacks()
            let surface = coordinator.makeView(url: url, options: options)
            context.coordinator.retainedView = surface
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
                attachCallbacks()
                // SwiftUI calls updateUIView for unrelated state changes.
                // Do not call makeView again while this host already owns
                // the running surface. Only reclaim it after full screen
                // moved the video view out, leaving the preview host empty.
                if !container.subviews.isEmpty { return }
                // Reparent the *same* render view and decoder. A fresh
                // makeView on return can restart KSPlayer's pipeline and
                // produce hardware-decoder errors on some live streams.
                if let retained = context.coordinator.retainedView {
                    host(retained, in: container)
                } else {
                    let surface = coordinator.makeView(url: url, options: options)
                    context.coordinator.retainedView = surface
                    host(surface, in: container)
                }
            case .adopted:
                attachCallbacks()
                guard coordinator.playerLayer?.url != url else { return }
                let surface = coordinator.makeView(url: url, options: options)
                context.coordinator.retainedView = surface
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
