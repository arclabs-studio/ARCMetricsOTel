import Foundation

/// Checks the OTLP endpoint before anything is built.
///
/// `https` is always accepted. Plain `http` only for `localhost`, `127.0.0.1` or `::1`, or — in
/// Debug builds — when the configuration allows insecure transport. Anything else, a URL without
/// a host, a URL carrying a user name or password, or one with a query or fragment (even an empty
/// one) is rejected: it would travel with every export and end up in proxy logs. Send credentials
/// in ``OTelConfiguration/headers`` instead.
enum EndpointValidator {
    private static let loopbackHosts: Set = ["localhost", "127.0.0.1", "::1"]

    static func validate(_ url: URL, allowsInsecureTransport: Bool) throws(OTelBootstrapError) {
        guard let scheme = url.scheme?.lowercased(),
              let host = url.host(percentEncoded: false)?.lowercased(),
              !host.isEmpty,
              url.user(percentEncoded: true) == nil,
              url.password(percentEncoded: true) == nil,
              url.query(percentEncoded: true) == nil,
              url.fragment(percentEncoded: true) == nil else {
            throw .invalidEndpoint
        }
        #if DEBUG
        let honoursInsecureTransport = allowsInsecureTransport
        #else
        let honoursInsecureTransport = false
        #endif
        switch scheme {
        case "https":
            return
        case "http" where honoursInsecureTransport || loopbackHosts.contains(host):
            return
        case "http":
            throw .insecureEndpoint
        default:
            throw .invalidEndpoint
        }
    }
}
