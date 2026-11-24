import AVFoundation
import PlayerCore

final class AVPlaybackEngine: PlaybackEngine, VideoFrameSource {
    private let player = AVPlayer()
    private(set) var output: AVPlayerItemVideoOutput?
    var onEvent: ((PlaybackEvent) -> Void)?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private var itemObserver: NSKeyValueObservation?

    init() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 4), queue: .main) { [weak self] _ in
            guard let self, let item = self.player.currentItem else { return }
            self.onEvent?(.timeline(position: item.currentTime().seconds, duration: item.duration.seconds))
        }
        statusObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            DispatchQueue.main.async { self?.onEvent?(.playing(player.timeControlStatus != .paused)) }
        }
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    func load(_ url: URL) {
        let item = AVPlayerItem(url: url)
        let frames = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ])
        item.add(frames)
        itemObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self, self.player.currentItem === item, item.status == .failed else { return }
                self.onEvent?(.failed(item.error?.localizedDescription ?? "영상을 열 수 없습니다."))
            }
        }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self, weak item] _ in
            guard let self, self.player.currentItem === item else { return }
            self.onEvent?(.ended)
        }
        output = frames
        player.replaceCurrentItem(with: item)
    }

    func resume() {
        if let item = player.currentItem, item.currentTime() >= item.duration { player.seek(to: .zero) }
        player.play()
    }

    func pause() { player.pause() }

    func seek(to seconds: Double, completion: @escaping () -> Void) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            DispatchQueue.main.async { completion() }
        }
    }

    func close() {
        player.pause()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        itemObserver = nil
        player.replaceCurrentItem(with: nil)
        output = nil
    }
}
