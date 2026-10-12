import Foundation

/// What the sync server said, in words a person can read.
struct SyncError: LocalizedError {
    let message: String
    /// The server refused the token: the account has to be signed in again.
    var signedOut = false
    var errorDescription: String? { message }
}

/// Talks to a StreamBoss sync server (see server/) over HTTP; the rules for what is synced are in Core/Sync.swift.
final class SyncApi: SyncTransport {
    let base: String
    var token: String?

    init(server: String, token: String? = nil) throws {
        guard let b = SyncServer.normalize(server) else {
            throw SyncError(message: tr("That does not look like a server address."))
        }
        base = b
        self.token = token
    }

    private func call(_ method: String, _ path: String, body: [String: Any]? = nil, auth: Bool = true) async throws -> (Int, [String: Any]?) {
        guard let url = URL(string: base + path) else {
            throw SyncError(message: tr("That does not look like a server address."))
        }
        var req = URLRequest(url: url, timeoutInterval: 25)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        if auth, let t = token { req.setValue("Bearer \(t)", forHTTPHeaderField: "authorization") }
        if let body = body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        do {
            let (data, res) = try await URLSession.shared.data(for: req)
            let status = (res as? HTTPURLResponse)?.statusCode ?? 0
            return (status, (try? JSONSerialization.jsonObject(with: data)) as? [String: Any])
        } catch {
            throw SyncError(message: tr("Could not reach the sync server. Check the address and that you are online."))
        }
    }

    private func failure(_ status: Int, _ json: [String: Any]?) -> SyncError {
        SyncError(message: (json?["error"] as? String) ?? tr("The sync server answered with an error."), signedOut: status == 401)
    }

    /// Signs in (or creates the account) and keeps the token. Returns the token and the e-mail.
    func signIn(email: String, password: String, create: Bool, device: String) async throws -> (token: String, email: String) {
        let (status, json) = try await call("POST", create ? "/api/register" : "/api/login",
                                            body: ["email": email.trimmingCharacters(in: .whitespaces), "password": password, "device": device],
                                            auth: false)
        guard status == 200 || status == 201, let t = json?["token"] as? String else { throw failure(status, json) }
        token = t
        return (t, (json?["email"] as? String) ?? email)
    }

    func signOut() async {
        _ = try? await call("POST", "/api/logout", body: [:])
        token = nil
    }

    func fetch() async throws -> [String: SyncRemoteItem] {
        let (status, json) = try await call("GET", "/api/data")
        guard status == 200 else { throw failure(status, json) }
        var out: [String: SyncRemoteItem] = [:]
        for (key, v) in (json?["items"] as? [String: Any]) ?? [:] {
            guard let item = v as? [String: Any], let rev = item["rev"] as? Int else { continue }
            out[key] = SyncRemoteItem(value: item["value"] as? String, rev: rev)
        }
        return out
    }

    func put(key: String, value: String?, base rev: Int) async throws -> SyncPutResult {
        var body: [String: Any] = ["base": rev]
        if let v = value { body["value"] = v } else { body["value"] = NSNull() }
        let name = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
        let (status, json) = try await call("PUT", "/api/data/" + name, body: body)
        if status == 200, let r = json?["rev"] as? Int { return .ok(r) }
        if status == 409 {
            return .conflict(SyncRemoteItem(value: json?["value"] as? String, rev: (json?["rev"] as? Int) ?? 0))
        }
        throw failure(status, json)
    }
}
