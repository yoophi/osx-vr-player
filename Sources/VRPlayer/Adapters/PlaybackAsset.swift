import AVFoundation

enum PlaybackAsset {
    // Some MP4 files carry complete HEVC decoder configuration under the hev1
    // sample entry. AVFoundation can play their audio while ignoring their video.
    static func open(_ url: URL) async throws -> AVAsset {
        let original = AVURLAsset(url: url)
        let tracks = try await original.loadTracks(withMediaType: .video)
        guard !tracks.isEmpty else { throw PlaybackFormatError.noVideo }
        for track in tracks where try await track.load(.isPlayable) { return original }

        let movie = AVMutableMovie(url: url)
        var replaced = false
        for track in try await movie.loadTracks(withMediaType: .video) {
            for description in try await track.load(.formatDescriptions) {
                guard CMFormatDescriptionGetMediaSubType(description) == 0x68657631, // hev1
                      let compatible = hevcDescription(for: description) else { continue }
                track.replaceFormatDescription(description, with: compatible)
                replaced = true
            }
        }
        guard replaced else { throw PlaybackFormatError.unsupported }
        return movie
    }

    private static func hevcDescription(for source: CMFormatDescription) -> CMVideoFormatDescription? {
        let size = CMVideoFormatDescriptionGetDimensions(source)
        var result: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault, codecType: kCMVideoCodecType_HEVC,
                                             width: size.width, height: size.height,
                                             extensions: CMFormatDescriptionGetExtensions(source),
                                             formatDescriptionOut: &result) == noErr, let result else { return nil }
        // Only adapt tracks whose header supplies decoder parameter sets.
        var count = 0
        guard CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(result, parameterSetIndex: 0,
                parameterSetPointerOut: nil, parameterSetSizeOut: nil, parameterSetCountOut: &count,
                nalUnitHeaderLengthOut: nil) == noErr, count >= 3 else { return nil }
        return result
    }
}

private enum PlaybackFormatError: LocalizedError {
    case noVideo, unsupported
    var errorDescription: String? {
        switch self {
        case .noVideo: return "영상 트랙을 찾을 수 없습니다."
        case .unsupported: return "이 파일의 영상 트랙을 macOS에서 디코딩할 수 없습니다."
        }
    }
}
