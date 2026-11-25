import SwiftUI
import UniformTypeIdentifiers
import PlayerCore

struct PlayerScreen: View {
    @ObservedObject var presentation: PlayerPresentation
    private var playback: PlaybackSession { presentation.session }
    private var state: PlaybackState { playback.state }
    @State private var zoom = 1.0
    @State private var trackingEnabled = false
    @State private var rightEye = false
    @State private var reset = 0
    @State private var dropTargeted = false

    @State private var showsVolume = false
    @State private var keyMonitor: Any?

    private func adjustZoom(steps: Double) {
        guard state.currentURL != nil, steps.isFinite else { return }
        zoom = min(4, max(0.5, zoom * pow(1.2, steps)))
    }

    private func installPlayerKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags
            guard let window = event.window, window.isKeyWindow, window.attachedSheet == nil,
                  !(window is NSPanel), NSApp.modalWindow == nil,
                  !flags.contains(.command), !flags.contains(.control) else { return event }
            if showsVolume { return event }
            if state.currentURL != nil, !flags.contains(.option) {
                if !flags.contains(.shift), [29, 82].contains(event.keyCode) {
                    zoom = 1
                    return nil
                }
                switch event.characters {
                case "+", "=": adjustZoom(steps: 1); return nil
                case "-": adjustZoom(steps: -1); return nil
                case "0": zoom = 1; return nil
                default: break
                }
            }
            if [36, 76, 53].contains(event.keyCode) {
                guard !flags.contains(.option), !flags.contains(.shift) else { return event }
                guard !event.isARepeat else { return nil }
                if event.keyCode != 53 {
                    guard state.currentURL != nil else { return event }
                    window.toggleFullScreen(nil)
                } else if window.styleMask.contains(.fullScreen) {
                    window.toggleFullScreen(nil)
                } else if state.currentURL == nil {
                    NSApp.terminate(nil)
                } else if state.stopped {
                    playback.close()
                } else {
                    playback.stop()
                }
                return nil
            }
            guard state.duration > 0,
                  event.keyCode == 123 || event.keyCode == 124 else { return event }
            let interval: Double
            switch (flags.contains(.shift), flags.contains(.option)) {
            case (true, true): interval = 180
            case (false, true): interval = 60
            case (true, false): interval = 30
            default: interval = 5
            }
            playback.seek(to: state.position + (event.keyCode == 123 ? -interval : interval))
            return nil
        }
    }

    private func timestamp(_ seconds: Double) -> String {
        let total = Int(seconds)
        if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var windowTitle: String {
        guard let url = state.currentURL else { return "VR180 Player" }
        return url.pathComponents.suffix(2).joined(separator: "/").replacingOccurrences(of: "//", with: "/")
    }

    var body: some View {
        ZStack {
            VideoSurface(frames: presentation.engine, onError: { playback.setError($0) }, rightEye: rightEye, trackingEnabled: trackingEnabled, reset: reset, zoom: zoom, onZoom: adjustZoom)
            if state.currentURL == nil {
                Text("VR180 동영상이나 폴더를 이 창에 끌어다 놓으세요.")
                    .foregroundStyle(.white).allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            if zoom != 1 {
                Text(zoom, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit().padding(6)
                    .background(.regularMaterial, in: Capsule()).padding(12)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            controls.padding(12)
        }
        .frame(minWidth: 620, minHeight: 360)
        .navigationTitle(windowTitle)
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
        .onOpenURL { url in
            if url.isFileURL { playback.open(url) }
        }
        .onChange(of: state.currentURL) { _ in
            reset += 1
            zoom = 1
        }
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            installPlayerKeys()
        }
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
        .alert("재생 오류", isPresented: Binding(get: { state.error != nil }, set: { if !$0 { playback.setError(nil) } })) {
            Button("확인") { playback.setError(nil) }
        } message: { Text(state.error ?? "") }
    }

    private func neighborButton(_ offset: Int, title: String, symbol: String) -> some View {
        let file = state.neighbor(offset)
        return Button {
            if let file { playback.play(file) }
        } label: {
            Label(title, systemImage: symbol)
        }
        .labelStyle(.iconOnly)
        .help(title)
        .disabled(file == nil)
    }

    private func eyeButton(right: Bool) -> some View {
        let selected = rightEye == right
        let title = right ? "오른쪽 눈 표시" : "왼쪽 눈 표시"
        let symbol = right ? "r.circle" : "l.circle"
        return Button { rightEye = right } label: {
            Label(title, systemImage: selected ? symbol + ".fill" : symbol)
        }
        .labelStyle(.iconOnly)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(title)
    }

    private var controls: some View {
        VStack(spacing: 6) {
            HStack {
                Text(timestamp(state.position))
                Slider(value: Binding(get: { state.position }, set: { playback.seek(to: $0) }),
                       in: 0...max(state.duration, 0.001)) { Text("재생 위치") }
                    .disabled(state.duration <= 0)
                Text(timestamp(state.duration))
            }.monospacedDigit()
            HStack {
                Button("열기…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.allowedContentTypes = [.movie]
                    if panel.runModal() == .OK, let url = panel.url {
                        playback.open(url)
                    }
                }.keyboardShortcut("o")
                neighborButton(-1, title: "이전 파일", symbol: "backward.end.fill")
                Button { playback.toggle() } label: {
                    Label(state.playing ? "일시정지" : "재생",
                          systemImage: state.playing ? "pause.fill" : "play.fill")
                }
                .labelStyle(.iconOnly)
                .help(state.playing ? "일시정지" : "재생")
                .disabled(state.currentURL == nil)
                neighborButton(1, title: "다음 파일", symbol: "forward.end.fill")
                Button { showsVolume.toggle() } label: {
                    Label("볼륨", systemImage: "speaker.wave.2.fill")
                }
                .labelStyle(.iconOnly)
                .help("볼륨 조절")
                .popover(isPresented: $showsVolume, arrowEdge: .bottom) {
                    VStack {
                        Text(playback.volume, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                        VolumeSlider(value: playback.volume, onChange: playback.setVolume)
                            .frame(width: 24, height: 110)
                    }.padding(12)
                }
                Button { playback.toggleMute() } label: {
                    Label(playback.isMuted ? "음소거 해제" : "음소거", systemImage: "speaker.slash.fill")
                }
                .labelStyle(.iconOnly)
                .tint(playback.isMuted ? Color.accentColor : nil)
                .accessibilityValue(playback.isMuted ? "켜짐" : "꺼짐")
                .help(playback.isMuted ? "음소거 해제" : "음소거")
                if let current = state.currentURL {
                    Menu {
                        ForEach(state.playlist, id: \.self) { url in
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
                Toggle(isOn: $trackingEnabled) {
                    Label("얼굴 추적", systemImage: "viewfinder")
                }
                .toggleStyle(.button)
                .labelStyle(.iconOnly)
                .help(trackingEnabled ? "얼굴 추적 켜짐 · 얼굴을 클릭해 추적하고 다시 클릭해 중지" : "얼굴 추적 꺼짐")
                HStack(spacing: 2) {
                    eyeButton(right: false)
                    eyeButton(right: true)
                }
                Button { reset += 1 } label: {
                    Label("시점 초기화", systemImage: "scope")
                }
                .labelStyle(.iconOnly)
                .help("시점 초기화")
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .environment(\.colorScheme, .dark)
    }
}
