import Foundation
import UniformTypeIdentifiers

import PlayerCore

struct FileMovieLibrary: MovieLibrary {
    func kind(of url: URL) throws -> MediaKind {
        if try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true { return .directory }
        return isMovie(url) ? .movie : .unsupported
    }

    private func isMovie(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isRegularFileKey]) else { return false }
        return values.isRegularFile == true && values.contentType?.conforms(to: .movie) == true
    }

    func movies(in folder: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentTypeKey, .isRegularFileKey], options: [.skipsHiddenFiles])
            .filter(isMovie)
            .map { $0.standardizedFileURL }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
