import Foundation
import UniformTypeIdentifiers

enum Playlist {
    static func isMovie(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isRegularFileKey]) else { return false }
        return values.isRegularFile == true && values.contentType?.conforms(to: .movie) == true
    }

    static func movies(in folder: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentTypeKey, .isRegularFileKey], options: [.skipsHiddenFiles])
            .filter(isMovie)
            .map { $0.standardizedFileURL }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    static func related(to url: URL) -> [URL] {
        let key = seriesKey(url)
        guard !key.isEmpty, let files = try? movies(in: url.deletingLastPathComponent()) else { return [url] }
        let matches = files.filter { seriesKey($0) == key }
        return matches.contains(url) ? matches : [url]
    }

    private static func seriesKey(_ url: URL) -> String {
        url.deletingPathExtension().lastPathComponent.lowercased()
            .replacingOccurrences(of: #"[\s._(\[\-]*(?:(?:part|pt|episode|ep|clip|vol|ch)[\s._\-]*)?\d+[)\]]?$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[\s._\-]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
