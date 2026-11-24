import XCTest
import PlayerCore

private final class TestEngine: PlaybackEngine {
    var onEvent: ((PlaybackEvent) -> Void)?
    var loaded: URL?
    var target: Double?
    var completeSeek: (() -> Void)?
    func load(_ url: URL) { loaded = url }
    func resume() { onEvent?(.playing(true)) }
    func pause() { onEvent?(.playing(false)) }
    func close() { loaded = nil }
    func seek(to seconds: Double, completion: @escaping () -> Void) {
        target = seconds
        completeSeek = completion
    }
}

private struct TestLibrary: MovieLibrary {
    let folder = URL(fileURLWithPath: "/movies", isDirectory: true)
    var files: [URL] {
        ["Other.mp4", "Trip Part 1.mp4", "Trip Part 2.mp4"].map { folder.appendingPathComponent($0) }
    }
    func kind(of url: URL) throws -> MediaKind {
        if url == folder { return .directory }
        return files.contains(url) ? .movie : .unsupported
    }
    func movies(in folder: URL) throws -> [URL] { files }
}

final class PlaybackSessionTests: XCTestCase {
    private let engine = TestEngine()
    private let library = TestLibrary()

    func testFolderStartsFirstMovieAndAdvancesUntilLast() {
        let session = PlaybackSession(engine: engine, library: library)
        session.open(library.folder)
        XCTAssertEqual(session.state.playlist, library.files)
        XCTAssertNil(session.state.neighbor(-1))
        for file in library.files {
            XCTAssertEqual(engine.loaded, file)
            XCTAssertTrue(session.state.playing)
            engine.onEvent?(.ended)
        }
        XCTAssertEqual(engine.loaded, library.files.last)
        XCTAssertNil(session.state.neighbor(1))
    }

    func testOpeningRelatedMovieAndRejectingUnsupportedInput() {
        let session = PlaybackSession(engine: engine, library: library)
        session.open(library.files[2])
        XCTAssertEqual(session.state.playlist, Array(library.files.dropFirst()))
        XCTAssertEqual(session.state.currentURL, library.files[2])
        session.open(library.folder.appendingPathComponent("notes.txt"))
        XCTAssertNotNil(session.state.error)
        XCTAssertEqual(engine.loaded, library.files[2])
    }

    func testPendingSeeksStopAndClose() {
        let session = PlaybackSession(engine: engine, library: library)
        session.open(library.folder)
        engine.onEvent?(.timeline(position: 12, duration: 100))
        session.seek(to: 50)
        let staleCompletion = engine.completeSeek
        session.seek(to: 120)
        staleCompletion?()
        engine.onEvent?(.timeline(position: 50, duration: 100))
        XCTAssertEqual(session.state.position, 100)
        XCTAssertEqual(engine.target, 100)
        session.stop()
        XCTAssertEqual(engine.target, 0)
        XCTAssertTrue(session.state.stopped)
        XCTAssertFalse(session.state.playing)
        session.toggle()
        XCTAssertFalse(session.state.stopped)
        XCTAssertTrue(session.state.playing)
        session.close()
        engine.completeSeek?()
        engine.onEvent?(.ended)
        XCTAssertNil(engine.loaded)
        XCTAssertNil(session.state.currentURL)
        XCTAssertTrue(session.state.playlist.isEmpty)
        XCTAssertEqual(session.state.duration, 0)
    }
}
