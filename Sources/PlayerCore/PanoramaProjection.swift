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

    /// Exponential damping halves the angular error every 120 ms, independent of refresh rate.
    public static func follow(from current: SIMD2<Float>, toward target: SIMD2<Float>, elapsed: Double) -> SIMD2<Float> {
        let fraction = 1 - exp2(-min(max(elapsed, 0), 0.1) / 0.12)
        return current + (target - current) * Float(fraction)
    }

    /// The direction of the face in camera space at the end of a manual pan.
    public static func cameraRay(to box: CGRect, from camera: SIMD2<Float>) -> SIMD3<Float> {
        let face = angles(centeredOn: box)
        let yaw = face.x - camera.x
        let x = cos(face.y) * sin(yaw)
        let y = sin(face.y)
        let z = cos(face.y) * cos(yaw)
        return SIMD3(x, cos(camera.y) * y - sin(camera.y) * z,
                        sin(camera.y) * y + cos(camera.y) * z)
    }

    /// Invert the shader's pitch and yaw rotations so the moving face stays on the saved ray.
    public static func trackingAngles(for box: CGRect, ray: SIMD3<Float>, current: SIMD2<Float>) -> SIMD2<Float> {
        let face = angles(centeredOn: box)
        let radius = hypot(ray.y, ray.z)
        guard radius > 0.00001 else { return SIMD2(face.x - atan2(ray.x, ray.z), current.y) }
        let elevation = asin(min(1, max(-1, sin(face.y) / radius)))
        let offset = atan2(ray.y, ray.z)
        let limit = Float.pi / 2
        func solution(_ elevation: Float) -> SIMD2<Float> {
            let pitch = min(limit, max(-limit, atan2(sin(elevation - offset), cos(elevation - offset))))
            let z = cos(pitch) * ray.z - sin(pitch) * ray.y
            let yaw = face.x - atan2(ray.x, z)
            return SIMD2(min(limit, max(-limit, atan2(sin(yaw), cos(yaw)))), pitch)
        }
        let first = solution(elevation)
        let second = solution(.pi - elevation)
        // Near the poles two pitches can solve the same projection. Prefer a valid,
        // continuous solution over one clipped to the camera's angular limits.
        func error(_ candidate: SIMD2<Float>) -> Float {
            simd_distance_squared(cameraRay(to: box, from: candidate), ray)
        }
        let difference = error(first) - error(second)
        if abs(difference) > 0.000001 { return difference < 0 ? first : second }
        return simd_distance_squared(current, first) <= simd_distance_squared(current, second) ? first : second
    }

    public static func angles(centeredOn box: CGRect) -> SIMD2<Float> {
        SIMD2(Float(box.midX - 0.5) * .pi, Float(box.midY - 0.5) * .pi)
    }
}
