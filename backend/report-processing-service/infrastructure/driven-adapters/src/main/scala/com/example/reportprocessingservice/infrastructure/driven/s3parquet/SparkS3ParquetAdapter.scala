package com.example.reportprocessingservice.infrastructure.driven.s3parquet

import com.example.reportprocessingservice.domain.ports.ParquetStorePort
import org.apache.spark.sql.{DataFrame, SaveMode, SparkSession}

/** Lee/escribe parquet en S3 (floci en dev, AWS real en prod). Layout §9.1.
 *  Idempotente por `reportId` con sobrescritura determinista (DR-3). */
class SparkS3ParquetAdapter(spark: SparkSession, bucket: String) extends ParquetStorePort {

  override def writeRaw(reportType: String, reportId: String, df: DataFrame): String = {
    val uri = s"s3a://$bucket/raw/$reportType/$reportId/"
    df.write.mode(SaveMode.Overwrite).parquet(uri)
    uri
  }

  override def readRaw(uri: String): DataFrame =
    spark.read.parquet(uri)

  override def writeProcessed(reportType: String, reportId: String, df: DataFrame): String = {
    val uri = s"s3a://$bucket/processed/$reportType/$reportId/"
    df.write.mode(SaveMode.Overwrite).parquet(uri)
    uri
  }
}
