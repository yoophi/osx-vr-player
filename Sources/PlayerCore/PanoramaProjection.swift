import CoreGraphics
import simd

public enum PanoramaProjection {
    /// Mirrors the Metal shader's perspective ray and rotation before SBS packing.
    public static func eyePoint(screen: SIMD2<Float>, aspect: Float, zoom: Float, angles: SIMD2<Float>) -> CGPoint? {
        let ray = simd_normalize(SIMD3(screen.x * aspect, screen.y, zoom))
        let y = cos(angles.y) * ray.y + sin(angles.y) * ray.z
        let z = -sin(angles.y) * ray.y + cos(angles.y) * ray.z
        let x = cos(angles.x) * ray.x + sin(angles.x) * z
        let forward = -sin(angles.x) * ray.x + cos(angles.x) * z
        guard forward >= 0 else { return nil }
        return CGPoint(x: CGFloat(atan2(x, forward) / .pi + 0.5),
                       y: CGFloat(asin(min(1, max(-1, y))) / .pi + 0.5))
    }

    public static func angles(centeredOn box: CGRect) -> SIMD2<Float> {
        SIMD2(Float(box.midX - 0.5) * .pi, Float(box.midY - 0.5) * .pi)
    }
}
