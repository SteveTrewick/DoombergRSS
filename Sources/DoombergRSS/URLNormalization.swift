import Foundation

enum URLNormalizer {
    private static let trackingParams: Set<String> = [
        "gclid",
        "gbraid",
        "wbraid",
        "fbclid",
        "mc_cid",
        "mc_eid",
        "igshid",
        "msclkid",
        "yclid",
        "vero_id",
        "ref",
        "ref_src"
    ]

    static func normalize(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        if let scheme = components.scheme {
            components.scheme = scheme.lowercased()
        }
        if let host = components.host {
            components.host = host.lowercased()
        }

        components.fragment = nil

        if let port = components.port, let scheme = components.scheme {
            if (scheme == "http" && port == 80) || (scheme == "https" && port == 443) {
                components.port = nil
            }
        }

        if let queryItems = components.queryItems {
            let filtered = queryItems.filter { item in
                let name = item.name.lowercased()
                if name.hasPrefix("utm_") {
                    return false
                }
                return !trackingParams.contains(name)
            }
            let sorted = filtered.sorted {
                if $0.name == $1.name {
                    return ($0.value ?? "") < ($1.value ?? "")
                }
                return $0.name < $1.name
            }
            components.queryItems = sorted.isEmpty ? nil : sorted
        }

        return components.url ?? url
    }
}
