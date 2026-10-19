import ARCMetrics
import Foundation
import Testing
@testable import ARCMetricsOTel

@Suite("AttributeScrubber leaks", .tags(.unit)) struct AttributeScrubberLeakTests {
    private let sut = AttributeScrubber.default

    struct LeakCase: Sendable, CustomTestStringConvertible {
        let key: String
        let raw: String
        let expected: String
        /// Pieces of the input that must not survive in the output.
        let secrets: [String]
        var testDescription: String {
            "\(key)=\(raw) -> \(expected)"
        }
    }

    // MARK: An @ after the authority

    static let anyAtCases = [LeakCase(key: "url.full", raw: "https://ab/cd+ef@github.com/org/repo",
                                      expected: "https://REDACTED", secrets: ["ab/", "cd+ef", "github", "repo"]),
                             LeakCase(key: "link", raw: "https://ab/cd+ef@github.com/org/repo",
                                      expected: "https://REDACTED", secrets: ["ab/", "cd+ef", "github", "repo"]),
                             LeakCase(key: "url.full", raw: "https://to#k/en@host",
                                      expected: "https://REDACTED", secrets: ["to#k", "k/en", "host"]),
                             LeakCase(key: "link", raw: "https://to#k/en@host",
                                      expected: "https://REDACTED", secrets: ["to#k", "k/en", "host"]),
                             LeakCase(key: "url.full", raw: "//ab/cd@host/x",
                                      expected: "//REDACTED", secrets: ["ab/", "cd@", "host"]),
                             LeakCase(key: "url.full", raw: "https://user:p@ss/word@host/x",
                                      expected: "https://REDACTED", secrets: ["user", "p@ss", "word", "host"]),
                             LeakCase(key: "link", raw: "https://user:p@ss/word@host/x",
                                      expected: "https://REDACTED", secrets: ["user", "p@ss", "word", "host"])]

    @Test("An @ anywhere after the authority redacts the whole value, and no secret character survives",
          arguments: anyAtCases)
    func redactsWhenAtFollowsTheAuthority(_ testCase: LeakCase) {
        let result = sut.scrub([testCase.key: .string(testCase.raw)])

        #expect(result == [testCase.key: .string(testCase.expected)])
        guard case let .string(output)? = result[testCase.key] else {
            Issue.record("the value disappeared or changed type")
            return
        }
        for secret in testCase.secrets {
            #expect(!output.contains(secret), "\(secret) survived in \(output)")
        }
    }

    static let anyAtGuards = [AttributeScrubberURLTests.ScrubCase(raw: "https://u:p@host/a?q=1",
                                                                  expected: "https://REDACTED:REDACTED@host/a"),
                              AttributeScrubberURLTests.ScrubCase(raw: "https://host:8080/a?x=1",
                                                                  expected: "https://host:8080/a"),
                              AttributeScrubberURLTests.ScrubCase(raw: "https://x.test/a",
                                                                  expected: "https://x.test/a")]

    @Test("Without an @ after the authority, the existing rules apply", arguments: anyAtGuards, ["url.full", "link"])
    func atRuleLeavesOrdinaryURLsAlone(_ testCase: AttributeScrubberURLTests.ScrubCase, key: String) {
        #expect(sut.scrub([key: .string(testCase.raw)]) == [key: .string(testCase.expected)])
    }

    // MARK: More wrapper characters

    static let wrapperCases = [AttributeScrubberURLTests.ScrubCase(raw: "\u{2060}mailto:jane@x.com",
                                                                   expected: "\u{2060}mailto:REDACTED"),
                               AttributeScrubberURLTests.ScrubCase(raw: "\u{200C}mailto:jane@x.com",
                                                                   expected: "\u{200C}mailto:REDACTED"),
                               AttributeScrubberURLTests.ScrubCase(raw: "\u{200D}tel:+1555",
                                                                   expected: "\u{200D}tel:REDACTED"),
                               AttributeScrubberURLTests.ScrubCase(raw: "`https://u:p@h/a?q",
                                                                   expected: "`https://REDACTED:REDACTED@h/a"),
                               AttributeScrubberURLTests.ScrubCase(raw: "\u{200C}\u{200D}\u{2060}`https://u:p@h/a?q",
                                                                   expected: "\u{200C}\u{200D}\u{2060}`https://REDACTED:REDACTED@h/a")]

    @Test("U+200C, U+200D, U+2060 and a backtick are ignored for detection and kept as a prefix",
          arguments: wrapperCases, ["link", "url.full"])
    func scrubsValuesWrappedInMoreCharacters(_ testCase: AttributeScrubberURLTests.ScrubCase, key: String) {
        #expect(sut.scrub([key: .string(testCase.raw)]) == [key: .string(testCase.expected)])
    }

    @Test("Text that merely contains a backtick or invisible characters is unchanged",
          arguments: ["`code`", "`", "\u{200C}\u{200D}\u{2060}", "`see https://h/a?q`"])
    func backtickTextUnchanged(value: String) {
        let input: TraceAttributes = ["note": .string(value)]

        #expect(sut.scrub(input) == input)
    }

    // MARK: sip, sips, xmpp, im

    static let messagingCases = [AttributeScrubberURLTests.ScrubCase(raw: "sip:alice@example.com",
                                                                     expected: "sip:REDACTED"),
                                 AttributeScrubberURLTests.ScrubCase(raw: "SIPS:alice@example.com",
                                                                     expected: "sips:REDACTED"),
                                 AttributeScrubberURLTests.ScrubCase(raw: "xmpp:alice@example.com?message",
                                                                     expected: "xmpp:REDACTED"),
                                 AttributeScrubberURLTests.ScrubCase(raw: "XMPP:alice@example.com",
                                                                     expected: "xmpp:REDACTED"),
                                 AttributeScrubberURLTests.ScrubCase(raw: "im:alice@example.com",
                                                                     expected: "im:REDACTED"),
                                 AttributeScrubberURLTests.ScrubCase(raw: "Im:alice@example.com",
                                                                     expected: "im:REDACTED")]

    @Test("sip:, sips:, xmpp: and im: values are replaced whole, under any key",
          arguments: messagingCases, ["link", "url.full", "target"])
    func redactsMessagingSchemes(_ testCase: AttributeScrubberURLTests.ScrubCase, key: String) {
        #expect(sut.scrub([key: .string(testCase.raw)]) == [key: .string(testCase.expected)])
    }

    @Test("Values that merely resemble sip, sips, xmpp or im are unchanged",
          arguments: ["image:x", "sipx:y", "imx:z", "xmpps:q", "sip", "im", "simple:x", "xmp:y"])
    func messagingLookalikesUnchanged(value: String) {
        let input: TraceAttributes = ["note": .string(value)]

        #expect(sut.scrub(input) == input)
    }
}
