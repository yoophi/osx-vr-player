import SwiftUI
import PlayerCore

final class PlayerPresentation: ObservableObject {
    let engine = AVPlaybackEngine()
    let session: PlaybackSession

    init() {
        session = PlaybackSession(engine: engine, library: FileMovieLibrary())
        session.onChange = { [weak self] in self?.objectWillChange.send() }
    }
}

@main
struct VRPlayerApp: App {
    @StateObject private var presentation = PlayerPresentation()
    init() { NSApplication.shared.setActivationPolicy(.regular) }
    var body: some Scene {
        Window("VR180 Player", id: "player") { PlayerScreen(presentation: presentation) }
    }
}
