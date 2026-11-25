import CoreImage
import Vision
import PlayerCore

/// Boxes use the selected eye's normalized, bottom-left image coordinates.
struct FaceAnalysis {
    let time: Double
    let image: CGImage
    let faces: [CGRect]
    let tracked: CGRect?
    let hasSelection: Bool
}

/// A sequence belongs to one eye of one movie. Its methods run on the analysis queue.
final class VisionFaceAnalyzer {
    private var face: FaceAssociation?

    // A small RGB patch from the inner face, used only while following this selection.
    private func appearance(_ box: CGRect, in image: CGImage) -> [UInt8] {
        let inner = box.insetBy(dx: box.width * 0.15, dy: box.height * 0.12)
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let crop = CGRect(x: inner.minX * w, y: (1 - inner.maxY) * h, width: inner.width * w, height: inner.height * h)
        guard let patch = image.cropping(to: crop.integral) else { return [] }
        var bytes = [UInt8](repeating: 0, count: 6 * 6 * 4)
        return bytes.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: 6, height: 6, bitsPerComponent: 8,
                                      bytesPerRow: 24, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return [] }
            ctx.interpolationQuality = .medium
            ctx.draw(patch, in: CGRect(x: 0, y: 0, width: 6, height: 6))
            return raw.enumerated().compactMap { $0.offset % 4 == 3 ? nil : $0.element }
        }
    }

    func select(_ box: CGRect, in frame: FaceAnalysis) {
        face = FaceAssociation(box: box, time: frame.time, appearance: appearance(box, in: frame.image))
    }

    func analyze(_ buffer: CVPixelBuffer, rightEye: Bool, time: Double, context: CIContext) throws -> FaceAnalysis {
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
        if var selected = face {
            tracked = selected.match(boxes, at: time) { appearance($0, in: image) }
            face = selected.expired(at: time) ? nil : selected
        }
        return FaceAnalysis(time: time, image: image, faces: boxes, tracked: tracked, hasSelection: face != nil)
    }
}
