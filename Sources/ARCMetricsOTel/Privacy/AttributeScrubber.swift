import ARCMetrics

/// Removes or rewrites attributes before a record is created.
///
/// Every record's own attributes go through ``OTelConfiguration/attributeScrubber`` inside the
/// telemetry actor: span start and end attributes, events, MetricKit reports, lifecycle events and
/// screen views. `session.id` and `session.previous_id` are added afterwards, so a scrubber can
/// neither remove nor forge them. Resource attributes (`service.name`, …) are not scrubbed, and
/// neither are names — span names, event names and screen names — nor a span's error type: keep
/// those constant.
///
/// ```swift
/// let scrubber = AttributeScrubber.default.then(AttributeScrubber { attributes in
///     attributes.filter { !$0.key.hasPrefix("customer.") }
/// })
/// ```
public struct AttributeScrubber: Sendable {
    private let body: @Sendable (TraceAttributes) -> TraceAttributes

    /// Creates a scrubber that maps a record's attributes through `scrub`.
    ///
    /// It runs on the telemetry thread for every record: keep it fast.
    public init(_ scrub: @escaping @Sendable (TraceAttributes) -> TraceAttributes) {
        body = scrub
    }

    /// `attributes` after this scrubber.
    public func scrub(_ attributes: TraceAttributes) -> TraceAttributes {
        body(attributes)
    }

    /// A scrubber that applies this one, then `next`.
    public func then(_ next: AttributeScrubber) -> AttributeScrubber {
        AttributeScrubber { attributes in
            next.scrub(scrub(attributes))
        }
    }
}

// MARK: - Default

public extension AttributeScrubber {
    /// A best-effort backstop, built from OpenTelemetry's semantic conventions and Apple's App
    /// Privacy data types. It cannot recognise every key that holds personal data — `customer`,
    /// `ip` or `cookies_enabled` pass — so never put personal data in attributes, and add your own
    /// rules with ``then(_:)``.
    ///
    /// Keys are compared ignoring case. The default:
    ///
    /// - Drops OpenTelemetry's personal-data attributes: `user.email`, `user.full_name`,
    ///   `user.name`, `user.id`, `user.hash`, `enduser.id`, `enduser.pseudo.id` and
    ///   `geo.postal_code`, also under another namespace (`client.geo.postal_code`).
    /// - Drops an attribute when a word of its key — split on `.`, `_`, `-` and camelCase
    ///   boundaries, alone or joined with the next word — names contact information, a location,
    ///   a credential or a user id: `email`, `phone`, `address`, `lat`, `lon`, `latitude`,
    ///   `longitude`, `password`, `passwd`, `token`, `jwt`, `bearer`, `secret`, `authorization`,
    ///   `cookie`, `credential`, `credentials`, `apikey`, `privatekey` or `userid`. `user.email`,
    ///   `accessToken`, `x-api-key`, `user_id` and `geo.location.lat` are dropped;
    ///   `tokenizer.version` and `latency_ms` are kept. Standard keys such as `server.address` and
    ///   `client.address` are dropped too.
    /// - For `url.*` string values: replaces credentials with `REDACTED:REDACTED`, as the
    ///   semantic conventions require for `url.full`, and cuts the query and fragment. Drops
    ///   `url.query` and `url.fragment`.
    static let `default` = AttributeScrubber { attributes in
        var scrubbed: TraceAttributes = [:]
        for (key, value) in attributes {
            let lowercasedKey = key.lowercased()
            guard !DefaultRules.isDenied(key, lowercased: lowercasedKey) else { continue }
            scrubbed[key] = lowercasedKey.hasPrefix("url.") ? DefaultRules.scrubbedURL(value) : value
        }
        return scrubbed
    }
}

/// The rules behind ``AttributeScrubber/default``.
private enum DefaultRules {
    /// OpenTelemetry semantic-convention attributes that hold personal data.
    static let deniedKeys: Set<String> = ["user.email", "user.full_name", "user.name", "user.id", "user.hash",
                                          "enduser.id", "enduser.pseudo.id", "geo.postal_code", "url.query",
                                          "url.fragment"]

    /// Key words naming contact information, a location, a credential or a user id.
    static let deniedSegments: Set<String> = ["email", "phone", "address", "lat", "lon", "latitude", "longitude",
                                              "password", "passwd", "token", "jwt", "bearer", "secret", "authorization",
                                              "cookie",
                                              "credential", "credentials", "apikey", "privatekey", "userid"]

    static func isDenied(_ key: String, lowercased: String) -> Bool {
        if deniedKeys.contains(where: { lowercased == $0 || lowercased.hasSuffix("." + $0) }) {
            return true
        }
        let segments = key.split(whereSeparator: { $0 == "." || $0 == "_" || $0 == "-" })
        let words = segments.flatMap { camelCaseWords(of: $0) }.map { $0.lowercased() }
        // Adjacent words joined, so `api_key`, `x-api-key` and `userId` match `apikey` and `userid`.
        let joinedPairs = zip(words, words.dropFirst()).map { $0 + $1 }
        return (segments.map { $0.lowercased() } + words + joinedPairs).contains { deniedSegments.contains($0) }
    }

    /// `userEmail` → `user`, `Email`; `APIKey` → `API`, `Key`.
    static func camelCaseWords(of segment: Substring) -> [String] {
        var words: [String] = []
        var current = ""
        let characters = Array(segment)
        for (index, character) in characters.enumerated() {
            let startsWord = character.isUppercase && !current.isEmpty
                && (current.last?.isLowercase == true
                    || (index + 1 < characters.count && characters[index + 1].isLowercase))
            if startsWord {
                words.append(current)
                current = ""
            }
            current.append(character)
        }
        words.append(current)
        return words
    }

    /// A `url.*` value without credentials, query or fragment.
    static func scrubbedURL(_ value: TraceAttributeValue) -> TraceAttributeValue {
        guard case let .string(url) = value else {
            return value
        }
        let end = url.firstIndex { $0 == "?" || $0 == "#" } ?? url.endIndex
        return .string(redactingCredentials(in: String(url[..<end])))
    }

    /// `scheme://user:password@host/…` → `scheme://REDACTED:REDACTED@host/…`.
    static func redactingCredentials(in url: String) -> String {
        guard let schemeEnd = url.range(of: "://") else {
            return url
        }
        let authorityEnd = url[schemeEnd.upperBound...].firstIndex(of: "/") ?? url.endIndex
        let authority = url[schemeEnd.upperBound ..< authorityEnd]
        guard let at = authority.lastIndex(of: "@") else {
            return url
        }
        return url[..<schemeEnd.upperBound] + "REDACTED:REDACTED" + url[at...]
    }
}
