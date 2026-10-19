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
    /// - For URLs — every `url.*` string value, and any string value under any key that starts with
    ///   a scheme followed by `://` (`http.url`, `deeplink.url`, `link`): replaces credentials with
    ///   `REDACTED:REDACTED`, as the semantic conventions require for `url.full`, and cuts the query
    ///   and fragment. A `url.*` value without a scheme (`//user:pw@host`, `user:pw@host`) gets the
    ///   same treatment. When the credentials' end is ambiguous — a `?` or `#` before the
    ///   authority's last `@`, or any `@` after the authority — everything after `scheme://`
    ///   becomes `REDACTED`. Drops `url.query` and `url.fragment`.
    /// - Replaces a `mailto:`, `tel:`, `telprompt:`, `callto:`, `sms:`, `smsto:`, `facetime:`,
    ///   `facetime-audio:`, `facetime-prompt:`, `geo:`, `sip:`, `sips:`, `xmpp:` or `im:` value,
    ///   under any key, with `<scheme>:REDACTED`.
    /// - Skips leading whitespace, `<`, `"`, `'`, `(`, `[`, `` ` `` and zero-width characters
    ///   (U+200B, U+200C, U+200D, U+2060, U+FEFF) when detecting a URL or contact scheme, and keeps
    ///   them in front of the scrubbed value.
    static let `default` = AttributeScrubber { attributes in
        var scrubbed: TraceAttributes = [:]
        for (key, value) in attributes {
            let lowercasedKey = key.lowercased()
            guard !DefaultRules.isDenied(key, lowercased: lowercasedKey) else { continue }
            scrubbed[key] = DefaultRules.scrubbed(value, isURLKey: lowercasedKey.hasPrefix("url."))
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

    /// URI schemes whose whole value is personal data.
    static let contactSchemes = ["mailto", "tel", "telprompt", "callto", "sms", "smsto", "facetime",
                                 "facetime-audio", "facetime-prompt", "geo", "sip", "sips", "xmpp", "im"]

    /// Characters that often wrap a value (`<https://…>`, `"mailto:…"`, `(tel:…)`, `` `…` ``), and
    /// invisible ones that can lead it: zero-width space, non-joiner and joiner, word joiner and
    /// byte-order mark.
    static let wrapperScalars: Set<Unicode.Scalar> = ["<", "\"", "'", "(", "[", "`",
                                                      "\u{200B}", "\u{200C}", "\u{200D}", "\u{2060}", "\u{FEFF}"]

    /// Whether `character` is skipped when detecting a URL or contact scheme; it is kept in the
    /// result. Checked per scalar: a joiner merges with the character before it into one `Character`.
    static func isWrapper(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { $0.properties.isWhitespace || wrapperScalars.contains($0) }
    }

    /// `value` with any URL in it scrubbed. A string is a URL when its key is `url.*` or when it
    /// starts with a scheme and `://`; a contact-scheme value (`mailto:`, `tel:`, …) is replaced
    /// whole. Leading wrapper characters are skipped for detection and kept in the result.
    static func scrubbed(_ value: TraceAttributeValue, isURLKey: Bool) -> TraceAttributeValue {
        guard case let .string(string) = value else {
            return value
        }
        let bodyStart = string.firstIndex { !isWrapper($0) } ?? string.endIndex
        let prefix = String(string[..<bodyStart])
        let body = String(string[bodyStart...])
        let lowercasedBody = body.lowercased()
        if let scheme = contactSchemes.first(where: { lowercasedBody.hasPrefix($0 + ":") }) {
            return .string(prefix + scheme + ":REDACTED")
        }
        guard isURLKey || schemeSeparator(in: body) != nil else {
            return value
        }
        return .string(prefix + scrubbedURL(body))
    }

    /// The `://` after a leading scheme, a scheme being a letter followed by letters, digits, `+`,
    /// `.` or `-` (RFC 3986); `nil` when `string` does not start with one.
    static func schemeSeparator(in string: String) -> Range<String.Index>? {
        guard let separator = string.range(of: "://"),
              let first = string.first,
              first.isASCII,
              first.isLetter else {
            return nil
        }
        let isScheme = string[..<separator.lowerBound].allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || "+.-".contains(character))
        }
        return isScheme ? separator : nil
    }

    /// Where the authority starts: after `scheme://`, after a leading `//`, or at the start of a
    /// `url.*` value with neither.
    static func authorityStart(of url: String) -> String.Index {
        if let separator = schemeSeparator(in: url) {
            return separator.upperBound
        }
        return url.hasPrefix("//") ? url.index(url.startIndex, offsetBy: 2) : url.startIndex
    }

    /// `url` without credentials, query or fragment.
    ///
    /// Two shapes hide where the credentials end, so everything after the scheme (or `//`) is
    /// redacted instead of cut:
    /// - a `?` or `#` before the authority's last `@` (`https://user:p?ss@host`);
    /// - an `@` anywhere after the authority (`https://user:pa/ss@host`, `https://tok/en@host`,
    ///   `https://user:p@ss/word@host`), where a credential holds a `/`. This also redacts an `@`
    ///   in an ordinary path, query or fragment (`https://host/@me`, `?email=a@b`), which is
    ///   accepted for a backstop.
    static func scrubbedURL(_ url: String) -> String {
        let start = authorityStart(of: url)
        let authorityEnd = url[start...].firstIndex(of: "/") ?? url.endIndex
        let authority = url[start ..< authorityEnd]
        let delimiterInUserInfo = authority.lastIndex(of: "@").map { at in
            authority[..<at].contains { $0 == "?" || $0 == "#" }
        } ?? false
        if delimiterInUserInfo || url[authorityEnd...].contains("@") {
            return url[..<start] + "REDACTED"
        }
        let end = url.firstIndex { $0 == "?" || $0 == "#" } ?? url.endIndex
        return redactingCredentials(in: String(url[..<end]))
    }

    /// `scheme://user:password@host/…` → `scheme://REDACTED:REDACTED@host/…`; also without a
    /// scheme (`//user:password@host`, `user:password@host`).
    static func redactingCredentials(in url: String) -> String {
        let start = authorityStart(of: url)
        let authorityEnd = url[start...].firstIndex(of: "/") ?? url.endIndex
        guard let at = url[start ..< authorityEnd].lastIndex(of: "@") else {
            return url
        }
        return url[..<start] + "REDACTED:REDACTED" + url[at...]
    }
}
