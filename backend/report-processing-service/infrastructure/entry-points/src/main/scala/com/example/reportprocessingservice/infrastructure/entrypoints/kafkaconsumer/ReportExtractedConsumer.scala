package com.example.reportprocessingservice.infrastructure.entrypoints.kafkaconsumer

import com.example.reportprocessingservice.application.usecases.ProcessReportUseCase
import com.example.reportprocessingservice.domain.model.ReportType
import org.apache.kafka.clients.consumer.KafkaConsumer

import java.time.Duration
import java.util.{Collections, Properties, UUID}
import scala.jdk.CollectionConverters._

/** Entry-point dirigido por evento: consume `report.extracted` (report.extracted) y dispara MS2. */
class ReportExtractedConsumer(
    bootstrapServers: String,
    topicIn: String = "report.extracted",
    groupId: String = "report-processing-service",
    useCase: ProcessReportUseCase
) {

  @volatile private var running = true

  private def buildConsumer(): KafkaConsumer[String, String] = {
    val props = new Properties()
    props.put("bootstrap.servers", bootstrapServers)
    props.put("group.id", groupId)
    props.put("key.deserializer", "org.apache.kafka.common.serialization.StringDeserializer")
    props.put("value.deserializer", "org.apache.kafka.common.serialization.StringDeserializer")
    props.put("auto.offset.reset", "earliest")
    props.put("enable.auto.commit", "true")
    new KafkaConsumer[String, String](props)
  }

  def stop(): Unit = running = false

  def start(): Unit = {
    val consumer = buildConsumer()
    consumer.subscribe(Collections.singletonList(topicIn))
    try {
      while (running) {
        val records = consumer.poll(Duration.ofMillis(1000))
        for (record <- records.asScala) {
          handle(record.value())
        }
      }
    } finally {
      consumer.close()
    }
  }

  private def handle(json: String): Unit = {
    val reportType = field(json, "reportType").getOrElse("")
    val reportId   = field(json, "reportId").getOrElse(UUID.randomUUID().toString)
    val runId      = field(json, "runId").getOrElse(UUID.randomUUID().toString)
    val rawUri     = field(json, "rawParquetUri").getOrElse("")
    // Por defecto los 3 formatos; un proyecto puede derivarlos del catálogo.
    val formats    = List("PDF", "XLS", "CSV")
    useCase.execute(ReportType.fromString(reportType), reportId, runId, rawUri, formats)
  }

  // Extracción mínima de campos JSON (sustituible por una librería en endurecimiento).
  private def field(json: String, key: String): Option[String] = {
    val pattern = ("\"" + key + "\"\\s*:\\s*\"([^\"]*)\"").r
    pattern.findFirstMatchIn(json).map(_.group(1))
  }
}
