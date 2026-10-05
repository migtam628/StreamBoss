import AVKit
import SwiftUI

/// Native AVPlayerViewController: Siri Remote transport controls, audio and
/// subtitle menus come for free. AVPlayer plays HLS and MP4; MKV and raw
/// MPEG-TS are not supported by Apple's stack.
struct PlayerView: UIViewControllerRepresentable {
    @EnvironmentObject var model: AppModel
    let item: MediaItem

    func makeCoordinator() -> Coordinator { Coordinator(model: model, item: item) }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        guard let s = item.url, let url = URL(string: s) else { return vc }
        let player = AVPlayer(url: url)
        let start = model.resume(for: item.key)
        if item.kind != .live, start > 0 {
            player.seek(to: CMTime(seconds: start, preferredTimescale: 600))
        }
        context.coordinator.attach(player)
        vc.player = player
        player.play()
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ vc: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.finish()
        vc.player?.pause()
    }

    @MainActor
    final class Coordinator {
        let model: AppModel
        let item: MediaItem
        private var player: AVPlayer?
        private var observer: Any?

        init(model: AppModel, item: MediaItem) {
            self.model = model
            self.item = item
        }

        func attach(_ p: AVPlayer) {
            player = p
            observer = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 10, preferredTimescale: 1), queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.save() }
            }
        }

        private func save() {
            guard let p = player, let d = p.currentItem?.duration.seconds, d.isFinite else { return }
            model.save(position: p.currentTime().seconds, duration: d, key: item.key, live: item.kind == .live)
        }

        func finish() {
            save()
            if let o = observer { player?.removeTimeObserver(o) }
            observer = nil
        }
    }
}
