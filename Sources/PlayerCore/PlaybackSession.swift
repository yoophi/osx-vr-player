import Foundation

public enum MediaKind { case directory, movie, unsupported }

public protocol MovieLibrary {
    func kind(of url: URL) throws -> MediaKind
    func movies(in folder: URL) throws -> [URL]
}

public enum PlaybackEvent {
    case timeline(position: Double, duration: Double)
    case playing(Bool)
    case ended
    case failed(String)
}

public protocol PlaybackEngine: AnyObject {
    var onEvent: ((PlaybackEvent) -> Void)? { get set }
    func load(_ url: URL)
    func resume()
    func pause()
    func seek(to seconds: Double, completion: @escaping () -> Void)
    func close()
}

public struct PlaybackState {
    public fileprivate(set) var playlist: [URL] = []
    public fileprivate(set) var currentURL: URL?
    public fileprivate(set) var position = 0.0
    public fileprivate(set) var duration = 0.0
    public fileprivate(set) var playing = false
    public fileprivate(set) var stopped = false
    public var error: String?

    public func neighbor(_ offset: Int) -> URL? {
        guard let currentURL, let index = playlist.firstIndex(of: currentURL),
              playlist.indices.contains(index + offset) else { return nil }
        return playlist[index + offset]
    }
}

/// Commands and engine events are delivered on the application's main thread.
public final class PlaybackSession {
    public var onChange: (() -> Void)?
    public private(set) var state = PlaybackState() {
        didSet { onChange?() }
    }
    private let engine: PlaybackEngine
    private let library: MovieLibrary
    private var pendingSeek: UUID?

    public init(engine: PlaybackEngine, library: MovieLibrary) {
        self.engine = engine
        self.library = library
        engine.onEvent = { [weak self] event in self?.handle(event) }
    }

    public func open(_ input: URL) {
        let url = input.standardizedFileURL
        do {
            switch try library.kind(of: url) {
            case .directory:
                let movies = try library.movies(in: url)
                guard let first = movies.first else {
                    state.error = "폴더에 동영상 파일이 없습니다."
                    return
                }
                state.playlist = movies
                play(first)
            case .movie:
                state.playlist = Playlist.related(to: url, library: library)
                play(url)
            case .unsupported:
                state.error = "동영상 파일이나 폴더를 선택하세요."
            }
        } catch { state.error = error.localizedDescription }
    }

    public func play(_ url: URL) {
        guard state.playlist.contains(url) else { return }
        pendingSeek = nil
        state.stopped = false
        state.currentURL = url
        state.position = 0
        state.duration = 0
        engine.load(url)
        engine.resume()
    }

    public func seek(to seconds: Double) {
        guard state.duration > 0, seconds.isFinite else { return }
        state.stopped = false
        let target = max(0, min(seconds, state.duration))
        let request = UUID()
        pendingSeek = request
        state.position = target
        engine.seek(to: target) { [weak self] in
            if self?.pendingSeek == request { self?.pendingSeek = nil }
        }
    }

    public func toggle() {
        guard state.currentURL != nil else { return }
        state.stopped = false
        if state.playing { engine.pause() } else { engine.resume() }
    }

    public func stop() {
        engine.pause()
        seek(to: 0)
        state.stopped = true
    }

    public func close() {
        pendingSeek = nil
        engine.close()
        state = PlaybackState()
    }

    public func setError(_ message: String?) { state.error = message }

    private func handle(_ event: PlaybackEvent) {
        guard state.currentURL != nil else { return }
        switch event {
        case let .timeline(position, duration):
            if duration.isFinite && duration > 0 { state.duration = duration }
            if pendingSeek == nil && position.isFinite {
                state.position = max(0, min(position, state.duration))
            }
        case let .playing(playing): state.playing = playing
        case .ended:
            if let next = state.neighbor(1) { play(next) }
        case let .failed(message): state.error = message
        }
    }
}
