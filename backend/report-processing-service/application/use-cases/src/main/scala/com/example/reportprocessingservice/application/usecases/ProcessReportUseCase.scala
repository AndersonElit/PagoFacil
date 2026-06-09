package com.example.reportprocessingservice.application.usecases

import com.example.reportprocessingservice.domain.model.ReportType
import com.example.reportprocessingservice.domain.ports._

/** MS2: resuelve el transformer por `reportType` vía factory, transforma el parquet `raw/`
 *  y materializa `processed/`, publicando `report.processed`. */
class ProcessReportUseCase(
    factory: ReportTransformerFactory,
    store: ParquetStorePort,
    events: EventBusPort,
    outTopic: String = "report.processed"
) {

  def execute(
      reportType: ReportType,
      reportId: String,
      runId: String,
      rawUri: String,
      formats: List[String]
  ): Unit = {
    try {
      val transformer = factory.resolve(reportType)
      val raw = store.readRaw(rawUri)
      val processed = transformer.transform(raw)
      val uri = store.writeProcessed(reportType.value, reportId, processed)
      val fmts = formats.map(f => "\"" + f + "\"").mkString(",")
      val payload =
        s"""{"reportId":"$reportId","runId":"$runId","reportType":"${reportType.value}",""" +
        s""""processedParquetUri":"$uri","formats":[$fmts],""" +
        s""""processedAt":"${java.time.Instant.now()}"}"""
      events.publish(outTopic, reportId, payload)
    } catch {
      case e: UnsupportedReportTypeException =>
        val payload =
          s"""{"reportId":"$reportId","stage":"processing","reason":"${e.getMessage}","failedColumns":[]}"""
        events.publish("report.processing.failed", reportId, payload)
        throw e
    }
  }
}
