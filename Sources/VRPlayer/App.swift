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
    private var observations: [NSKeyValueObservation] = []

    init() {
        observations.append(player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            DispatchQueue.main.async { self?.playing = player.timeControlStatus != .paused }
        })
    }

    func open(_ url: URL) {
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
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                VideoSurface(playback: playback, rightEye: rightEye, reset: reset)
                if playback.fileName.isEmpty {
                    Text("좌우 나란히 배치된 180° 등거리 원통형 영상을 여세요.")
                        .foregroundStyle(.white).allowsHitTesting(false)
                }
            }
            HStack {
                Button("열기…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.movie]
                    if panel.runModal() == .OK, let url = panel.url {
                        reset += 1
                        playback.open(url)
                    }
                }.keyboardShortcut("o")
                Button(playback.playing ? "일시정지" : "재생") { playback.toggle() }
                    .disabled(playback.fileName.isEmpty)
                Text(playback.fileName).lineLimit(1).truncationMode(.middle)
                Spacer()
                Picker("표시할 눈", selection: $rightEye) {
                    Text("왼쪽").tag(false)
                    Text("오른쪽").tag(true)
                }.pickerStyle(.segmented).fixedSize()
                Button("시점 초기화") { reset += 1 }
            }.padding(10)
        }.frame(minWidth: 620, minHeight: 360)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { $0.isFileURL && UTType(filenameExtension: $0.pathExtension)?.conforms(to: .movie) == true }) else { return false }
            reset += 1
            playback.open(url)
            return true
        } isTargeted: { dropTargeted = $0 }
        .overlay {
            if dropTargeted {
                Rectangle().strokeBorder(Color.accentColor, lineWidth: 3).allowsHitTesting(false)
            }
        }
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
        .alert("재생 오류", isPresented: Binding(get: { playback.error != nil }, set: { if !$0 { playback.error = nil } })) {
            Button("확인") { playback.error = nil }
        } message: { Text(playback.error ?? "") }
    }
}
