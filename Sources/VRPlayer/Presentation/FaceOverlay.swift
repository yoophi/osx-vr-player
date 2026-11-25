import CoreImage
import QuartzCore
import simd

/// Schedules at most one Vision job at a time. UI and frame submission run on the main thread.
final class FaceOverlay {
    private let queue = DispatchQueue(label: "vrplayer.face-analysis", qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var analyzer = VisionFaceAnalyzer()
    private var analysis: FaceAnalysis?
    private var selection: (box: CGRect, frame: FaceAnalysis)?
    private var busy = false
    private var generation = 0
    private var lastFrame: UInt64?
    private var nextUpdate = 0.0
    private(set) var tracked: CGRect?
    var faces: [CGRect] { analysis?.faces ?? [] }

    private(set) var hasSelection = false

    func face(at point: CGPoint) -> CGRect? {
        faces.filter { $0.contains(point) }.min { $0.width * $0.height < $1.width * $1.height }
    }

    func reset() {
        generation &+= 1
        analyzer = VisionFaceAnalyzer()
        selection = nil
        analysis = nil
        tracked = nil
        hasSelection = false
        nextUpdate = 0
        lastFrame = nil
    }

    func toggleSelection(at point: CGPoint?) {
        if hasSelection {
            reset()
            return
        }
        guard let point, let analysis, let box = face(at: point) else { return }
        generation &+= 1
        analyzer = VisionFaceAnalyzer()
        selection = (box, analysis)
        tracked = box
        hasSelection = true
        nextUpdate = 0
        lastFrame = nil
    }

    func update(buffer: CVPixelBuffer, frame: UInt64, time: Double, rightEye: Bool) {
        let now = CACurrentMediaTime()
        guard !busy, frame != lastFrame, now >= nextUpdate else { return }
        busy = true
        nextUpdate = now + 0.1
        lastFrame = frame
        let seed = selection
        selection = nil
        queue.async { [weak self, analyzer, generation, context] in
            let result: FaceAnalysis?
            do {
                if let seed { analyzer.select(seed.box, in: seed.frame) }
                result = try analyzer.analyze(buffer, rightEye: rightEye, time: time, context: context)
            } catch { result = nil }
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                guard self.generation == generation else { return }
                self.analysis = result
                self.tracked = result?.tracked
                if let result { self.hasSelection = result.hasSelection }
            }
        }
    }
}
