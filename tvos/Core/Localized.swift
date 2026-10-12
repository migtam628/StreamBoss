import Foundation

/// The text in the person's language. The English text is the key: SwiftUI's Text("..."), Button("...") and
/// TextField("...") look it up by themselves, and these two do the same for the plain strings in Core.
/// The translations are in tvos/i18n/strings.json (see tool/tvos_i18n.py, which CI runs).
func tr(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// Like `tr`, for a text with %lld (a number) or %@ (a piece of text) in it.
func trf(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), arguments: args)
}
