/// Why ``OTelBootstrap/configure(_:)`` could not build the pipeline.
public enum OTelBootstrapError: Error, Equatable {
    /// The endpoint has no host, or its scheme is neither `http` nor `https`.
    case invalidEndpoint

    /// The endpoint is plain `http` on a non-loopback host and
    /// ``OTelConfiguration/allowsInsecureTransport`` is `false`.
    case insecureEndpoint

    /// The on-disk buffer directory could not be created.
    case storageUnavailable
}
