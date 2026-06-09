package com.example.reportextractionservice.domain.model

/** Eventos de dominio del subsistema de reportería (§6). La serialización vive en infraestructura. */
sealed trait ReportEvent { def reportId: String }

final case class ReportExtracted(
    reportId: String,
    runId: String,
    reportType: String,
    schemaVersion: String,
    rawParquetUri: String,
    rowCount: Long,
    validatedAt: String
) extends ReportEvent

final case class ReportProcessed(
    reportId: String,
    runId: String,
    reportType: String,
    processedParquetUri: String,
    formats: List[String],
    processedAt: String
) extends ReportEvent

final case class ReportFailed(
    reportId: String,
    stage: String,
    reason: String,
    failedColumns: List[String]
) extends ReportEvent
