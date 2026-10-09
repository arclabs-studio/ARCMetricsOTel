import Foundation

/// A minimal protobuf wire-format reader for the OTLP export requests.
///
/// Upstream sends `application/x-protobuf` whatever `exportAsJson` says, and the test target
/// cannot reach the generated message types, so the bodies are decoded by hand from the
/// published `opentelemetry-proto` field numbers. That keeps the oracle independent of the
/// exporter's own encoder.
enum OTLPDecoder {
    struct Span {
        let name: String
        let traceID: Data
        let spanID: Data
        let parentSpanID: Data
        let attributes: [String: String]
    }

    struct LogRecord {
        let eventName: String
        let severityNumber: Int
        let attributes: [String: String]
    }

    struct Traces {
        var resourceAttributes: [String: String] = [:]
        var spans: [Span] = []
    }

    struct Logs {
        var resourceAttributes: [String: String] = [:]
        var records: [LogRecord] = []
    }

    // MARK: Requests

    /// `ExportTraceServiceRequest`: `resource_spans = 1`.
    static func traces(from body: Data) -> Traces {
        var result = Traces()
        for resourceSpans in fields(body, number: 1) {
            // ResourceSpans: resource = 1, scope_spans = 2.
            for resource in fields(resourceSpans.bytes, number: 1) {
                result.resourceAttributes.merge(attributes(resource.bytes, number: 1)) { _, new in new }
            }
            for scopeSpans in fields(resourceSpans.bytes, number: 2) {
                // ScopeSpans: spans = 2.
                result.spans += fields(scopeSpans.bytes, number: 2).map { span(from: $0.bytes) }
            }
        }
        return result
    }

    /// `ExportLogsServiceRequest`: `resource_logs = 1`.
    static func logs(from body: Data) -> Logs {
        var result = Logs()
        for resourceLogs in fields(body, number: 1) {
            // ResourceLogs: resource = 1, scope_logs = 2.
            for resource in fields(resourceLogs.bytes, number: 1) {
                result.resourceAttributes.merge(attributes(resource.bytes, number: 1)) { _, new in new }
            }
            for scopeLogs in fields(resourceLogs.bytes, number: 2) {
                // ScopeLogs: log_records = 2.
                result.records += fields(scopeLogs.bytes, number: 2).map { logRecord(from: $0.bytes) }
            }
        }
        return result
    }

    // MARK: Messages

    /// Span: trace_id = 1, span_id = 2, parent_span_id = 4, name = 5, attributes = 9.
    private static func span(from data: Data) -> Span {
        Span(name: string(data, number: 5),
             traceID: fields(data, number: 1).first?.bytes ?? Data(),
             spanID: fields(data, number: 2).first?.bytes ?? Data(),
             parentSpanID: fields(data, number: 4).first?.bytes ?? Data(),
             attributes: attributes(data, number: 9))
    }

    /// LogRecord: severity_number = 2, attributes = 6, event_name = 12.
    private static func logRecord(from data: Data) -> LogRecord {
        LogRecord(eventName: string(data, number: 12),
                  severityNumber: Int(fields(data, number: 2).first?.varint ?? 0),
                  attributes: attributes(data, number: 6))
    }

    /// Repeated KeyValue (key = 1, value = 2) → AnyValue (string_value = 1, bool = 2, int = 3).
    private static func attributes(_ data: Data, number: Int) -> [String: String] {
        var result: [String: String] = [:]
        for pair in fields(data, number: number) {
            let key = string(pair.bytes, number: 1)
            guard let value = fields(pair.bytes, number: 2).first else { continue }
            if let text = fields(value.bytes, number: 1).first {
                result[key] = String(bytes: text.bytes, encoding: .utf8) ?? ""
            } else if let flag = fields(value.bytes, number: 2).first {
                result[key] = flag.varint == 0 ? "false" : "true"
            } else if let integer = fields(value.bytes, number: 3).first {
                result[key] = String(Int64(bitPattern: integer.varint))
            }
        }
        return result
    }

    private static func string(_ data: Data, number: Int) -> String {
        fields(data, number: number).first.map { String(bytes: $0.bytes, encoding: .utf8) ?? "" } ?? ""
    }

    // MARK: Wire format

    struct Field {
        let number: Int
        let varint: UInt64
        let bytes: Data
    }

    /// Every top-level field called `number`, in order. Stops quietly at malformed input.
    static func fields(_ data: Data, number: Int) -> [Field] {
        let bytes = [UInt8](data)
        var index = 0
        var result: [Field] = []
        while index < bytes.count {
            guard let tag = varint(bytes, &index) else { break }
            let fieldNumber = Int(tag >> 3)
            var field = Field(number: fieldNumber, varint: 0, bytes: Data())
            switch tag & 0x7 {
            case 0:
                guard let value = varint(bytes, &index) else { return result }
                field = Field(number: fieldNumber, varint: value, bytes: Data())
            case 1:
                index += 8
            case 2:
                guard let length = varint(bytes, &index), index + Int(length) <= bytes.count else { return result }
                field = Field(number: fieldNumber, varint: 0, bytes: Data(bytes[index ..< index + Int(length)]))
                index += Int(length)
            case 5:
                index += 4
            default:
                return result
            }
            if fieldNumber == number, tag & 0x7 == 0 || tag & 0x7 == 2 {
                result.append(field)
            }
        }
        return result
    }

    private static func varint(_ bytes: [UInt8], _ index: inout Int) -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while index < bytes.count, shift < 64 {
            let byte = bytes[index]
            index += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 {
                return result
            }
            shift += 7
        }
        return nil
    }
}
