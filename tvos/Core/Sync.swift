import Foundation

// Sync with a StreamBoss sync server (see server/). The wire format and the merge rules are the same as the
// Flutter app's (lib/services/sync/), so a My List or a resume position made on a phone arrives here and back.
// Only the address, the e-mail and a token are ever sent; nothing about the provider but its address and login name.

/// How a synced value looks on the server: its type and value as JSON text, `{"t":"l","v":["a","b"]}`.
/// Types: s text, l list of texts (the others are not used by what the Apple TV syncs).
enum SyncCodec {
    private static func encode(_ obj: [String: Any]) -> String {
        let d = (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data()
        return String(decoding: d, as: UTF8.self)
    }

    private static func parse(_ s: String?) -> [String: Any]? {
        guard let s = s, let d = s.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    static func encodeList(_ list: [String]) -> String { encode(["t": "l", "v": list]) }

    static func decodeList(_ s: String?) -> [String]? {
        guard let j = parse(s), let v = j["v"] as? [Any] else { return nil }
        return v.map { "\($0)" }
    }

    static func encodeText(_ text: String) -> String { encode(["t": "s", "v": text]) }

    static func decodeText(_ s: String?) -> String? {
        guard let j = parse(s), let v = j["v"] as? String else { return nil }
        return v
    }

    /// A map of resume positions (item key -> milliseconds) is kept on the server as JSON text inside a text value.
    static func encodeMap(_ m: [String: Int]) -> String {
        let d = (try? JSONSerialization.data(withJSONObject: m, options: [.sortedKeys])) ?? Data()
        return encodeText(String(decoding: d, as: UTF8.self))
    }

    static func decodeMap(_ s: String?) -> [String: Int]? {
        guard let text = decodeText(s) else { return nil }
        guard let d = text.data(using: .utf8),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return [:] }
        var out: [String: Int] = [:]
        for (k, v) in o {
            if let n = v as? Int {
                out[k] = n
            } else if let n = v as? Double {
                out[k] = Int(n)
            }
        }
        return out
    }
}

/// Three-way merge of one synced preference: [base] is what this device saw at its last sync, [local] what it
/// holds now, [server] what the server holds; nil means it does not exist there. [hadBase] is false for a device
/// that never synced this key: then the server wins where the two disagree and the two sides are joined.
enum SyncMerge {
    /// A list without meaning in its order (My List): both devices' additions stay, a removal on one is a removal on both.
    static func list(base: [String]?, local: [String]?, server: [String]?, hadBase: Bool) -> [String]? {
        if server == nil && local == nil { return nil }
        let s = server ?? [], l = local ?? [], b = Set(base ?? [])
        if !hadBase { return s + l.filter { !s.contains($0) } }
        let removed = b.filter { !l.contains($0) }
        var out = s.filter { !removed.contains($0) }
        for e in l where !b.contains(e) && !out.contains(e) { out.append(e) }
        return out
    }

    /// An object whose entries are independent (resume positions): changes to different entries both stay.
    static func map(base: [String: Int]?, local: [String: Int]?, server: [String: Int]?, hadBase: Bool) -> [String: Int]? {
        if server == nil && local == nil { return nil }
        let s = server ?? [:], l = local ?? [:], b = base ?? [:]
        if !hadBase { return l.merging(s) { _, theirs in theirs } }
        var out = s
        for (k, v) in l where b[k] != v { out[k] = v }
        for k in b.keys where l[k] == nil { out.removeValue(forKey: k) }
        return out
    }
}

/// A source saved on another device, as the server holds it (the password is never there).
struct SyncedSource: Equatable {
    let name: String
    let type: SourceType
    let url: String
    let username: String

    /// The sources in the wire text of the `sources` preference (a list of JSON texts). Demo ones are left out.
    static func decode(_ wire: String?) -> [SyncedSource] {
        guard let list = SyncCodec.decodeList(wire) else { return [] }
        return list.compactMap { text in
            guard let d = text.data(using: .utf8),
                  let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
                  let name = o["name"] as? String,
                  let t = o["type"] as? String,
                  let type = SourceType(rawValue: t), type != .demo else { return nil }
            return SyncedSource(name: name, type: type, url: (o["url"] as? String) ?? "", username: (o["user"] as? String) ?? "")
        }
    }
}

/// What this device syncs: My List (item keys such as `movie:123`) and resume positions in milliseconds.
struct SyncState: Equatable {
    var favorites: [String] = []
    var positions: [String: Int] = [:]
}

struct SyncRemoteItem: Equatable {
    var value: String?
    var rev: Int
}

enum SyncPutResult {
    case ok(Int)
    case conflict(SyncRemoteItem)
}

/// The server, as far as the engine needs it (the app talks HTTP; the tests use a fake).
protocol SyncTransport {
    func fetch() async throws -> [String: SyncRemoteItem]
    func put(key: String, value: String?, base: Int) async throws -> SyncPutResult
}

/// What the server and this device agreed on for a key at the last sync.
struct SyncBaseEntry: Codable, Equatable {
    var rev: Int
    var value: String?
}

struct SyncOutcome {
    var state: SyncState
    var pulled: Int
    var pushed: Int
    /// The server's `sources` preference, for the "use a saved source" list.
    var sourcesWire: String?
}

/// Brings this device's My List and resume positions and the server's into step, key by key.
final class SyncEngine {
    static let favoritesKey = "favorites"
    static let positionsKey = "positions"
    private static let maxRounds = 4

    /// What each key looked like at the last sync; the caller keeps it between runs.
    private(set) var base: [String: SyncBaseEntry]

    init(base: [String: SyncBaseEntry] = [:]) { self.base = base }

    private func wire(_ key: String, _ s: SyncState) -> String? {
        let had = base[key]?.value != nil
        if key == Self.favoritesKey {
            return s.favorites.isEmpty && !had ? nil : SyncCodec.encodeList(s.favorites)
        }
        return s.positions.isEmpty && !had ? nil : SyncCodec.encodeMap(s.positions)
    }

    private func same(_ key: String, _ a: String?, _ b: String?) -> Bool {
        if a == nil || b == nil { return a == nil && b == nil }
        if key == Self.favoritesKey { return SyncCodec.decodeList(a) == SyncCodec.decodeList(b) }
        return SyncCodec.decodeMap(a) == SyncCodec.decodeMap(b)
    }

    private func merged(_ key: String, base b: String?, local: String?, server: String?, hadBase: Bool) -> String? {
        if key == Self.favoritesKey {
            return SyncMerge.list(base: SyncCodec.decodeList(b), local: SyncCodec.decodeList(local),
                                  server: SyncCodec.decodeList(server), hadBase: hadBase).map(SyncCodec.encodeList)
        }
        return SyncMerge.map(base: SyncCodec.decodeMap(b), local: SyncCodec.decodeMap(local),
                             server: SyncCodec.decodeMap(server), hadBase: hadBase).map(SyncCodec.encodeMap)
    }

    func run(local: SyncState, api: SyncTransport) async throws -> SyncOutcome {
        var remote = try await api.fetch()
        var state = local
        var pulled = 0, pushed = 0
        let keys = [Self.favoritesKey, Self.positionsKey]

        // One key: merge, store here what changed, and say whether the server needs the result.
        func settle(_ key: String) -> (send: Bool, wire: String?) {
            let r = remote[key]
            let b = base[key]
            let localWire = wire(key, state)
            let m = merged(key, base: b?.value, local: localWire, server: r?.value, hadBase: b != nil)
            if !same(key, m, localWire) {
                if key == Self.favoritesKey {
                    state.favorites = SyncCodec.decodeList(m) ?? []
                } else {
                    state.positions = SyncCodec.decodeMap(m) ?? [:]
                }
                pulled += 1
            }
            let need = !same(key, m, r?.value)
            if !need { base[key] = SyncBaseEntry(rev: r?.rev ?? 0, value: m) }
            return (need, m)
        }

        var toSend: [(key: String, wire: String?)] = []
        for key in keys {
            let s = settle(key)
            if s.send { toSend.append((key, s.wire)) }
        }

        for item in toSend {
            var value = item.wire
            rounds: for _ in 0..<Self.maxRounds {
                switch try await api.put(key: item.key, value: value, base: remote[item.key]?.rev ?? 0) {
                case .ok(let rev):
                    base[item.key] = SyncBaseEntry(rev: rev, value: value)
                    pushed += 1
                    break rounds
                case .conflict(let current):
                    // Another device wrote in the meantime: merge with what is there now and try again.
                    remote[item.key] = current
                    let s = settle(item.key)
                    if !s.send { break rounds }
                    value = s.wire
                }
            }
        }
        return SyncOutcome(state: state, pulled: pulled, pushed: pushed, sourcesWire: remote["sources"]?.value)
    }

    /// Forget what was synced (signing out): the next account starts as a new device would.
    func forget() { base = [:] }
}

/// A sync server's address as typed: `sync.example.com` becomes `https://sync.example.com`; a full address is
/// kept (http is for a server on your own network). Nil for something that cannot be an address.
enum SyncServer {
    static func normalize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        if !s.contains("://") { s = "https://" + s }
        guard let u = URL(string: s), let host = u.host, !host.isEmpty,
              u.scheme == "https" || u.scheme == "http" else { return nil }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}
