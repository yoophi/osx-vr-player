import CoreImage
import QuartzCore
import simd

/// Schedules at most one Vision job at a time. UI and frame submission run on the main thread.
final class FaceOverlay {
    private let queue = DispatchQueue(label: "vrplayer.face-analysis", qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var analyzer = VisionFaceAnalyzer()
    private var analysis: FaceAnalysis?
    private var selection: (CGRect, CGImage)?
    private var busy = false
    private var generation = 0
    private var lastFrame: UInt64?
    private var nextUpdate = 0.0
    private(set) var tracked: CGRect?
    var faces: [CGRect] { analysis?.faces ?? [] }

    // Metal requires a bound buffer even when the shader has no outlines to draw.
    private(set) var rectangles: [SIMD4<Float>] = [.zero]
    private(set) var counts = SIMD2<UInt32>(0, .max)

    private func updateOutlines() {
        var boxes = faces
        if let tracked { boxes.append(tracked) }
        counts = SIMD2(UInt32(boxes.count), tracked == nil ? .max : UInt32(boxes.count - 1))
        rectangles = boxes.map { SIMD4(Float($0.minX), Float($0.minY), Float($0.maxX), Float($0.maxY)) }
        if rectangles.isEmpty { rectangles.append(.zero) }
    }

    func reset() {
        generation &+= 1
        analyzer = VisionFaceAnalyzer()
        selection = nil
        analysis = nil
        tracked = nil
        updateOutlines()
        nextUpdate = 0
        lastFrame = nil
    }

    func select(at point: CGPoint) {
        guard let analysis, let face = faces.filter({ $0.contains(point) }).min(by: {
            $0.width * $0.height < $1.width * $1.height
        }) else { return }
        generation &+= 1
        analyzer = VisionFaceAnalyzer()
        selection = (face, analysis.image)
        tracked = face
        updateOutlines()
        nextUpdate = 0
        lastFrame = nil
    }

    func update(buffer: CVPixelBuffer, frame: UInt64, rightEye: Bool) {
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
                if let (box, image) = seed { try analyzer.select(box, in: image) }
                result = try analyzer.analyze(buffer, rightEye: rightEye, context: context)
            } catch { result = nil }
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                guard self.generation == generation else { return }
                self.analysis = result
                self.tracked = result?.tracked
                self.updateOutlines()
                if result == nil { self.analyzer = VisionFaceAnalyzer() }
            }
        }
    }
}
