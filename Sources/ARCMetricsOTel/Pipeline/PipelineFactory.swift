import Foundation
import OpenTelemetryApi
import OpenTelemetryProtocolExporterCommon
import OpenTelemetryProtocolExporterHttp
import OpenTelemetrySdk
import PersistenceExporter

/// Builds a ``Pipeline``.
///
/// The OTLP exporters are created with `requeueOnFailure: false` (the disk buffer already
/// retries; requeueing too would deliver twice), `envVarHeaders: nil` (never read headers from
/// the process environment) and an ``OTLPHTTPClient`` over the injected `URLSession`.
enum PipelineFactory {
    /// The instrumentation scope name on every span and log record.
    static let scopeName = "ARCMetricsOTel"

    /// Prepares `storage` and builds the pipeline.
    ///
    /// - Throws: ``OTelBootstrapError/storageUnavailable`` when the buffer directories cannot be created.
    static func make(configuration: OTelConfiguration,
                     dependencies: OTelDependencies,
                     gate: TelemetryGate,
                     storage: StorageLocation) throws(OTelBootstrapError) -> Pipeline {
        do {
            try storage.prepare()
        } catch {
            throw .storageUnavailable
        }
        let timeout = configuration.exportTimeout.timeInterval
        let device = DeviceInfo.current(environment: dependencies.environment,
                                        operatingSystemVersion: dependencies.operatingSystemVersion,
                                        machine: dependencies.machine)
        let resource = ResourceBuilder.make(configuration: configuration, device: device)
        let exporters = dependencies.exporters ?? otlpExporters(configuration: configuration,
                                                                dependencies: dependencies)
        let allowsExport: @Sendable () -> Bool = { gate.allowsExport }

        let spanBuffer = PersistenceSpanExporterDecorator(spanExporter: GatedSpanExporter(inner: exporters.spans,
                                                                                          gate: gate),
                                                          storageURL: storage.traces,
                                                          exportCondition: allowsExport,
                                                          performancePreset: dependencies.performancePreset)
        let logBuffer = PersistenceLogExporterDecorator(logRecordExporter: GatedLogExporter(inner: exporters.logs,
                                                                                            gate: gate),
                                                        storageURL: storage.logs,
                                                        exportCondition: allowsExport,
                                                        performancePreset: dependencies.performancePreset)
        let spanProcessor = BatchSpanProcessor(spanExporter: spanBuffer,
                                               scheduleDelay: dependencies.scheduleDelay,
                                               exportTimeout: timeout)
        let logProcessor = BatchLogRecordProcessor(logRecordExporter: logBuffer,
                                                   scheduleDelay: dependencies.scheduleDelay,
                                                   exportTimeout: timeout)
        let tracerProvider = TracerProviderBuilder()
            .with(resource: resource)
            .with(sampler: SessionSampler(gate: gate))
            .add(spanProcessor: spanProcessor)
            .build()
        let loggerProvider = LoggerProviderBuilder()
            .with(resource: resource)
            .with(processors: [logProcessor])
            .build()
        return Pipeline(tracerProvider: tracerProvider,
                        loggerProvider: loggerProvider,
                        tracer: tracerProvider.get(instrumentationName: scopeName),
                        logger: loggerProvider.loggerBuilder(instrumentationScopeName: scopeName).build(),
                        spanProcessor: spanProcessor,
                        logProcessor: logProcessor,
                        spanBuffer: spanBuffer,
                        logBuffer: logBuffer)
    }
}

// MARK: - OTLP

private extension PipelineFactory {
    static func otlpExporters(configuration: OTelConfiguration,
                              dependencies: OTelDependencies) -> ExporterOverride {
        let headers = configuration.headers.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        let config = OtlpConfiguration(timeout: configuration.exportTimeout.timeInterval,
                                       compression: dependencies.compression,
                                       headers: headers)
        let client = OTLPHTTPClient(session: dependencies.urlSession)
        let spans = OtlpHttpTraceExporter(endpoint: configuration.endpoint.appending(path: "v1/traces"),
                                          config: config,
                                          httpClient: client,
                                          envVarHeaders: nil,
                                          requeueOnFailure: false)
        let logs = OtlpHttpLogExporter(endpoint: configuration.endpoint.appending(path: "v1/logs"),
                                       config: config,
                                       httpClient: client,
                                       envVarHeaders: nil,
                                       requeueOnFailure: false)
        return ExporterOverride(spans: spans, logs: logs)
    }
}
