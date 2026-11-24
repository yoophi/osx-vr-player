import CoreGraphics
import XCTest
import PlayerCore

final class FaceTrackingTests: XCTestCase {
    private let box = CGRect(x: 0.3, y: 0.4, width: 0.12, height: 0.16)
    private let appearance: [UInt8] = [64, 128, 192]

    func testReappearanceAfterGapAndRejectionOfDistractor() {
        var target = FaceAssociation(box: box, time: 0, appearance: appearance)
        XCTAssertNil(target.match([], at: 0.5) { _ in [] })
        XCTAssertNil(target.match([box], at: 1) { _ in [255, 255, 255] })
        let returned = box.offsetBy(dx: 0.06, dy: 0)
        XCTAssertEqual(target.match([returned], at: 1.8) { _ in appearance }, returned)
        XCTAssertNil(target.match([returned], at: 4) { _ in appearance })
    }

    func testAmbiguousFacesDoNotReplaceTarget() {
        var target = FaceAssociation(box: box, time: 0, appearance: appearance)
        let pair = [box.offsetBy(dx: -0.02, dy: 0), box.offsetBy(dx: 0.02, dy: 0)]
        XCTAssertNil(target.match(pair, at: 0.5) { _ in appearance })
    }

    func testCameraConvergesAtSameRateAcrossDisplayRefreshRates() {
        let goal = SIMD2<Float>(1, -0.5)
        func advance(_ hz: Int) -> SIMD2<Float> {
            (0..<hz).reduce(.zero) { current, _ in
                PanoramaProjection.follow(from: current, toward: goal, elapsed: 1 / Double(hz))
            }
        }
        let first = PanoramaProjection.follow(from: .zero, toward: goal, elapsed: 1.0 / 60)
        XCTAssertGreaterThan(first.x, 0)
        XCTAssertLessThan(first.x, 0.1)
        XCTAssertEqual(advance(30).x, advance(120).x, accuracy: 0.00001)
        XCTAssertEqual(advance(60).x, goal.x, accuracy: 0.005)
    }
}
