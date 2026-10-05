import SwiftUI

struct SetupView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 28) {
            Text("STREAMBOSS")
                .font(.system(size: 64, weight: .black))
                .foregroundStyle(Color(red: 1, green: 0.24, blue: 0.44))
            Text("Bring your own provider. We just play it.")
                .foregroundStyle(.secondary)

            if let e = model.error {
                Text(e).foregroundStyle(.red)
            }

            Picker("Source", selection: $model.source.type) {
                Text("Xtream").tag(SourceType.xtream)
                Text("M3U").tag(SourceType.m3u)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 700)

            VStack(spacing: 16) {
                TextField(model.source.type == .m3u ? "Playlist URL" : "Server URL (http://host:port)",
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
            }
        }
        .padding(60)
    }
}
