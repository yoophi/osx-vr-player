import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

@main
struct VRPlayerApp: App {
    init() { NSApplication.shared.setActivationPolicy(.regular) }
    var body: some Scene {
        Window("VR180 Player", id: "player") { PlayerScreen() }
    }
}

final class Playback: ObservableObject {
    let player = AVPlayer()
    private(set) var output: AVPlayerItemVideoOutput?
    @Published var fileName = ""
    @Published var playing = false
    @Published var error: String?
    @Published private(set) var playlist: [URL] = []
    @Published private(set) var currentURL: URL?
    @Published private(set) var position = 0.0
    @Published private(set) var duration = 0.0
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var pendingSeek: UUID?
    private var observations: [NSKeyValueObservation] = []

    init() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 4), queue: .main) { [weak self] _ in
            guard let self, let item = self.player.currentItem else { return }
            let length = item.duration.seconds
            if length.isFinite && length > 0 { self.duration = length }
            let current = item.currentTime().seconds
            if self.pendingSeek == nil && current.isFinite { self.position = max(0, min(current, self.duration)) }
        }
        observations.append(player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            DispatchQueue.main.async { self?.playing = player.timeControlStatus != .paused }
        })
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    func open(_ input: URL) {
        let url = input.standardizedFileURL
        do {
            if try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                let files = try Playlist.movies(in: url)
                guard let first = files.first else {
                    error = "폴더에 동영상 파일이 없습니다."
                    return
                }
                playlist = files
                play(first)
            } else if Playlist.isMovie(url) {
                playlist = Playlist.related(to: url)
                play(url)
            } else {
                error = "동영상 파일이나 폴더를 선택하세요."
            }
        } catch { self.error = error.localizedDescription }
    }

    func seek(to seconds: Double) {
        guard duration > 0, seconds.isFinite else { return }
        let target = max(0, min(seconds, duration))
        let request = UUID()
        pendingSeek = request
        position = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            DispatchQueue.main.async {
                if self?.pendingSeek == request { self?.pendingSeek = nil }
            }
        }
    }

    func play(_ url: URL) {
        currentURL = url
        position = 0
        duration = 0
        pendingSeek = nil
        let item = AVPlayerItem(url: url)
        let frames = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ])
        item.add(frames)
        observations = Array(observations.prefix(1))
        observations.append(item.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self, self.player.currentItem === item, item.status == .failed else { return }
                self.error = item.error?.localizedDescription ?? "영상을 열 수 없습니다."
            }
        })
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self, weak item] _ in
            guard let self, self.player.currentItem === item, let index = self.playlist.firstIndex(of: url),
                  self.playlist.indices.contains(index + 1) else { return }
            self.play(self.playlist[index + 1])
        }
        output = frames
        fileName = url.lastPathComponent
        player.replaceCurrentItem(with: item)
        player.play()
    }

    func toggle() {
        if playing { player.pause(); return }
        if let item = player.currentItem, item.currentTime() >= item.duration { player.seek(to: .zero) }
        player.play()
    }
}

struct PlayerScreen: View {
    @StateObject private var playback = Playback()
    @State private var rightEye = false
    @State private var reset = 0
    @State private var dropTargeted = false

    private func timestamp(_ seconds: Double) -> String {
        let total = Int(seconds)
        if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                VideoSurface(playback: playback, rightEye: rightEye, reset: reset)
                if playback.fileName.isEmpty {
                    Text("VR180 동영상이나 폴더를 이 창에 끌어다 놓으세요.")
                        .foregroundStyle(.white).allowsHitTesting(false)
                }
            }
            HStack {
                Text(timestamp(playback.position))
                Slider(value: Binding(get: { playback.position }, set: { playback.seek(to: $0) }),
                       in: 0...max(playback.duration, 0.001)) { Text("재생 위치") }
                    .disabled(playback.duration <= 0)
                Text(timestamp(playback.duration))
            }.monospacedDigit().padding(.horizontal, 10).padding(.top, 6)
            HStack {
                Button("열기…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.allowedContentTypes = [.movie]
                    if panel.runModal() == .OK, let url = panel.url {
                        playback.open(url)
                    }
                }.keyboardShortcut("o")
                Button(playback.playing ? "일시정지" : "재생") { playback.toggle() }
                    .disabled(playback.fileName.isEmpty)
                if let current = playback.currentURL {
                    Menu {
                        ForEach(playback.playlist, id: \.self) { url in
                            Button {
                                playback.play(url)
                            } label: {
                                if url == current { Label(url.lastPathComponent, systemImage: "checkmark") }
                                else { Text(url.lastPathComponent) }
                            }
                        }
                    } label: {
                        Text(current.lastPathComponent).lineLimit(1).truncationMode(.middle)
                    }.help("플레이리스트")
                }
                Spacer()
                Picker("표시할 눈", selection: $rightEye) {
                    Text("왼쪽").tag(false)
                    Text("오른쪽").tag(true)
                }.pickerStyle(.segmented).fixedSize()
                Button("시점 초기화") { reset += 1 }
            }.padding(10)
        }.frame(minWidth: 620, minHeight: 360)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { $0.isFileURL }) else { return false }
            playback.open(url)
            return true
        } isTargeted: { dropTargeted = $0 }
        .overlay {
            if dropTargeted {
                Rectangle().strokeBorder(Color.accentColor, lineWidth: 3).allowsHitTesting(false)
            }
        }
        .onChange(of: playback.currentURL) { _ in reset += 1 }
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
        .alert("재생 오류", isPresented: Binding(get: { playback.error != nil }, set: { if !$0 { playback.error = nil } })) {
            Button("확인") { playback.error = nil }
        } message: { Text(playback.error ?? "") }
    }
}
