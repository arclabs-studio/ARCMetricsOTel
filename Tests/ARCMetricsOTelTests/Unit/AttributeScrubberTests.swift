import ARCMetrics
import Foundation
import Testing
@testable import ARCMetricsOTel

@Suite("Attribute scrubber", .tags(.unit), .timeLimit(.minutes(1))) struct AttributeScrubberTests {
    /// Every key the package emits on its own, as literals: the scrubber must never remove one.
    private static let packageKeys = ["session.id", "session.previous_id", "error.type",
                                      "exception.type", "exception.signal", "exception.termination_reason",
                                      "app.hang.duration_s", "ios.app.state", "app.screen.name",
                                      "metrickit.memory.peak_memory_usage",
                                      "metrickit.memory.suspended_memory_average",
                                      "metrickit.cpu.cpu_time", "metrickit.gpu.time",
                                      "metrickit.app_time.foreground_time", "metrickit.app_time.background_time",
                                      "metrickit.network_transfer.cellular_download",
                                      "metrickit.network_transfer.cellular_upload",
                                      "metrickit.network_transfer.wifi_download",
                                      "metrickit.network_transfer.wifi_upload",
                                      "metrickit.diskio.logical_write_count",
                                      "metrickit.app_responsiveness.hang_time_total_s",
                                      "metrickit.app_launch.time_to_first_draw_average_s",
                                      "metrickit.animation.hitch_time_ratio_ms_per_s",
                                      "metrickit.animation.scroll_hitch_time_ratio_ms_per_s"]

    private let sut = AttributeScrubber.default

    // MARK: Denylist

    @Test("A key with a denylisted segment is dropped, whatever the separator or case",
          arguments: ["user.email", "auth_token", "geo.lat", "geo.lon", "Authorization", "server.address",
                      "user-phone", "PASSWORD", "client_secret", "user.phone_number", "x-user.Email_id",
                      "email", "contact.EMAIL.primary", "email_", "geo.location.latitude",
                      "location.longitude", "http.cookie", "aws_credentials", "credential", "apikey",
                      "userEmail", "accessToken", "phoneNumber", "homeAddress", "geoLatitude", "APIKey.value",
                      "api_key", "api-key", "api.key", "x-api-key", "http.request.header.x-api-key", "user_id",
                      "userId", "userID", "passwd", "jwt", "bearer", "private_key", "privateKey"])
    func dropsDeniedKey(key: String) {
        // Given an attribute whose key has a denylisted segment
        let input: TraceAttributes = [key: "value"]

        // When scrubbed by default
        let result = sut.scrub(input)

        // Then it is gone
        #expect(result.isEmpty)
    }

    @Test("A denylisted key is dropped whatever the value type",
          arguments: [TraceAttributeValue.string("x"), 7, 41.4, true])
    func dropsRegardlessOfValueType(value: TraceAttributeValue) {
        #expect(sut.scrub(["geo.lat": value, "geo.lon": value]).isEmpty)
    }

    @Test("Near-miss keys survive because only whole segments are matched",
          arguments: ["tokenizer.version", "latency_ms", "translation.lang", "emails_sent", "addressbook.count",
                      "phones", "secrets.count", "passwords_checked", "authorizations", "app.screen.name",
                      "slon", "tokens", "tokenizerVersion", "latencyMs", "cookies_enabled", "service.name",
                      "user.roles", "user.names_count", "api.version", "key.count", "user.count",
                      "private.mode"]) func keepsNearMiss(key: String) {
        let input: TraceAttributes = [key: "value"]

        #expect(sut.scrub(input) == input)
    }

    @Test("OpenTelemetry's personal-data attributes are dropped by name",
          arguments: ["user.email", "user.full_name", "user.name", "user.id", "user.hash", "enduser.id",
                      "enduser.pseudo.id", "geo.postal_code",
                      "client.geo.postal_code"]) func dropsSemconvPersonalData(key: String) {
        #expect(sut.scrub([key: "value"]).isEmpty)
    }

    @Test("Only the offending attributes are dropped; the rest keep their values and types") func dropsOnlyOffenders() {
        let input: TraceAttributes = ["user.email": "a@b.test", "plan": "pro", "retries": 3, "ratio": 0.5,
                                      "cached": true, "auth_token": "abc", "geo.lat": 40.4]

        let result = sut.scrub(input)

        #expect(result == ["plan": "pro", "retries": 3, "ratio": 0.5, "cached": true])
    }

    @Test("Empty attributes stay empty") func emptyStaysEmpty() {
        #expect(sut.scrub([:]).isEmpty)
    }

    // MARK: URLs

    @Test("A url.* string value is cut at the first query or fragment marker",
          arguments: [("https://x.test/a?q=1#f", "https://x.test/a"),
                      ("/path#frag", "/path"),
                      ("/path?a=1?b=2", "/path"),
                      ("/path#frag?notquery", "/path"),
                      ("https://x.test/a/b", "https://x.test/a/b"),
                      ("?only=query", ""),
                      ("", "")])
    func cutsURLValue(raw: String, expected: String) {
        let result = sut.scrub(["url.full": .string(raw), "url.path": .string(raw)])

        #expect(result == ["url.full": .string(expected), "url.path": .string(expected)])
    }

    @Test("Credentials in a url.* value are replaced with REDACTED, as OpenTelemetry's semantic conventions require",
          arguments: [("https://user:pass@x.test/a?q=1", "https://REDACTED:REDACTED@x.test/a"),
                      ("https://user@x.test/a", "https://REDACTED:REDACTED@x.test/a"),
                      ("https://user:p%40ss@x.test:8443/a#f", "https://REDACTED:REDACTED@x.test:8443/a"),
                      ("https://user:pass@x.test", "https://REDACTED:REDACTED@x.test"),
                      ("https://x.test/a@b", "https://x.test/a@b")])
    func redactsURLCredentials(raw: String, expected: String) {
        #expect(sut.scrub(["url.full": .string(raw)]) == ["url.full": .string(expected)])
    }

    @Test("url.* keys are matched whatever their case") func urlKeysIgnoreCase() {
        let result = sut.scrub(["URL.Full": "https://u:p@x.test/a?q=1", "Url.Query": "q=1"])

        #expect(result == ["URL.Full": "https://REDACTED:REDACTED@x.test/a"])
    }

    @Test("url.query and url.fragment are dropped entirely", arguments: ["url.query", "url.fragment"])
    func dropsQueryAndFragmentKeys(key: String) {
        #expect(sut.scrub([key: "q=1", "url.path": "/a"]) == ["url.path": "/a"])
    }

    @Test("Non-string url.* values are unchanged") func nonStringURLValuesUnchanged() {
        let input: TraceAttributes = ["url.status": 200, "url.cached": true, "url.ratio": 0.5]

        #expect(sut.scrub(input) == input)
    }

    @Test("Keys outside the url. prefix keep a ? or # in their value",
          arguments: [("note", "what?"), ("search.term", "a#b"), ("urlish.value", "a?b"), ("myurl.full", "/a?b=1")])
    func nonURLKeysKeepMarkers(key: String, value: String) {
        let input: TraceAttributes = [key: .string(value)]

        #expect(sut.scrub(input) == input)
    }

    @Test("A url.* key that also has a denylisted segment is dropped", arguments: ["url.token", "url.address"])
    func deniedURLKeyDropped(key: String) {
        #expect(sut.scrub([key: "/a"]).isEmpty)
    }

    // MARK: Allowlist

    @Test("Every key the package emits survives the default scrubber unchanged", arguments: Self.packageKeys)
    func packageKeysSurvive(key: String) {
        let input: TraceAttributes = [key: 1.5]

        #expect(sut.scrub(input) == input)
    }

    // MARK: Custom and composed

    @Test("A custom scrubber applies its closure") func customClosureApplies() {
        let scrubber = AttributeScrubber { attributes in
            attributes.filter { $0.key != "drop.me" }.merging(["added": true]) { _, new in new }
        }

        #expect(scrubber.scrub(["drop.me": 1, "keep": 2]) == ["keep": 2, "added": true])
    }

    @Test("then applies self first, then the next scrubber") func thenAppliesInOrder() {
        let adder = AttributeScrubber { $0.merging(["marker": "on"]) { _, new in new } }
        let dropper = AttributeScrubber { $0.filter { $0.key != "marker" } }

        // Adding then dropping removes the key; dropping then adding leaves it
        #expect(adder.then(dropper).scrub(["a": 1]) == ["a": 1])
        #expect(dropper.then(adder).scrub(["a": 1]) == ["a": 1, "marker": "on"])
    }

    @Test("A scrubber chained after .default sees already-scrubbed input") func chainSeesDefaultOutput() {
        let probe = AttributeScrubber { attributes in
            attributes.merging(["saw.email": .bool(attributes["user.email"] != nil),
                                "saw.plan": .bool(attributes["plan"] != nil)]) { _, new in new }
        }

        let result = AttributeScrubber.default.then(probe).scrub(["user.email": "a@b.test", "plan": "pro"])

        #expect(result == ["plan": "pro", "saw.email": false, "saw.plan": true])
    }

    // MARK: Configuration

    @Test("OTelConfiguration scrubs with .default unless told otherwise") func configurationDefault() throws {
        let configuration = try TestConfiguration.make()

        #expect(configuration.attributeScrubber.scrub(["user.email": "a@b.test", "plan": "pro"]) == ["plan": "pro"])
    }

    @Test("OTelConfiguration keeps the scrubber it is given") func configurationCustom() throws {
        let configuration = try TestConfiguration.make(attributeScrubber: AttributeScrubber { _ in ["only": 1] })

        #expect(configuration.attributeScrubber.scrub(["user.email": "a@b.test"]) == ["only": 1])
    }
}
