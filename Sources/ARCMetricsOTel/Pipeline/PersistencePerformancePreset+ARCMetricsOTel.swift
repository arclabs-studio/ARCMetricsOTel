import PersistenceExporter

extension PersistencePerformancePreset {
    /// The disk buffer's limits.
    ///
    /// Upstream's default keeps up to 512 MB for 18 hours and retries every 20 seconds at most.
    /// Telemetry is not worth that much of a user's storage or radio: this keeps 16 MB for 6 hours
    /// and backs off to one attempt a minute. An object (one batch, see
    /// `PipelineFactory.maxExportBatchSize`) may be up to 1 MB, the size of a file.
    static let arcMetricsOTel = PersistencePerformancePreset(maxFileSize: 1024 * 1024,
                                                             maxDirectorySize: 16 * 1024 * 1024,
                                                             maxFileAgeForWrite: 4.75,
                                                             minFileAgeForRead: 4.75 + 0.5,
                                                             maxFileAgeForRead: 6 * 60 * 60,
                                                             maxObjectsInFile: 500,
                                                             maxObjectSize: 1024 * 1024,
                                                             synchronousWrite: false,
                                                             initialExportDelay: 5,
                                                             defaultExportDelay: 5,
                                                             minExportDelay: 1,
                                                             maxExportDelay: 60,
                                                             exportDelayChangeRate: 0.1)
}
