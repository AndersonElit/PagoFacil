package com.example.reportprocessingservice.infrastructure.entrypoints

import com.example.reportprocessingservice.application.usecases.{ProcessReportUseCase, ReportTransformer, ReportTransformerFactory}
import com.example.reportprocessingservice.domain.model.ReportType
import com.example.reportprocessingservice.infrastructure.driven.kafkaproducer.KafkaEventPublisher
import com.example.reportprocessingservice.infrastructure.driven.s3parquet.SparkS3ParquetAdapter
import com.example.reportprocessingservice.infrastructure.entrypoints.kafkaconsumer.ReportExtractedConsumer
import com.example.reportprocessingservice.application.usecases.transformers.TransactionsTransformer
import com.example.reportprocessingservice.application.usecases.transformers.ComplianceAlertsTransformer
import com.example.reportprocessingservice.application.usecases.transformers.UsersTransformer
import org.apache.spark.sql.SparkSession

/** MS2 — transformación por tipo de reporte (modo triggered-by-event).
 *  Cablea la ReportTransformerFactory con los tipos registrados (DR-10) y arranca el consumer. */
object BatchMain {

  def main(args: Array[String]): Unit = {
    val spark = buildSpark()
    val bucket    = sys.env.getOrElse("REPORT_BUCKET", "reports")
    val bootstrap = sys.env.getOrElse("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092")
    val topicIn   = sys.env.getOrElse("KAFKA_TOPIC_IN", "report.extracted")

    val store  = new SparkS3ParquetAdapter(spark, bucket)
    val events = new KafkaEventPublisher(bootstrap)

      val t0 = new TransactionsTransformer()
      val t1 = new ComplianceAlertsTransformer()
      val t2 = new UsersTransformer()
    val registry: Map[ReportType, ReportTransformer] = Map(t0.reportType -> t0, t1.reportType -> t1, t2.reportType -> t2)
    val factory = new ReportTransformerFactory(registry)
    val useCase = new ProcessReportUseCase(factory, store, events, "report.processed")

    val consumer = new ReportExtractedConsumer(bootstrap, topicIn, "report-processing-service", useCase)
    sys.addShutdownHook {
      consumer.stop()
      events.close()
      spark.stop()
    }
    consumer.start()
  }

  private def buildSpark(): SparkSession = {
    val builder = SparkSession.builder
      .appName("report-processing-service")
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
