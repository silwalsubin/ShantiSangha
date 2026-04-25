import Foundation

/// Parses Friends invite links — both `shantisangha://invite/{token}` and
/// `https://shantisangha.com/invite/{token}` Universal Link forms.
enum FriendsDeepLink {
    static func parse(_ url: URL) -> String? {
        if url.scheme == "shantisangha", url.host == "invite" {
            let comps = url.pathComponents.filter { $0 != "/" }
            return comps.first
        }
        if url.scheme == "shantisangha" {
            // shantisangha://invite/{token}
            let parts = url.absoluteString.replacingOccurrences(of: "shantisangha://", with: "")
            let comps = parts.split(separator: "/").map(String.init)
            if comps.count == 2, comps[0] == "invite" { return comps[1] }
        }
        if url.scheme == "https", url.host == "shantisangha.com" {
            let comps = url.pathComponents
            // ["/", "invite", "{token}"]
            if comps.count >= 3, comps[1] == "invite" {
                let token = comps[2]
                if !token.isEmpty { return token }
            }
        }
        return nil
    }
}
