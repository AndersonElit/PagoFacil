package com.example.reportextractionservice.application.usecases

import com.example.reportextractionservice.domain.model._
import com.example.reportextractionservice.domain.ports._
import org.apache.spark.sql.functions.col

/** MS1: valida el DataFrame de origen contra el `ReportSchema` declarado (DR-1),
 *  materializa parquet crudo en `raw/` y publica `report.extracted`.
 *  Si la validación falla ⇒ publica `report.extraction.failed` y falla rápido. */
class ValidateAndExtractUseCase(
    source: SourceDataPort,
    store: ParquetStorePort,
    events: EventBusPort,
    outTopic: String = "report.extracted"
) {

  def execute(schema: ReportSchema, reportId: String, runId: String): Unit = {
    val df = source.read()
    val actual = df.columns.toSet

    val missing = schema.columnNames.diff(actual)
    if (missing.nonEmpty) {
      fail(reportId, "extraction", "missing columns", missing.toList)
      throw new IllegalStateException(s"Schema validation failed: missing columns $missing")
    }

    val nullViolations = schema.notNullColumns.filter { c =>
      actual.contains(c) && df.filter(col(c).isNull).limit(1).count() > 0
    }
    if (nullViolations.nonEmpty) {
      fail(reportId, "extraction", "null values in non-nullable columns", nullViolations)
      throw new IllegalStateException(s"Integrity validation failed: nulls in $nullViolations")
    }

    val uri = store.writeRaw(schema.reportType.value, reportId, df)
    val rowCount = df.count()
    val payload =
      s"""{"reportId":"$reportId","runId":"$runId","reportType":"${schema.reportType.value}",""" +
      s""""schemaVersion":"${schema.version}","rawParquetUri":"$uri","rowCount":$rowCount,""" +
      s""""validatedAt":"${java.time.Instant.now()}"}"""
    events.publish(outTopic, reportId, payload)
  }

  private def fail(reportId: String, stage: String, reason: String, cols: List[String]): Unit = {
    val arr = cols.map(c => "\"" + c + "\"").mkString(",")
    val payload =
      s"""{"reportId":"$reportId","stage":"$stage","reason":"$reason","failedColumns":[$arr]}"""
    events.publish("report.extraction.failed", reportId, payload)
  }
}
