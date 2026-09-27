import Foundation

/// What a `claudebar://` URL asks the app to do.
///
/// The action is the URL's host (`claudebar://open`) or, when the URL is
/// written with three slashes, its path (`claudebar:///open`). Actions take
/// no parameters, so a URL with a query, a fragment or anything beyond the
/// action name is not an action. See docs/features/url-schemes/README.md.
enum URLSchemeAction: String, Equatable, Sendable {
    case open
    case refresh
    case settings

    static let scheme = "claudebar"

    init?(url: URL) {
        guard url.scheme?.caseInsensitiveCompare(Self.scheme) == .orderedSame,
              url.query == nil, url.fragment == nil
        else { return nil }
        let host = url.host ?? ""
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let name: String
        if host.isEmpty {
            name = path
        } else {
            guard path.isEmpty else { return nil }
            name = host
        }
        self.init(rawValue: name)
    }
}
