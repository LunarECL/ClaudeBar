import Foundation

/// What a `claudebar://` URL asks the app to do.
///
/// The action is the URL's host (`claudebar://open`) or, when the URL is
/// written with three slashes, its path (`claudebar:///open`). Anything else
/// is not an action. See docs/features/url-schemes/README.md.
enum URLSchemeAction: String, Equatable, Sendable {
    case open
    case refresh
    case settings

    static let scheme = "claudebar"

    init?(url: URL) {
        guard url.scheme?.caseInsensitiveCompare(Self.scheme) == .orderedSame else { return nil }
        let host = url.host ?? ""
        let name = host.isEmpty
            ? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            : host
        self.init(rawValue: name)
    }
}
