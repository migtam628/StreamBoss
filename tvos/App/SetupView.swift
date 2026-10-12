import SwiftUI

struct SetupView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var sync: SyncModel
    @State private var showSignIn = false

    var body: some View {
        VStack(spacing: 28) {
            Text(verbatim: "STREAMBOSS")
                .font(.system(size: 64, weight: .black))
                .foregroundStyle(Color(red: 1, green: 0.24, blue: 0.44))
            Text("Bring your own provider. We just play it.")
                .foregroundStyle(.secondary)

            if let e = model.error {
                Text(e).foregroundStyle(.red)
            }

            Picker("Source", selection: $model.source.type) {
                Text(verbatim: "Xtream").tag(SourceType.xtream)
                Text(verbatim: "M3U").tag(SourceType.m3u)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 700)

            VStack(spacing: 16) {
                TextField(model.source.type == .m3u ? LocalizedStringKey("Playlist URL") : LocalizedStringKey("Server URL (http://host:port)"),
                          text: $model.source.url)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if model.source.type == .xtream {
                    TextField("Username", text: $model.source.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $model.source.password)
                }
            }
            .frame(maxWidth: 700)

            HStack(spacing: 24) {
                Button("Connect") { Task { await model.connect() } }
                Button("Try demo") { Task { await model.useDemo() } }
                if !sync.signedIn { Button("Use my sync account") { showSignIn = true } }
            }

            if sync.signedIn && !sync.sources.isEmpty {
                VStack(spacing: 12) {
                    Text("From your sync account").foregroundStyle(.secondary)
                    Text("Sources come without their password: pick one, type the password, then Connect.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(sync.sources, id: \.name) { s in
                                Button {
                                    model.source = Source(type: s.type, url: s.url, username: s.username, password: "")
                                } label: {
                                    Text(verbatim: s.name)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .padding(60)
        .sheet(isPresented: $showSignIn) { SyncSignInView() }
    }
}
