import Foundation
import SwiftUI

/// The sync account on this Apple TV: signing in, and keeping My List and resume positions in step with the
/// server (and so with the phone, tablet and computer apps). The token is in the keychain; the address and the
/// e-mail are plain preferences.
@MainActor
final class SyncModel: ObservableObject {
    @Published var server: String
    @Published var email: String
    @Published var signedIn: Bool
    @Published var busy = false
    @Published var message: String?
    @Published var lastSync: Date?
    /// The sources saved on other devices (without their passwords), to start from.
    @Published var sources: [SyncedSource] = []

    private let defaults = UserDefaults.standard
    private var engine: SyncEngine
    private var running = false
    private var pending: Task<Void, Never>?

    init() {
        server = defaults.string(forKey: "syncServer") ?? ""
        email = defaults.string(forKey: "syncEmail") ?? ""
        signedIn = Keychain.get("syncToken") != nil
        engine = SyncEngine(base: SyncModel.loadBase())
    }

    private static func loadBase() -> [String: SyncBaseEntry] {
        guard let d = UserDefaults.standard.data(forKey: "syncBase"),
              let b = try? JSONDecoder().decode([String: SyncBaseEntry].self, from: d) else { return [:] }
        return b
    }

    private func saveBase() {
        if let d = try? JSONEncoder().encode(engine.base) { defaults.set(d, forKey: "syncBase") }
    }

    func signIn(password: String, create: Bool, app: AppModel) async {
        guard !busy else { return }
        busy = true
        message = nil
        do {
            let api = try SyncApi(server: server)
            let r = try await api.signIn(email: email, password: password, create: create, device: "Apple TV")
            Keychain.set(r.token, for: "syncToken")
            server = api.base
            email = r.email
            defaults.set(server, forKey: "syncServer")
            defaults.set(email, forKey: "syncEmail")
            signedIn = true
            busy = false
            await sync(app: app)
        } catch {
            busy = false
            message = error.localizedDescription
        }
    }

    func signOut() async {
        if let t = Keychain.get("syncToken"), let api = try? SyncApi(server: server, token: t) { await api.signOut() }
        Keychain.set("", for: "syncToken")
        defaults.removeObject(forKey: "syncBase")
        engine = SyncEngine()
        signedIn = false
        sources = []
        lastSync = nil
        message = nil
    }

    /// Syncs now: sends what changed here, brings what changed elsewhere.
    func sync(app: AppModel) async {
        guard signedIn, !running, let token = Keychain.get("syncToken") else { return }
        running = true
        busy = true
        defer {
            running = false
            busy = false
        }
        do {
            let api = try SyncApi(server: server, token: token)
            let before = app.syncState()
            let out = try await engine.run(local: before, api: api)
            // Something changed here while the server was being asked: start over next time, so nothing is overwritten.
            if app.syncState() != before {
                engine = SyncEngine(base: SyncModel.loadBase())
                return
            }
            if out.pulled > 0 { app.apply(out.state) }
            saveBase()
            sources = SyncedSource.decode(out.sourcesWire)
            lastSync = Date()
            message = nil
        } catch let e as SyncError where e.signedOut {
            await signOut()
            message = tr("You were signed out. Sign in again.")
        } catch {
            engine = SyncEngine(base: SyncModel.loadBase())
            message = error.localizedDescription
        }
    }

    /// When the app opens: a change made here (My List, the end of a video) syncs soon, and now is a good time too.
    func start(app: AppModel) async {
        app.onChange = { [weak self, weak app] in
            guard let self = self, let app = app else { return }
            self.requestSync(app: app)
        }
        await sync(app: app)
    }

    /// A change was made here (My List, the end of a video): sync soon, once for a run of changes.
    func requestSync(app: AppModel) {
        guard signedIn else { return }
        pending?.cancel()
        pending = Task { [weak self, weak app] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled, let self = self, let app = app else { return }
            await self.sync(app: app)
        }
    }
}
