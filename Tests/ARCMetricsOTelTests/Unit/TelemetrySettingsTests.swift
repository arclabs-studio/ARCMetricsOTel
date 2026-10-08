import Testing
@testable import ARCMetricsOTel

@Suite("TelemetrySettings", .tags(.unit)) struct TelemetrySettingsTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let input: Double
        let expected: Double
        var testDescription: String {
            "\(input) -> \(expected)"
        }
    }

    static let cases = [Case(input: 1.7, expected: 1),
                        Case(input: -0.2, expected: 0),
                        Case(input: 0.4, expected: 0.4),
                        Case(input: .nan, expected: 0),
                        Case(input: .infinity, expected: 1),
                        Case(input: -.infinity, expected: 0)]

    @Test("Sample rate is clamped to 0...1 and NaN becomes 0", arguments: cases)
    func sampleRateIsClamped(_ testCase: Case) {
        // Given a rate from a remote flag, possibly out of range
        // When the settings are created
        let settings = TelemetrySettings(isEnabled: true, sampleRate: testCase.input)

        // Then the stored rate is usable as a probability
        #expect(settings.sampleRate == testCase.expected)
    }

    @Test("Clamping keeps the kill switch untouched") func clampingKeepsSwitch() {
        let settings = TelemetrySettings(isEnabled: false, sampleRate: 7)

        #expect(settings.isEnabled == false)
        #expect(settings.sampleRate == 1)
    }
}
