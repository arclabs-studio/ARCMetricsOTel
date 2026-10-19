import OpenTelemetrySdk

/// Exporters that replace OTLP/HTTP, for tests.
struct ExporterOverride {
    let spans: any SpanExporter
    let logs: any LogRecordExporter
}
