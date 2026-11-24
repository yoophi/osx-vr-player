import CoreGraphics
import Foundation

/// Associates short gaps within a movie using local appearance and motion, without storing identities.
public struct FaceAssociation {
    private var lastBox: CGRect
    private var lastTime: Double
    private var velocity = CGPoint.zero
    private var appearance: [UInt8]

    public init(box: CGRect, time: Double, appearance: [UInt8]) {
        lastBox = box
        lastTime = time
        self.appearance = appearance
    }

    public func expired(at time: Double) -> Bool { time - lastTime > 2 || time < lastTime }

    public mutating func match(_ boxes: [CGRect], at time: Double,
                               appearanceOf: (CGRect) -> [UInt8]) -> CGRect? {
        guard !expired(at: time), !appearance.isEmpty else { return nil }
        let elapsed = time - lastTime
        let horizon = min(elapsed, 0.5)
        let predicted = CGPoint(x: lastBox.midX + velocity.x * horizon,
                                y: lastBox.midY + velocity.y * horizon)
        let radius = max(0.04, max(lastBox.width, lastBox.height) * 0.85) + min(elapsed * 0.15, 0.20)
        var candidates: [(box: CGRect, pixels: [UInt8], score: Double)] = []
        for box in boxes {
            let distance = hypot(box.midX - predicted.x, box.midY - predicted.y)
            guard distance <= radius, box.width > 0, box.height > 0 else { continue }
            let scaleChange = max(abs(log(box.width / lastBox.width)), abs(log(box.height / lastBox.height)))
            guard scaleChange < 0.7 else { continue }
            let pixels = appearanceOf(box)
            guard pixels.count == appearance.count else { continue }
            let difference = zip(pixels, appearance).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
            let visual = Double(difference) / (255 * Double(pixels.count))
            guard visual < 0.20 else { continue }
            candidates.append((box, pixels, visual * 4 + distance / radius * 0.4 + scaleChange * 0.2))
        }
        candidates.sort { $0.score < $1.score }
        guard let best = candidates.first else { return nil }
        if candidates.count > 1 && candidates[1].score - best.score < 0.08 { return nil }
        if elapsed > 0.001 {
            velocity.x = 0.5 * velocity.x + 0.5 * (best.box.midX - lastBox.midX) / elapsed
            velocity.y = 0.5 * velocity.y + 0.5 * (best.box.midY - lastBox.midY) / elapsed
        }
        appearance = zip(appearance, best.pixels).map { UInt8((3 * Int($0) + Int($1)) / 4) }
        lastBox = best.box
        lastTime = time
        return best.box
    }
}
