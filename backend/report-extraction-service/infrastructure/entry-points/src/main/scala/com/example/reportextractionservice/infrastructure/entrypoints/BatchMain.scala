package com.example.reportextractionservice.infrastructure.entrypoints

import com.example.reportextractionservice.application.usecases.ValidateAndExtractUseCase
import com.example.reportextractionservice.domain.model.{ColumnSpec, ReportSchema, ReportType}
import com.example.reportextractionservice.infrastructure.driven.kafkaproducer.KafkaEventPublisher
import com.example.reportextractionservice.infrastructure.driven.s3parquet.SparkS3ParquetAdapter
import com.example.reportextractionservice.infrastructure.driven.jdbcsource.SparkJdbcSourceAdapter
import org.apache.spark.sql.SparkSession

import java.util.UUID

/** MS1 — extracción + validación de esquema. Lee el read model CQRS → valida → parquet `raw/`
 *  → publica `report.extracted` (§3, DR-1). */
object BatchMain {

  def main(args: Array[String]): Unit = {
    val argMap: Map[String, String] =
      args.grouped(2)
        .collect { case Array(k, v) if k.startsWith("--") => k.stripPrefix("--") -> v }
        .toMap

    val spark = buildSpark()
    try {
      val bucket    = sys.env.getOrElse("REPORT_BUCKET", "reports")
      val bootstrap = sys.env.getOrElse("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092")

      val source = new SparkJdbcSourceAdapter(
        spark,
        sys.env.getOrElse("JDBC_URL", "jdbc:postgresql://localhost:5432/app"),
        sys.env.getOrElse("JDBC_TABLE", "ventas"),
        sys.env.getOrElse("JDBC_USER", "app"),
        sys.env.getOrElse("JDBC_PASSWORD", "app")
      )

      val store  = new SparkS3ParquetAdapter(spark, bucket)
      val events = new KafkaEventPublisher(bootstrap)
      val useCase = new ValidateAndExtractUseCase(source, store, events, "report.extracted")

      val reportType = ReportType.fromString(argMap.getOrElse("reportType", "ventas-mensual"))
      val reportId   = argMap.getOrElse("reportId", UUID.randomUUID().toString)
      val runId      = UUID.randomUUID().toString

      // TODO: resolver el ReportSchema vigente desde report_schema_catalog (§9.2).
      val schema = ReportSchema(
        reportType,
        version = "v1",
        columns = List(
          ColumnSpec("id", "string", nullable = false)
          // TODO: declarar las columnas reales del reporte.
        ),
        integrityRules = List.empty
      )

      try {
        useCase.execute(schema, reportId, runId)
      } finally {
        events.close()
      }
    } finally {
      spark.stop()
    }
  }

  private def buildSpark(): SparkSession = {
    val builder = SparkSession.builder
      .appName("report-extraction-service")
      .master(sys.env.getOrElse("SPARK_MASTER", "local[*]"))
    val endpoint = sys.env.getOrElse("AWS_ENDPOINT_URL", "")
    val spark = builder.getOrCreate()
    val hc = spark.sparkContext.hadoopConfiguration
    if (endpoint.nonEmpty) hc.set("fs.s3a.endpoint", endpoint)
    hc.set("fs.s3a.path.style.access", "true")
    hc.set("fs.s3a.access.key", sys.env.getOrElse("AWS_ACCESS_KEY_ID", "test"))
    hc.set("fs.s3a.secret.key", sys.env.getOrElse("AWS_SECRET_ACCESS_KEY", "test"))
    hc.set("fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem")
    spark
  }
}
