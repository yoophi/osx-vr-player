import CoreImage
import Vision

/// Boxes use the selected eye's normalized, bottom-left image coordinates.
struct FaceAnalysis {
    let image: CGImage
    let faces: [CGRect]
    let tracked: CGRect?
}

/// A sequence belongs to one eye of one movie. Its methods run on the analysis queue.
final class VisionFaceAnalyzer {
    private let sequence = VNSequenceRequestHandler()
    private var tracker: VNTrackObjectRequest?

    func select(_ box: CGRect, in image: CGImage) throws {
        let request = VNTrackObjectRequest(detectedObjectObservation: VNDetectedObjectObservation(boundingBox: box))
        request.trackingLevel = .accurate
        try sequence.perform([request], on: image)
        if let found = request.results?.first as? VNDetectedObjectObservation {
            request.inputObservation = found
            tracker = request
        }
    }

    func analyze(_ buffer: CVPixelBuffer, rightEye: Bool, context: CIContext) throws -> FaceAnalysis {
        let source = CIImage(cvPixelBuffer: buffer)
        let width = floor(source.extent.width / 2)
        let rect = CGRect(x: rightEye ? width : 0, y: 0, width: width, height: source.extent.height)
        let scale = min(1, 960 / max(rect.width, rect.height))
        let eye = source.cropped(to: rect)
            .transformed(by: CGAffineTransform(translationX: -rect.minX, y: 0))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let image = context.createCGImage(eye, from: eye.extent) else {
            throw CocoaError(.coderReadCorrupt)
        }
        let detector = VNDetectFaceRectanglesRequest()
        try VNImageRequestHandler(cgImage: image).perform([detector])
        let boxes = (detector.results ?? []).sorted { $0.confidence > $1.confidence }.prefix(32).map(\.boundingBox)
        var tracked: CGRect?
        if let tracker {
            try sequence.perform([tracker], on: image)
            if let found = tracker.results?.first as? VNDetectedObjectObservation, found.confidence >= 0.55 {
                tracker.inputObservation = found
                tracked = found.boundingBox
            } else {
                self.tracker = nil
            }
        }
        return FaceAnalysis(image: image, faces: boxes, tracked: tracked)
    }
}
