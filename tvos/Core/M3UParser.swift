import Foundation

/// Parses an extended M3U playlist. URLs containing /movie/ or /series/ are
/// treated as movies; everything else is live TV grouped by `group-title`.
enum M3UParser {
    static func parse(_ body: String) -> Library {
        var lib = Library()
        var attrs: [String: String] = [:]
        var name = ""
        var n = 0
        var liveCats: [String] = []
        var movieCats: [String] = []

        for raw in body.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("#EXTINF") {
                attrs = parseAttributes(line)
                if let comma = titleComma(line) {
                    name = String(line[line.index(after: comma)...]).trimmingCharacters(in: .whitespaces)
                } else {
                    name = ""
                }
                if name.isEmpty { name = attrs["tvg-name"] ?? "Channel \(n + 1)" }
            } else if !line.hasPrefix("#") {
                let group = (attrs["group-title"]?.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 } ?? "Other"
                let isVod = line.contains("/movie/") || line.contains("/series/")
                let item = MediaItem(
                    id: String(n),
                    name: name,
                    kind: isVod ? .movie : .live,
                    url: line,
                    poster: attrs["tvg-logo"],
                    categoryId: group
                )
                n += 1
                if isVod {
                    lib.movies.append(item)
                    if !movieCats.contains(group) { movieCats.append(group) }
                } else {
                    lib.live.append(item)
                    if !liveCats.contains(group) { liveCats.append(group) }
                }
                attrs = [:]
                name = ""
            }
        }
        lib.liveCategories = liveCats.map { MediaCategory(id: $0, name: $0) }
        lib.movieCategories = movieCats.map { MediaCategory(id: $0, name: $0) }
        return lib
    }

    /// First comma outside quotes: the title follows it.
    static func titleComma(_ line: String) -> String.Index? {
        var inQuote = false
        for i in line.indices {
            let c = line[i]
            if c == "\"" { inQuote.toggle() }
            else if c == "," && !inQuote { return i }
        }
        return nil
    }

    static func parseAttributes(_ line: String) -> [String: String] {
        var out: [String: String] = [:]
        guard let re = try? NSRegularExpression(pattern: "([\\w-]+)=\"([^\"]*)\"") else { return out }
        let ns = NSString(string: line)
        for m in re.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
            out[ns.substring(with: m.range(at: 1)).lowercased()] = ns.substring(with: m.range(at: 2))
        }
        return out
    }
}
