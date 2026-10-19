import Testing

extension Tag {
    /// Pure logic, no I/O beyond the temporary directory or an isolated `UserDefaults` suite.
    @Tag static var unit: Self

    /// The real pipeline wired through `OTelBootstrap`, with transport or exporters replaced.
    @Tag static var integration: Self

    /// Backs an acceptance criterion of FVRS-348.
    @Tag static var critical: Self
}
