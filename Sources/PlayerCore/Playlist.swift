import Foundation

enum Playlist {
    static func related(to url: URL, library: MovieLibrary) -> [URL] {
        let key = seriesKey(url)
        guard !key.isEmpty, let files = try? library.movies(in: url.deletingLastPathComponent()) else { return [url] }
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
