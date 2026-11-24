import AVFoundation
import MetalKit
import SwiftUI

protocol VideoFrameSource: AnyObject {
    var output: AVPlayerItemVideoOutput? { get }
}

struct VideoSurface: NSViewRepresentable {
    let frames: VideoFrameSource
    let onError: (String) -> Void
    let rightEye: Bool
    let reset: Int
    let zoom: Double
    let onZoom: (Double) -> Void
    func makeNSView(context: Context) -> PanoramaView { PanoramaView(frames: frames, onError: onError) }
    func updateNSView(_ view: PanoramaView, context: Context) {
        view.zoom = Float(zoom)
        view.onZoom = onZoom
        view.rightEye = rightEye
        if view.reset != reset {
            view.angles = .zero
            view.reset = reset
        }
    }
}

final class PanoramaView: MTKView {
    let frames: VideoFrameSource
    var angles = SIMD2<Float>.zero
    var zoom: Float = 1
    var onZoom: ((Double) -> Void)?
    var reset = 0
    var rightEye = false
    private var queue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    private var cache: CVMetalTextureCache?
    private var frameTexture: CVMetalTexture?
    private var previousOutput: AVPlayerItemVideoOutput?

    init(frames: VideoFrameSource, onError: @escaping (String) -> Void) {
        self.frames = frames
        super.init(frame: .zero, device: MTLCreateSystemDefaultDevice())
        clearColor = MTLClearColorMake(0, 0, 0, 1)
        do {
            guard let device, let queue = device.makeCommandQueue() else { throw RenderError.unavailable }
            self.queue = queue
            let library = try device.makeLibrary(source: Self.shader, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "triangle")
            descriptor.fragmentFunction = library.makeFunction(name: "panorama")
            descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            guard CVMetalTextureCacheCreate(nil, nil, device, nil, &cache) == kCVReturnSuccess else {
                throw RenderError.unavailable
            }
        } catch {
            DispatchQueue.main.async { onError(error.localizedDescription) }
        }
    }
    required init(coder: NSCoder) { fatalError("Unsupported initializer") }
    override func scrollWheel(with event: NSEvent) {
        let direction: Double = event.isDirectionInvertedFromDevice ? -1 : 1
        let steps = event.scrollingDeltaY / (event.hasPreciseScrollingDeltas ? 40 : 1)
        onZoom?(direction * steps)
    }

    override func mouseDragged(with event: NSEvent) {
        let scale = Float.pi / Float(max(bounds.height, 1)) * 0.5 / zoom
        angles.x = max(-.pi/2, min(.pi/2, angles.x - Float(event.deltaX) * scale))
        angles.y = max(-.pi/2, min(.pi/2, angles.y + Float(event.deltaY) * scale))
    }

    override func draw(_ dirtyRect: NSRect) {
        if previousOutput !== frames.output {
            frameTexture = nil
            previousOutput = frames.output
        }
        if let output = previousOutput, let cache {
            let time = output.itemTime(forHostTime: CACurrentMediaTime())
            if output.hasNewPixelBuffer(forItemTime: time),
               let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) {
                var texture: CVMetalTexture?
                if CVMetalTextureCacheCreateTextureFromImage(nil, cache, buffer, nil, .bgra8Unorm,
                    CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer), 0, &texture) == kCVReturnSuccess {
                    frameTexture = texture
                }
            }
        }
        guard let command = queue?.makeCommandBuffer(), let pass = currentRenderPassDescriptor,
              let drawable = currentDrawable, let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        if let frameTexture, let texture = CVMetalTextureGetTexture(frameTexture), let pipeline {
            var params = SIMD4(angles.x, angles.y, Float(drawableSize.width / max(drawableSize.height, 1)), rightEye ? 1 : 0)
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.setFragmentBytes(&params, length: MemoryLayout.size(ofValue: params), index: 0)
            var focalLength = zoom
            encoder.setFragmentBytes(&focalLength, length: MemoryLayout<Float>.size, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            command.addCompletedHandler { _ in withExtendedLifetime(frameTexture) {} }
        }
        encoder.endEncoding()
        command.present(drawable)
        command.commit()
    }

    private enum RenderError: LocalizedError {
        case unavailable
        var errorDescription: String? { "Metal 렌더러를 초기화할 수 없습니다." }
    }
    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    struct Vertex { float4 position [[position]]; float2 screen; };
    vertex Vertex triangle(uint i [[vertex_id]]) {
        float2 p = float2(i == 1 ? 3 : -1, i == 2 ? 3 : -1);
        return {float4(p, 0, 1), p};
    }
    fragment float4 panorama(Vertex v [[stage_in]], texture2d<float> frame [[texture(0)]],
                             constant float4 &params [[buffer(0)]], constant float &zoom [[buffer(1)]]) {
        float3 d = normalize(float3(v.screen.x * params.z, v.screen.y, zoom));
        float cp = cos(params.y), sp = sin(params.y);
        d.yz = float2(cp*d.y + sp*d.z, -sp*d.y + cp*d.z);
        float cy = cos(params.x), sy = sin(params.x);
        d.xz = float2(cy*d.x + sy*d.z, -sy*d.x + cy*d.z);
        if (d.z < 0) return float4(0,0,0,1);
        float u = atan2(d.x, d.z) / M_PI_F + 0.5;
        float margin = 1.0 / frame.get_width();
        float2 uv = float2((clamp(u, margin, 1-margin) + params.w)*0.5, 0.5 - asin(clamp(d.y,-1.0f,1.0f))/M_PI_F);
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        return frame.sample(s, uv);
    }
    """
}
