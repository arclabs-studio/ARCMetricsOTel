import ARCMetrics
import Foundation
import Testing
@testable import ARCMetricsOTel

@Suite("AttributeScrubber URLs", .tags(.unit)) struct AttributeScrubberURLTests {
    private let sut = AttributeScrubber.default

    // MARK: URLs under any key

    struct URLCase: Sendable, CustomTestStringConvertible {
        let key: String
        let raw: String
        let expected: String
        var testDescription: String {
            "\(key)=\(raw) -> \(expected)"
        }
    }

    static let urlCases = [URLCase(key: "http.url", raw: "https://x.test/a?q=1#f", expected: "https://x.test/a"),
                           URLCase(key: "http.target", raw: "https://x.test/a/b?token=1",
                                   expected: "https://x.test/a/b"),
                           URLCase(key: "deeplink.url", raw: "myapp://open/item?id=7", expected: "myapp://open/item"),
                           URLCase(key: "link", raw: "https://x.test/a#section", expected: "https://x.test/a"),
                           URLCase(key: "link", raw: "https://user:pass@x.test/a",
                                   expected: "https://REDACTED:REDACTED@x.test/a"),
                           URLCase(key: "link", raw: "https://user@x.test/a?q=1",
                                   expected: "https://REDACTED:REDACTED@x.test/a"),
                           URLCase(key: "Referrer", raw: "HTTPS://u:p@x.test/a?q=1#f",
                                   expected: "HTTPS://REDACTED:REDACTED@x.test/a"),
                           URLCase(key: "origin", raw: "custom+scheme.v1://host/p?x=1",
                                   expected: "custom+scheme.v1://host/p"),
                           URLCase(key: "link", raw: "https://x.test/a", expected: "https://x.test/a")]

    @Test("A string value that starts with a scheme and :// is scrubbed as a URL, whatever its key",
          arguments: urlCases)
    func scrubsURLUnderAnyKey(_ testCase: URLCase) {
        let result = sut.scrub([testCase.key: .string(testCase.raw)])

        #expect(result == [testCase.key: .string(testCase.expected)])
    }

    @Test("mailto: and tel: values are replaced whole, under any key, whatever the case of the scheme",
          arguments: [("link", "mailto:jane@example.com", "mailto:REDACTED"),
                      ("contact.uri", "MAILTO:jane@example.com?subject=hi", "mailto:REDACTED"),
                      ("target", "tel:+34600111222", "tel:REDACTED"),
                      ("target", "Tel:+34600111222", "tel:REDACTED"),
                      ("url.full", "mailto:jane@example.com", "mailto:REDACTED")])
    func redactsMailtoAndTel(key: String, raw: String, expected: String) {
        #expect(sut.scrub([key: .string(raw)]) == [key: .string(expected)])
    }

    @Test("Strings that do not start with a scheme and :// are unchanged",
          arguments: ["note: see docs", "a value with :// in the middle", "see https://x.test/a?q=1",
                      "/path?a=1#f", "://no-scheme?a=1", "1http://x.test/a?q=1", "http//x.test/a?q=1",
                      "telephone: 555", "mailtoday", "what?", "a#b", ""]) func nonURLStringsUnchanged(value: String) {
        let input: TraceAttributes = ["note": .string(value), "http.route": .string(value)]

        #expect(sut.scrub(input) == input)
    }

    @Test("Non-string values under non-url keys are unchanged") func nonStringValuesUnchanged() {
        let input: TraceAttributes = ["http.status": 200, "retry": true, "ratio": 0.5]

        #expect(sut.scrub(input) == input)
    }

    // MARK: More contact schemes, redaction before cutting, wrapped values

    struct ScrubCase: Sendable, CustomTestStringConvertible {
        let raw: String
        let expected: String
        var testDescription: String {
            "\(raw) -> \(expected)"
        }
    }

    static let contactCases = [ScrubCase(raw: "sms:+34600111222", expected: "sms:REDACTED"),
                               ScrubCase(raw: "SMS:+34600111222?body=hi", expected: "sms:REDACTED"),
                               ScrubCase(raw: "facetime:a@b.c", expected: "facetime:REDACTED"),
                               ScrubCase(raw: "FaceTime:a@b.c", expected: "facetime:REDACTED"),
                               ScrubCase(raw: "facetime-audio:+34600111222", expected: "facetime-audio:REDACTED"),
                               ScrubCase(raw: "FACETIME-AUDIO:+34600111222", expected: "facetime-audio:REDACTED"),
                               ScrubCase(raw: "geo:41.38,2.17", expected: "geo:REDACTED"),
                               ScrubCase(raw: "GEO:41.38,2.17", expected: "geo:REDACTED")]

    @Test("sms:, facetime:, facetime-audio: and geo: values are replaced whole, under any key",
          arguments: contactCases, ["link", "url.full", "target"])
    func redactsMoreContactSchemes(_ testCase: ScrubCase, key: String) {
        #expect(sut.scrub([key: .string(testCase.raw)]) == [key: .string(testCase.expected)])
    }

    @Test("Values that merely resemble a contact scheme are unchanged",
          arguments: ["smsc", "geography", "facetimes", "sms", "geo", "smsc:abc", "geography:x",
                      "facetimes:x"]) func contactLookalikesUnchanged(value: String) {
        let input: TraceAttributes = ["note": .string(value)]

        #expect(sut.scrub(input) == input)
    }

    static let authorityCases = [ScrubCase(raw: "https://user:p?ss@host/a", expected: "https://REDACTED"),
                                 ScrubCase(raw: "https://user:p#ss@host/a", expected: "https://REDACTED"),
                                 ScrubCase(raw: "https://host?email=a@b.c", expected: "https://REDACTED"),
                                 ScrubCase(raw: "myapp://host#a@b", expected: "myapp://REDACTED"),
                                 ScrubCase(raw: "https://host/p?email=a@b.c", expected: "https://REDACTED"),
                                 ScrubCase(raw: "https://u:p@host/a?q=1",
                                           expected: "https://REDACTED:REDACTED@host/a"),
                                 ScrubCase(raw: "https://host/a/@me?x", expected: "https://REDACTED"),
                                 ScrubCase(raw: "https://host/a#frag@x", expected: "https://REDACTED")]

    @Test("A ? or # before the last @ of the authority redacts the whole authority, before anything is cut",
          arguments: authorityCases, ["url.full", "link"])
    func redactsBeforeCutting(_ testCase: ScrubCase, key: String) {
        #expect(sut.scrub([key: .string(testCase.raw)]) == [key: .string(testCase.expected)])
    }

    static let wrappedCases = [ScrubCase(raw: " https://u:p@h/a?token=1", expected: " https://REDACTED:REDACTED@h/a"),
                               ScrubCase(raw: "<https://h/a?x=1>", expected: "<https://h/a"),
                               ScrubCase(raw: "\"mailto:a@b.c\"", expected: "\"mailto:REDACTED"),
                               ScrubCase(raw: "<tel:+34600111222>", expected: "<tel:REDACTED"),
                               ScrubCase(raw: "\n\t <\"https://h/a#f", expected: "\n\t <\"https://h/a"),
                               ScrubCase(raw: "  <https://h/a>", expected: "  <https://h/a>"),
                               ScrubCase(raw: "<<sms:+34600111222", expected: "<<sms:REDACTED")]

    @Test("Leading whitespace, < and \" are ignored for detection and kept as a prefix",
          arguments: wrappedCases, ["link", "url.full"])
    func scrubsWrappedValues(_ testCase: ScrubCase, key: String) {
        #expect(sut.scrub([key: .string(testCase.raw)]) == [key: .string(testCase.expected)])
    }

    @Test("Wrapped values that are not URLs are unchanged",
          arguments: [" see https://h/a?q", "<b>bold</b>", "   ", "\"quoted text\"", "<>",
                      "\"\""]) func wrappedNonURLsUnchanged(value: String) {
        let input: TraceAttributes = ["note": .string(value)]

        #expect(sut.scrub(input) == input)
    }

    // MARK: Round 3

    static let colonThenAtCases = [ScrubCase(raw: "https://user:pa/ss@host/p", expected: "https://REDACTED"),
                                   ScrubCase(raw: "https://u:p/q?x@host", expected: "https://REDACTED"),
                                   ScrubCase(raw: "https://u:p/ss#x@h", expected: "https://REDACTED"),
                                   ScrubCase(raw: "https://host:8080/a?email=a@b", expected: "https://REDACTED"),
                                   ScrubCase(raw: "https://host:8080/a?x=1", expected: "https://host:8080/a"),
                                   ScrubCase(raw: "https://host/a/@me?x", expected: "https://REDACTED"),
                                   ScrubCase(raw: "https://u:p@host/a?q=1",
                                             expected: "https://REDACTED:REDACTED@host/a")]

    @Test("A colon in the authority with no @, and an @ later in the value, redacts the whole authority",
          arguments: colonThenAtCases, ["url.full", "link"])
    func redactsColonThenAt(_ testCase: ScrubCase, key: String) {
        #expect(sut.scrub([key: .string(testCase.raw)]) == [key: .string(testCase.expected)])
    }

    static let moreContactCases = [ScrubCase(raw: "telprompt:+34600111222", expected: "telprompt:REDACTED"),
                                   ScrubCase(raw: "TelPrompt://+34600111222", expected: "telprompt:REDACTED"),
                                   ScrubCase(raw: "smsto:+34600111222:hi", expected: "smsto:REDACTED"),
                                   ScrubCase(raw: "SMSTO:+34600111222", expected: "smsto:REDACTED"),
                                   ScrubCase(raw: "callto:jane", expected: "callto:REDACTED"),
                                   ScrubCase(raw: "CallTo:jane", expected: "callto:REDACTED"),
                                   ScrubCase(raw: "facetime-prompt:a@b.c", expected: "facetime-prompt:REDACTED"),
                                   ScrubCase(raw: "FACETIME-PROMPT:a@b.c", expected: "facetime-prompt:REDACTED")]

    @Test("telprompt:, smsto:, callto: and facetime-prompt: values are replaced whole, under any key",
          arguments: moreContactCases, ["link", "url.full", "target"])
    func redactsEvenMoreContactSchemes(_ testCase: ScrubCase, key: String) {
        #expect(sut.scrub([key: .string(testCase.raw)]) == [key: .string(testCase.expected)])
    }

    @Test("Values that merely resemble the additional contact schemes are unchanged",
          arguments: ["telprompts:x", "callton:x", "smstoo:x", "facetime-prompts:x", "telprompt", "callto", "smsto"])
    func moreContactLookalikesUnchanged(value: String) {
        let input: TraceAttributes = ["note": .string(value)]

        #expect(sut.scrub(input) == input)
    }

    static let moreWrapperCases = [ScrubCase(raw: "'https://u:p@h/a?x'", expected: "'https://REDACTED:REDACTED@h/a"),
                                   ScrubCase(raw: "(mailto:a@b)", expected: "(mailto:REDACTED"),
                                   ScrubCase(raw: "[tel:+1555]", expected: "[tel:REDACTED"),
                                   ScrubCase(raw: "\u{200B}https://h/a?q", expected: "\u{200B}https://h/a"),
                                   ScrubCase(raw: "\u{FEFF}sms:+1", expected: "\u{FEFF}sms:REDACTED"),
                                   ScrubCase(raw: " ('[\u{200B}\u{FEFF}<\"https://h/a#f",
                                             expected: " ('[\u{200B}\u{FEFF}<\"https://h/a")]

    @Test("Leading ', (, [, U+200B and U+FEFF are ignored for detection and kept as a prefix",
          arguments: moreWrapperCases, ["link", "url.full"])
    func scrubsMoreWrappedValues(_ testCase: ScrubCase, key: String) {
        #expect(sut.scrub([key: .string(testCase.raw)]) == [key: .string(testCase.expected)])
    }

    @Test("Wrapped text that is not a URL is unchanged",
          arguments: ["(see docs)", "[note]", "'quoted'", "('[", "\u{200B}\u{FEFF}",
                      "(see https://h/a?q)"]) func moreWrappedNonURLsUnchanged(value: String) {
        let input: TraceAttributes = ["note": .string(value)]

        #expect(sut.scrub(input) == input)
    }

    static let schemelessCases = [ScrubCase(raw: "u:p@h/x", expected: "REDACTED:REDACTED@h/x"),
                                  ScrubCase(raw: "//u:p@h/x?q", expected: "//REDACTED:REDACTED@h/x"),
                                  ScrubCase(raw: "h/x?q=1", expected: "h/x"),
                                  ScrubCase(raw: "/users/@me", expected: "REDACTED"),
                                  ScrubCase(raw: "/a/b?x=1", expected: "/a/b")]

    @Test("url.* values without :// get the same credential rules, on the text before the first /, ? or #",
          arguments: schemelessCases, ["url.full", "url.original", "url.path"])
    func redactsSchemelessURLCredentials(_ testCase: ScrubCase, key: String) {
        #expect(sut.scrub([key: .string(testCase.raw)]) == [key: .string(testCase.expected)])
    }

    @Test("Scheme-less credentials are only redacted under url.* keys",
          arguments: ["u:p@h/x", "//u:p@h/x", "jane@example.com", "a:b@c"])
    func schemelessUnchangedOutsideURLKeys(value: String) {
        let input: TraceAttributes = ["note": .string(value)]

        #expect(sut.scrub(input) == input)
    }
}
