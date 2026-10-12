import SwiftUI

/// Sign in to (or create) the account on your own sync server.
struct SyncSignInView: View {
    @EnvironmentObject var sync: SyncModel
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""

    var body: some View {
        VStack(spacing: 24) {
            Text("Sync account").font(.title2)
            Text("Keep My List and where you stopped watching in step with your other devices, using your own sync server.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(spacing: 16) {
                TextField("Sync server address", text: $sync.server)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("E-mail", text: $sync.email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
            }
            .frame(maxWidth: 700)
            if let m = sync.message { Text(verbatim: m).foregroundStyle(.red) }
            if sync.busy { ProgressView() }
            HStack(spacing: 24) {
                Button("Sign in") { go(create: false) }
                Button("Create account") { go(create: true) }
                Button("Close") { dismiss() }
            }
        }
        .padding(60)
    }

    private func go(create: Bool) {
        Task {
            await sync.signIn(password: password, create: create, app: model)
            if sync.signedIn {
                password = ""
                dismiss()
            }
        }
    }
}

/// The sync section of Settings.
struct SyncSettings: View {
    @EnvironmentObject var sync: SyncModel
    @EnvironmentObject var model: AppModel
    @State private var showSignIn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sync").font(.headline)
            if sync.signedIn {
                Text(verbatim: sync.email).foregroundStyle(.secondary)
                if sync.lastSync != nil { Text("Synced").foregroundStyle(.secondary) }
                if let m = sync.message { Text(verbatim: m).foregroundStyle(.red) }
                HStack(spacing: 24) {
                    Button("Sync now") { Task { await sync.sync(app: model) } }
                    Button("Sign out of sync") { Task { await sync.signOut() } }
                }
            } else {
                Text("Keep My List and where you stopped watching in step with your other devices.")
                    .foregroundStyle(.secondary)
                Button("Sign in to sync") { showSignIn = true }
            }
        }
        .sheet(isPresented: $showSignIn) { SyncSignInView() }
    }
}
