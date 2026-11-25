import CoreGraphics
import XCTest
import PlayerCore

final class PanoramaProjectionTests: XCTestCase {
    func testCenterTracksFaceInNormalizedEyeSpaceAtAnyZoom() throws {
        let box = CGRect(x: 0.67, y: 0.21, width: 0.12, height: 0.2)
        let angles = PanoramaProjection.angles(centeredOn: box)
        for zoom: Float in [0.5, 1, 4] {
            let hit = try XCTUnwrap(PanoramaProjection.eyePoint(screen: .zero, aspect: 1.6, zoom: zoom, angles: angles))
            XCTAssertEqual(hit.x, box.midX, accuracy: 0.0001)
            XCTAssertEqual(hit.y, box.midY, accuracy: 0.0001)
        }
    }

    func testManualPanKeepsMovingFaceAtReleasedScreenPosition() throws {
        let face = CGRect(x: 0.59, y: 0.56, width: 0.09, height: 0.12)
        let released = SIMD2<Float>(0.24, 0.51)
        let ray = PanoramaProjection.cameraRay(to: face, from: released)
        let screen = SIMD2(ray.x / (1.7 * ray.z), ray.y / ray.z)
        var camera = released
        for target in [face, face.offsetBy(dx: 0.08, dy: -0.07), face.offsetBy(dx: -0.17, dy: 0.12)] {
            camera = PanoramaProjection.trackingAngles(for: target, ray: ray, current: camera)
            let projected = try XCTUnwrap(PanoramaProjection.eyePoint(screen: screen, aspect: 1.7, zoom: 1, angles: camera))
            XCTAssertEqual(projected.x, target.midX, accuracy: 0.00001)
            XCTAssertEqual(projected.y, target.midY, accuracy: 0.00001)
        }
    }

    func testClickProjectionUsesAspectAndRejectsBackOfHemisphere() throws {
        let point = try XCTUnwrap(PanoramaProjection.eyePoint(screen: SIMD2(0.5, 0), aspect: 2, zoom: 1, angles: .zero))
        XCTAssertEqual(point.x, 0.75, accuracy: 0.0001)
        XCTAssertEqual(point.y, 0.5, accuracy: 0.0001)
        XCTAssertNil(PanoramaProjection.eyePoint(screen: SIMD2(1, 0), aspect: 2, zoom: 1, angles: SIMD2(.pi/2, 0)))
    }
}
